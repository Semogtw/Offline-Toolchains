import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../firebase_sync_client.dart';
import '../../user_sync_service.dart';
import 'manga_firebase_sync_client.dart';
import 'manga_sync_local_store.dart';
import 'manga_sync_record.dart';

final class MangaAccountSyncService {
  MangaAccountSyncService({
    UserSyncService? userSyncService,
    MangaFirebaseSyncClient? firebaseClient,
    MangaSyncLocalStore? localStore,
  }) : _userSyncService = userSyncService ?? UserSyncService.instance,
       _firebaseClient = firebaseClient ?? MangaFirebaseSyncClient(),
       _localStore = localStore ?? MangaSyncLocalStore();

  static final MangaAccountSyncService instance = MangaAccountSyncService();

  static const String _queueKey = 'sync.manga.pending.queue';
  static const Duration _pullTtl = Duration(seconds: 60);
  static const Duration _postWritePullDelay = Duration(seconds: 8);

  final UserSyncService _userSyncService;
  final MangaFirebaseSyncClient _firebaseClient;
  final MangaSyncLocalStore _localStore;

  bool _initialized = false;
  int _pendingCount = 0;
  Future<void> _queueMutationQueue = Future<void>.value();
  Future<void>? _flushFuture;
  Future<void>? _syncFuture;
  Timer? _postWritePullTimer;
  DateTime? _lastPullAt;
  String? _observedUid;
  DateTime? _observedAnimeSyncAt;

  bool get isInitialized => _initialized;
  int get pendingCount => _pendingCount;
  DateTime? get lastPullAt => _lastPullAt;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _pendingCount = _readQueue(prefs).length;
    _observedUid = _userSyncService.session?.uid;
    _observedAnimeSyncAt = _userSyncService.lastSyncedAt;
    _userSyncService.addListener(_handleUserSyncChanged);
    if (_canUseRemote) {
      _synchronizeBestEffort(pullGatedByPullTtl: false);
    }
  }

  Future<void> record(MangaSyncRecord record) async {
    if (!_initialized) await initialize();
    await _enqueue(record);
    if (!_canUseRemote) return;
    _flushBestEffort();
    _schedulePostWritePull();
  }

  Future<void> synchronize({bool pullGatedByPullTtl = false}) {
    final active = _syncFuture;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _runSynchronize(pullGatedByPullTtl: pullGatedByPullTtl)
        .whenComplete(() {
          if (identical(_syncFuture, operation)) _syncFuture = null;
        });
    _syncFuture = operation;
    return operation;
  }

  Future<void> _runSynchronize({required bool pullGatedByPullTtl}) async {
    if (!_canUseRemote) return;
    await flushPending();
    // Never pull old remote state over a local mutation that could not be
    // uploaded. This is especially important for deletion tombstones because
    // the active row no longer exists locally to win a subsequent merge.
    if (_pendingCount > 0) return;
    if (!pullGatedByPullTtl || !_isLastPullWithinTtl()) {
      await pullRemoteState();
    }
  }

  Future<void> syncAfterAppResumed() async {
    if (!_initialized) await initialize();
    if (!_canUseRemote) return;
    await synchronize(pullGatedByPullTtl: true);
  }

  Future<void> flushPending() {
    if (!_canUseRemote) return Future<void>.value();
    final active = _flushFuture;
    if (active != null) return active;

    late final Future<void> operation;
    operation = _flushPendingOnce().whenComplete(() async {
      try {
        await _compactPersistedQueue();
      } finally {
        if (identical(_flushFuture, operation)) _flushFuture = null;
      }
    });
    _flushFuture = operation;
    return operation;
  }

  Future<void> _flushPendingOnce() async {
    await _queueMutationQueue;
    final prefs = await SharedPreferences.getInstance();
    final snapshot = _readQueue(prefs);
    if (snapshot.isEmpty) {
      _pendingCount = 0;
      return;
    }

    final remaining = <MangaSyncRecord>[];
    for (final record in snapshot) {
      try {
        await _saveWithAuthRetry(record);
      } catch (error) {
        debugPrint(
          '[MangaSync] Pending write preserved after ${error.runtimeType}.',
        );
        remaining.add(record);
      }
    }

    await _serializeQueueMutation(() async {
      final current = _readQueue(prefs);
      final appended = _recordsAppendedAfterSnapshot(
        snapshot: snapshot,
        current: current,
      );
      final next = _compactQueue(<MangaSyncRecord>[...remaining, ...appended]);
      if (!await prefs.setString(
        _queueKey,
        jsonEncode(next.map((record) => record.toJson()).toList()),
      )) {
        throw StateError('Manga pending sync queue was not persisted.');
      }
      _pendingCount = next.length;
    });
  }

  Future<void> pullRemoteState({bool retryOnAuthError = true}) async {
    if (!_canUseRemote) return;
    try {
      final remoteRecords = await _fetchWithAuthRetry(
        retryOnAuthError: retryOnAuthError,
      );
      final remoteByKey = <String, MangaSyncRecord>{};
      for (final record in remoteRecords) {
        final existing = remoteByKey[record.recordKey];
        remoteByKey[record.recordKey] = existing == null
            ? record
            : MangaSyncRecord.latest(existing, record);
      }
      final localByKey = await _localStore.loadAll();
      final keys = <String>{...remoteByKey.keys, ...localByKey.keys};

      for (final key in keys) {
        final local = localByKey[key];
        final remote = remoteByKey[key];
        if (local == null && remote != null) {
          await _localStore.applyRemote(remote);
          continue;
        }
        if (remote == null && local != null) {
          await _saveWithAuthRetry(local);
          continue;
        }
        if (local == null || remote == null) continue;
        if (local.syncContentEquals(remote)) continue;

        final winner = MangaSyncRecord.latest(local, remote);
        if (identical(winner, remote)) {
          await _localStore.applyRemote(remote);
        } else {
          await _saveWithAuthRetry(local);
        }
      }
      _lastPullAt = DateTime.now().toUtc();
    } on FirebaseSyncException catch (error) {
      debugPrint(
        '[MangaSync] Remote pull failed (${error.runtimeType}); local state kept.',
      );
      rethrow;
    }
  }

  Future<List<MangaSyncRecord>> _fetchWithAuthRetry({
    required bool retryOnAuthError,
  }) async {
    final session = _userSyncService.session;
    if (session == null) return const <MangaSyncRecord>[];
    try {
      return await _firebaseClient.fetchRecords(session: session);
    } on FirebaseSyncException catch (error) {
      if (!retryOnAuthError || !error.authExpired) rethrow;
      await _refreshSharedSession();
      final refreshed = _userSyncService.session;
      if (refreshed == null) rethrow;
      return _firebaseClient.fetchRecords(session: refreshed);
    }
  }

  Future<void> _saveWithAuthRetry(MangaSyncRecord record) async {
    final session = _userSyncService.session;
    if (session == null) {
      throw const FirebaseSyncException('No shared sync session available.');
    }
    try {
      await _firebaseClient.saveRecord(session: session, record: record);
    } on FirebaseSyncException catch (error) {
      if (!error.authExpired) rethrow;
      await _refreshSharedSession();
      final refreshed = _userSyncService.session;
      if (refreshed == null) rethrow;
      await _firebaseClient.saveRecord(session: refreshed, record: record);
    }
  }

  Future<void> _refreshSharedSession() async {
    // UserSyncService remains the sole owner of Firebase credentials/refresh.
    // Asking it to synchronize refreshes an expired session without Manga ever
    // reading or persisting credentials independently.
    await _userSyncService.synchronize();
  }

  Future<void> _enqueue(MangaSyncRecord record) {
    return _serializeQueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      final queue = _readQueue(prefs)..add(record);
      final compacted = _flushFuture == null ? _compactQueue(queue) : queue;
      if (!await prefs.setString(
        _queueKey,
        jsonEncode(compacted.map((item) => item.toJson()).toList()),
      )) {
        throw StateError('Manga pending sync item was not persisted.');
      }
      _pendingCount = compacted.length;
    });
  }

  Future<void> _compactPersistedQueue() {
    return _serializeQueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      final current = _readQueue(prefs);
      final compacted = _compactQueue(current);
      _pendingCount = compacted.length;
      if (_sameQueue(current, compacted)) return;
      if (!await prefs.setString(
        _queueKey,
        jsonEncode(compacted.map((record) => record.toJson()).toList()),
      )) {
        throw StateError('Compacted Manga sync queue was not persisted.');
      }
    });
  }

  List<MangaSyncRecord> _compactQueue(List<MangaSyncRecord> queue) {
    final order = <String>[];
    final latest = <String, MangaSyncRecord>{};
    for (final record in queue) {
      if (!latest.containsKey(record.recordKey)) order.add(record.recordKey);
      final existing = latest[record.recordKey];
      latest[record.recordKey] = existing == null
          ? record
          : MangaSyncRecord.latest(existing, record);
    }
    return <MangaSyncRecord>[for (final key in order) latest[key]!];
  }

  List<MangaSyncRecord> _recordsAppendedAfterSnapshot({
    required List<MangaSyncRecord> snapshot,
    required List<MangaSyncRecord> current,
  }) {
    if (current.length < snapshot.length) return current;
    for (var index = 0; index < snapshot.length; index++) {
      if (jsonEncode(current[index].toJson()) !=
          jsonEncode(snapshot[index].toJson())) {
        return current;
      }
    }
    return current.skip(snapshot.length).toList(growable: false);
  }

  List<MangaSyncRecord> _readQueue(SharedPreferences prefs) {
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return <MangaSyncRecord>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <MangaSyncRecord>[];
      final records = <MangaSyncRecord>[];
      for (final item in decoded.whereType<Map>()) {
        try {
          records.add(
            MangaSyncRecord.fromJson(Map<String, dynamic>.from(item)),
          );
        } catch (_) {
          // Skip one corrupt queue entry without discarding the rest.
        }
      }
      return records;
    } catch (_) {
      return <MangaSyncRecord>[];
    }
  }

  bool _sameQueue(List<MangaSyncRecord> left, List<MangaSyncRecord> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (jsonEncode(left[index].toJson()) !=
          jsonEncode(right[index].toJson())) {
        return false;
      }
    }
    return true;
  }

  Future<T> _serializeQueueMutation<T>(Future<T> Function() mutation) {
    final completer = Completer<T>();
    _queueMutationQueue = _queueMutationQueue.then((_) async {
      try {
        completer.complete(await mutation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  bool get _canUseRemote =>
      _userSyncService.state != UserSyncConnectionState.disabled &&
      _userSyncService.session != null &&
      _userSyncService.isFirebaseConfigured &&
      _firebaseClient.isConfigured;

  bool _isLastPullWithinTtl() {
    final lastPullAt = _lastPullAt;
    return lastPullAt != null &&
        DateTime.now().toUtc().isBefore(lastPullAt.add(_pullTtl));
  }

  void _handleUserSyncChanged() {
    if (!_initialized) return;
    final uid = _userSyncService.session?.uid;
    final animeSyncAt = _userSyncService.lastSyncedAt;
    final sessionChanged = uid != _observedUid;
    final animeSyncAdvanced = animeSyncAt != _observedAnimeSyncAt;
    _observedUid = uid;
    _observedAnimeSyncAt = animeSyncAt;
    if (_canUseRemote && (sessionChanged || animeSyncAdvanced)) {
      _synchronizeBestEffort(pullGatedByPullTtl: false);
    }
  }

  void _flushBestEffort() {
    unawaited(
      flushPending().catchError((Object error, StackTrace stackTrace) {
        debugPrint(
          '[MangaSync] Automatic flush failed (${error.runtimeType}); queue kept.',
        );
      }),
    );
  }

  void _synchronizeBestEffort({required bool pullGatedByPullTtl}) {
    unawaited(
      synchronize(pullGatedByPullTtl: pullGatedByPullTtl).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint(
          '[MangaSync] Automatic sync failed (${error.runtimeType}); local state kept.',
        );
      }),
    );
  }

  void _schedulePostWritePull() {
    if (!_canUseRemote) return;
    _postWritePullTimer?.cancel();
    _postWritePullTimer = Timer(_postWritePullDelay, () {
      _synchronizeBestEffort(pullGatedByPullTtl: false);
    });
  }

  void dispose() {
    _postWritePullTimer?.cancel();
    _postWritePullTimer = null;
    if (_initialized) _userSyncService.removeListener(_handleUserSyncChanged);
    _initialized = false;
  }
}
