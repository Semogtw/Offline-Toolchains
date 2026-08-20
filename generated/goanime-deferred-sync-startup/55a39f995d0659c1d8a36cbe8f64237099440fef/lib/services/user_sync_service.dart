// ignore_for_file: strict_raw_type
// Existing callbacks/fixtures still rely on implicit async or dynamic JSON shapes; keep new strict rules enabled elsewhere.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_anime_state.dart';
import 'app_work_coordinator.dart';
import 'firebase_sync_client.dart';
import 'myanimelist_sync_service.dart';
import 'remote_push_token_service.dart';
import 'search_history_service.dart';
import 'sync/secure_sync_credential_store.dart';
import 'sync/sync_credential_store.dart';
import 'watch_history_service.dart';
import 'watchlist_service.dart';

enum UserSyncConnectionState { disabled, localOnly, signingIn, synced, failed }

typedef UserSyncEnabledPreferenceWriter =
    Future<bool> Function(String key, bool enabled);
typedef UserSyncQueueWriter = Future<bool> Function(String key, String value);

class UserSyncService extends ChangeNotifier {
  UserSyncService._();

  static final UserSyncService instance = UserSyncService._();

  static const String _queueKey = 'sync.pending.queue';
  static const String _enabledKey = 'sync.enabled';

  FirebaseSyncClient _firebaseClient = FirebaseSyncClient();
  MyAnimeListSyncService _malService = MyAnimeListSyncService();
  RemotePushTokenService _remotePushTokenService =
      RemotePushTokenService.instance;
  SyncCredentialStore _credentialStore = createDefaultSyncCredentialStore();
  UserSyncEnabledPreferenceWriter? _enabledPreferenceWriter;
  UserSyncQueueWriter? _queueWriter;
  bool _enabled = false;
  bool _initialized = false;
  UserSyncConnectionState _state = UserSyncConnectionState.disabled;
  FirebaseAccountSession? _session;
  String? _lastError;
  int _pendingCount = 0;
  Timer? _autoSyncTimer;
  Timer? _postWriteSyncDebounce;
  Future<void> _queueMutationQueue = Future<void>.value();
  Future<void>? _flushFuture;
  bool _flushRequested = false;
  bool _isSynchronizing = false;
  DateTime? _lastSyncedAt;

  UserSyncConnectionState get state => _state;
  FirebaseAccountSession? get session => _session;
  String? get lastError => _lastError;
  int get pendingCount => _pendingCount;
  bool get isSynchronizing => _isSynchronizing;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isInitialized => _initialized;
  bool get isFirebaseConfigured => _firebaseClient.isConfigured;
  bool get isSignedIn => _session != null;
  bool get hasEmailAccount =>
      _session?.isAnonymous == false && (_session?.email?.isNotEmpty ?? false);

  @visibleForTesting
  void debugConfigure({
    FirebaseSyncClient? firebaseClient,
    MyAnimeListSyncService? malService,
    RemotePushTokenService? remotePushTokenService,
    SyncCredentialStore? credentialStore,
    UserSyncEnabledPreferenceWriter? enabledPreferenceWriter,
    UserSyncQueueWriter? queueWriter,
    bool enabled = true,
    FirebaseAccountSession? session,
    UserSyncConnectionState? state,
  }) {
    _firebaseClient = firebaseClient ?? _firebaseClient;
    _malService = malService ?? _malService;
    _remotePushTokenService = remotePushTokenService ?? _remotePushTokenService;
    _credentialStore =
        credentialStore ?? const SharedPreferencesSyncCredentialStore();
    _enabledPreferenceWriter = enabledPreferenceWriter;
    _queueWriter = queueWriter;
    _enabled = enabled;
    _initialized = true;
    _session = session;
    _lastError = null;
    _lastSyncedAt = null;
    _pendingCount = 0;
    _queueMutationQueue = Future<void>.value();
    _flushFuture = null;
    _flushRequested = false;
    _state =
        state ??
        (enabled
            ? session == null
                  ? UserSyncConnectionState.localOnly
                  : UserSyncConnectionState.synced
            : UserSyncConnectionState.disabled);
  }

  Future<void> initialize({
    bool enabledByDefault = true,
    bool deferAnonymousSignIn = false,
  }) async {
    if (_initialized) return;
    _initialized = true;

    if (_credentialStore case final InitializableSyncCredentialStore store) {
      await store.initialize();
    }

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? enabledByDefault;
    _pendingCount = _readQueue(prefs).length;

    final sessionJson = await _credentialStore.readFirebaseSessionJson();
    if (sessionJson != null) {
      try {
        _session = FirebaseAccountSession.fromJson(
          jsonDecode(sessionJson) as Map<String, dynamic>,
        );
      } catch (_) {
        await _credentialStore.deleteFirebaseSession();
      }
    }

    if (!_enabled) {
      _setState(UserSyncConnectionState.disabled);
      return;
    }

    _startAutoSyncTimer();

    if (_session != null) {
      _lastError = null;
      _setState(UserSyncConnectionState.synced);
      unawaited(_registerRemotePushToken());
      _synchronizeBestEffort();
      return;
    }

    if (deferAnonymousSignIn) {
      unawaited(signInAnonymously());
      return;
    }
    await signInAnonymously();
  }

  Future<void> setEnabled(bool enabled) async {
    final persisted = await _persistEnabledPreference(enabled);
    if (!enabled || !persisted) {
      _enabled = false;
      _stopAutoSyncTimer();
      _setState(UserSyncConnectionState.disabled);
      if (!persisted) {
        throw StateError('Sync enabled preference was not persisted.');
      }
      return;
    }

    _enabled = true;
    _startAutoSyncTimer();
    if (_session != null) {
      _lastError = null;
      _setState(UserSyncConnectionState.synced);
      unawaited(_registerRemotePushToken());
      _synchronizeBestEffort();
      return;
    }
    await signInAnonymously();
  }

  Future<bool> _persistEnabledPreference(bool enabled) async {
    try {
      final writer = _enabledPreferenceWriter;
      if (writer != null) return writer(_enabledKey, enabled);
      final prefs = await SharedPreferences.getInstance();
      return prefs.setBool(_enabledKey, enabled);
    } catch (_) {
      return false;
    }
  }

  Future<void> signInAnonymously() async {
    if (!_enabled) return;
    if (!_firebaseClient.isConfigured) {
      _lastError = null;
      _setState(UserSyncConnectionState.localOnly);
      return;
    }

    final previousSession = _session;
    _setState(UserSyncConnectionState.signingIn);
    try {
      final nextSession = await _firebaseClient.signInAnonymously();
      if (nextSession == null) {
        _session = previousSession;
        _setState(UserSyncConnectionState.localOnly);
        return;
      }
      await _credentialStore.writeFirebaseSessionJson(
        jsonEncode(nextSession.toJson()),
      );
      _session = nextSession;
      _lastError = null;
      _setState(UserSyncConnectionState.synced);
      unawaited(_registerRemotePushToken());
      await synchronize();
    } catch (e) {
      _session = previousSession;
      _lastError = e.toString();
      _setState(UserSyncConnectionState.failed);
    }
  }

  Future<void> linkEmailPassword({
    required String email,
    required String password,
  }) async {
    if (!_enabled || email.trim().isEmpty || password.isEmpty) return;
    if (!_firebaseClient.isConfigured) {
      _setState(UserSyncConnectionState.localOnly);
      return;
    }

    final previousSession = _session;
    _setState(UserSyncConnectionState.signingIn);
    try {
      final currentSession =
          previousSession ?? await _firebaseClient.signInAnonymously();
      if (currentSession == null) {
        _session = previousSession;
        _setState(UserSyncConnectionState.localOnly);
        return;
      }
      final nextSession = await _firebaseClient.linkEmailPassword(
        session: currentSession,
        email: email.trim(),
        password: password,
      );
      if (nextSession == null) {
        throw const FirebaseSyncException('Email link returned no session.');
      }
      await _credentialStore.writeFirebaseSessionJson(
        jsonEncode(nextSession.toJson()),
      );
      _session = nextSession;
      _lastError = null;
      _setState(UserSyncConnectionState.synced);
      unawaited(_registerRemotePushToken());
      await synchronize();
    } catch (e) {
      _session = previousSession;
      _lastError = e.toString();
      _setState(UserSyncConnectionState.failed);
    }
  }

  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    if (!_enabled || email.trim().isEmpty || password.isEmpty) return;
    if (!_firebaseClient.isConfigured) {
      _setState(UserSyncConnectionState.localOnly);
      return;
    }

    final previousSession = _session;
    _setState(UserSyncConnectionState.signingIn);
    try {
      final nextSession = await _firebaseClient.signInWithEmailPassword(
        email: email.trim(),
        password: password,
      );
      if (nextSession == null) {
        throw const FirebaseSyncException('Email sign-in returned no session.');
      }
      await _credentialStore.writeFirebaseSessionJson(
        jsonEncode(nextSession.toJson()),
      );
      _session = nextSession;
      _lastError = null;
      _setState(UserSyncConnectionState.synced);
      unawaited(_registerRemotePushToken());
      await synchronize();
    } catch (e) {
      _session = previousSession;
      _lastError = e.toString();
      _setState(UserSyncConnectionState.failed);
    }
  }

  Future<void> signOut() async {
    await _credentialStore.deleteFirebaseSession();
    _session = null;
    _lastError = null;
    _setState(
      _enabled
          ? UserSyncConnectionState.localOnly
          : UserSyncConnectionState.disabled,
    );
  }

  Future<void> saveMyAnimeListToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await _credentialStore.deleteMyAnimeListAccessToken();
    } else {
      await _credentialStore.writeMyAnimeListAccessToken(trimmed);
    }
    notifyListeners();
  }

  Future<bool> hasMyAnimeListToken() async {
    return ((await _credentialStore.readMyAnimeListAccessToken()) ?? '')
        .isNotEmpty;
  }

  Future<void> recordAnimeState(UserAnimeState state) async {
    if (!_initialized || !_enabled) return;
    await _enqueue({'type': 'anime', 'payload': state.toJson()});
    _flushPendingBestEffort();
    _schedulePostWritePull();
  }

  Future<void> recordSearch(String query) async {
    final trimmed = query.trim();
    if (!_initialized || !_enabled || trimmed.isEmpty) return;
    await _enqueue({
      'type': 'search',
      'payload': {
        'query': trimmed,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    });
    _flushPendingBestEffort();
    _schedulePostWritePull();
  }

  Future<void> recordSearchRemoved(String query) async {
    final trimmed = query.trim();
    if (!_initialized || !_enabled || trimmed.isEmpty) return;

    final removedAt = DateTime.now();
    final settingsPayload = {
      'searchRemoved': trimmed,
      'searchUpdatedAt': removedAt.toIso8601String(),
    };
    await _enqueue({'type': 'settings', 'payload': settingsPayload});
    await _enqueue({
      'type': 'search_delete',
      'payload': {'query': trimmed, 'removedAt': removedAt.toIso8601String()},
    });
    _flushPendingBestEffort();
  }

  Future<void> recordSearchHistoryCleared(DateTime clearedAt) async {
    if (!_initialized || !_enabled) return;

    final settingsPayload = {
      'searchHistoryClearedAt': clearedAt.toIso8601String(),
    };
    await _enqueue({'type': 'settings', 'payload': settingsPayload});
    await _enqueue({
      'type': 'search_clear',
      'payload': {'clearedAt': clearedAt.toIso8601String()},
    });
    _flushPendingBestEffort();
  }

  Future<void> recordSettings(Map<String, dynamic> settings) async {
    if (!_initialized || !_enabled) return;
    final payload = Map<String, dynamic>.from(settings);
    payload.putIfAbsent(
      'settingsUpdatedAt',
      () => DateTime.now().toIso8601String(),
    );
    await _enqueue({'type': 'settings', 'payload': payload});
    _flushPendingBestEffort();
  }

  Future<void> flushPending() {
    if (!_enabled) return Future<void>.value();
    final activeFlush = _flushFuture;
    if (activeFlush != null) {
      _flushRequested = true;
      return activeFlush;
    }

    late final Future<void> operation;
    operation = _runFlushLoop().whenComplete(() async {
      try {
        await _compactPendingAnimeQueue();
      } finally {
        if (identical(_flushFuture, operation)) {
          _flushFuture = null;
        }
      }
    });
    _flushFuture = operation;
    return operation;
  }

  void _flushPendingBestEffort() {
    unawaited(
      flushPending().catchError((Object error, StackTrace stackTrace) {
        _handleAutomaticFailure('flush', error);
      }),
    );
  }

  Future<void> _runFlushLoop() async {
    do {
      _flushRequested = false;
      await _flushPendingOnce();
    } while (_enabled && _flushRequested);
  }

  Future<void> _flushPendingOnce() async {
    await _ensureFreshSession();
    await _queueMutationQueue;

    final prefs = await SharedPreferences.getInstance();
    final queue = _readQueue(prefs);
    if (queue.isEmpty) {
      _pendingCount = 0;
      notifyListeners();
      return;
    }

    final remaining = <Map<String, dynamic>>[];
    for (final item in queue) {
      try {
        await _syncQueueItem(item);
      } on FirebaseSyncException catch (e) {
        if (e.authExpired && await _refreshSession()) {
          try {
            await _syncQueueItem(item);
            continue;
          } catch (retryError) {
            _lastError = retryError.toString();
          }
        } else {
          _lastError = e.toString();
        }
        remaining.add(item);
      } catch (e) {
        _lastError = e.toString();
        remaining.add(item);
      }
    }

    _pendingCount = await _persistFlushResult(
      prefs,
      snapshot: queue,
      remaining: remaining,
    );
    if (_pendingCount == 0) {
      _lastError = null;
    }
    if (_pendingCount == 0 && _state == UserSyncConnectionState.failed) {
      _setState(
        _session == null
            ? UserSyncConnectionState.localOnly
            : UserSyncConnectionState.synced,
      );
    } else {
      notifyListeners();
    }
  }

  Future<int> _persistFlushResult(
    SharedPreferences prefs, {
    required List<Map<String, dynamic>> snapshot,
    required List<Map<String, dynamic>> remaining,
  }) {
    return _serializeQueueMutation(() async {
      final current = _readQueue(prefs);
      final appended = _itemsAppendedAfterSnapshot(
        snapshot: snapshot,
        current: current,
      );
      final nextQueue = <Map<String, dynamic>>[...remaining, ...appended];
      final persisted = await _writeQueue(prefs, jsonEncode(nextQueue));
      if (!persisted) {
        throw StateError('Pending sync queue was not persisted.');
      }
      return nextQueue.length;
    });
  }

  List<Map<String, dynamic>> _itemsAppendedAfterSnapshot({
    required List<Map<String, dynamic>> snapshot,
    required List<Map<String, dynamic>> current,
  }) {
    if (current.length < snapshot.length) return current;
    for (var index = 0; index < snapshot.length; index++) {
      if (jsonEncode(current[index]) != jsonEncode(snapshot[index])) {
        return current;
      }
    }
    return current.skip(snapshot.length).toList(growable: false);
  }

  Future<void> synchronize() async {
    if (_isSynchronizing) return;
    _isSynchronizing = true;
    notifyListeners();
    try {
      await flushPending();
      await pullRemoteState();
    } finally {
      _isSynchronizing = false;
      notifyListeners();
    }
  }

  void _synchronizeBestEffort() {
    unawaited(
      synchronize().catchError((Object error, StackTrace stackTrace) {
        _handleAutomaticFailure('synchronize', error);
      }),
    );
  }

  void _handleAutomaticFailure(String operation, Object error) {
    debugPrint(
      '[UserSync] Automatic $operation failed (${error.runtimeType}).',
    );
    if (!_enabled) return;
    _lastError = error.toString();
    _setState(UserSyncConnectionState.failed);
  }

  Future<void> syncAfterAppResumed() async {
    if (!_enabled || _session == null) return;
    if (AppWorkCoordinator.instance.isAppInBackground) return;
    await synchronize();
  }

  Future<void> pullRemoteState({bool retryOnAuthError = true}) async {
    if (!_enabled || _session == null || !_firebaseClient.isConfigured) return;

    try {
      await _ensureFreshSession();
      final remoteStates = await _firebaseClient.fetchAnimeStates(
        session: _session!,
      );
      final localStates = await _loadLocalAnimeStates();
      final remoteIds = <String>{};
      for (final state in remoteStates) {
        remoteIds.add(state.animeId);
        final local = localStates[state.animeId];
        final merged = local == null
            ? state
            : UserAnimeState.merge(local, state);
        await _applySyncedAnimeState(merged);
        if (local != null && !UserAnimeState.syncContentEquals(merged, state)) {
          await _firebaseClient.saveAnimeState(
            session: _session!,
            state: merged,
          );
        }
      }

      for (final state in localStates.values) {
        if (!remoteIds.contains(state.animeId)) {
          await _firebaseClient.saveAnimeState(
            session: _session!,
            state: state,
          );
        }
      }

      final remoteSettings = await _firebaseClient.fetchSettings(
        session: _session!,
      );
      await _applySyncedSettings(remoteSettings);

      final remoteSearches = await _firebaseClient.fetchSearches(
        session: _session!,
      );
      await SearchHistoryService.applySyncedSearches(remoteSearches);

      _lastError = null;
      _lastSyncedAt = DateTime.now();
      if (_state == UserSyncConnectionState.failed) {
        _setState(UserSyncConnectionState.synced);
      } else {
        notifyListeners();
      }
    } on FirebaseSyncException catch (e) {
      if (retryOnAuthError && e.authExpired && await _refreshSession()) {
        await pullRemoteState(retryOnAuthError: false);
        return;
      }
      _lastError = e.toString();
      _setState(UserSyncConnectionState.failed);
    } catch (e) {
      _lastError = e.toString();
      _setState(UserSyncConnectionState.failed);
    }
  }

  Future<void> _ensureFreshSession() async {
    final session = _session;
    if (session == null || !session.shouldRefresh) return;
    await _refreshSession();
  }

  Future<void> _registerRemotePushToken() async {
    final session = _session;
    if (!_enabled ||
        session == null ||
        !_firebaseClient.isConfigured ||
        session.idToken.isEmpty) {
      return;
    }

    final token = await _remotePushTokenService.getAndroidFcmToken();
    if (token == null) return;

    try {
      await _firebaseClient.saveFcmToken(session: session, token: token);
    } on FirebaseSyncException catch (e) {
      if (e.authExpired && await _refreshSession()) {
        final freshSession = _session;
        if (freshSession != null) {
          await _firebaseClient.saveFcmToken(
            session: freshSession,
            token: token,
          );
        }
      }
    } catch (_) {
      // Push token registration must not block account sync or app startup.
    }
  }

  Future<bool> _refreshSession() async {
    final session = _session;
    if (session == null || !session.canRefresh) return false;

    try {
      final nextSession = await _firebaseClient.refreshSession(session);
      await _credentialStore.writeFirebaseSessionJson(
        jsonEncode(nextSession.toJson()),
      );
      _session = nextSession;
      _lastError = null;
      return true;
    } catch (e) {
      _session = session;
      _lastError = e.toString();
      return false;
    }
  }

  Future<void> _syncQueueItem(Map<String, dynamic> item) async {
    final type = item['type']?.toString();
    final payload = item['payload'];
    if (payload is! Map<String, dynamic>) return;

    if (type == 'anime') {
      final state = UserAnimeState.fromJson(payload);
      final malToken =
          (await _credentialStore.readMyAnimeListAccessToken()) ?? '';
      if (_session == null && malToken.isEmpty) {
        throw const FirebaseSyncException('No sync session available.');
      }
      if (_session != null) {
        await _firebaseClient.saveAnimeState(session: _session!, state: state);
      }
      if (malToken.isNotEmpty) {
        await _malService.syncAnimeState(accessToken: malToken, state: state);
      }
      return;
    }

    if (_session == null) {
      throw const FirebaseSyncException('No sync session available.');
    }

    if (type == 'search' && _session != null) {
      await _firebaseClient.saveSearch(
        session: _session!,
        query: payload['query']?.toString() ?? '',
        updatedAt:
            DateTime.tryParse(payload['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
      );
      return;
    }

    if (type == 'search_delete' && _session != null) {
      await _firebaseClient.deleteSearch(
        session: _session!,
        query: payload['query']?.toString() ?? '',
      );
      return;
    }

    if (type == 'search_clear' && _session != null) {
      await _firebaseClient.deleteAllSearches(session: _session!);
      return;
    }

    if (type == 'settings' && _session != null) {
      await _firebaseClient.saveSettings(session: _session!, settings: payload);
    }
  }

  Future<void> _enqueue(Map<String, dynamic> item) {
    return _serializeQueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      final current = _readQueue(prefs)..add(item);
      final queue = _flushFuture == null
          ? _compactAnimeQueue(current)
          : current;
      final persisted = await _writeQueue(prefs, jsonEncode(queue));
      if (!persisted) {
        throw StateError('Pending sync item was not persisted.');
      }
      _pendingCount = queue.length;
      notifyListeners();
    });
  }

  Future<void> _compactPendingAnimeQueue() {
    return _serializeQueueMutation(() async {
      final prefs = await SharedPreferences.getInstance();
      final current = _readQueue(prefs);
      final compacted = _compactAnimeQueue(current);
      _pendingCount = compacted.length;
      if (jsonEncode(current) == jsonEncode(compacted)) return;

      final persisted = await _writeQueue(prefs, jsonEncode(compacted));
      if (!persisted) {
        throw StateError('Compacted sync queue was not persisted.');
      }
      notifyListeners();
    });
  }

  List<Map<String, dynamic>> _compactAnimeQueue(
    List<Map<String, dynamic>> queue,
  ) {
    final compacted = <Map<String, dynamic>>[];
    for (final item in queue) {
      final incoming = _queuedAnimeState(item);
      if (incoming == null) {
        compacted.add(item);
        continue;
      }

      var merged = incoming;
      for (var index = compacted.length - 1; index >= 0; index--) {
        final existing = _queuedAnimeState(compacted[index]);
        if (existing == null || existing.animeId != incoming.animeId) {
          continue;
        }
        merged = UserAnimeState.merge(existing, merged);
        compacted.removeAt(index);
      }
      compacted.add({'type': 'anime', 'payload': merged.toJson()});
    }
    return compacted;
  }

  UserAnimeState? _queuedAnimeState(Map<String, dynamic> item) {
    if (item['type']?.toString() != 'anime') return null;
    final payload = item['payload'];
    if (payload is! Map) return null;
    try {
      final state = UserAnimeState.fromJson(Map<String, dynamic>.from(payload));
      return state.animeId.isEmpty ? null : state;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _writeQueue(SharedPreferences prefs, String value) {
    final writer = _queueWriter;
    if (writer != null) return writer(_queueKey, value);
    return prefs.setString(_queueKey, value);
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

  Future<Map<String, UserAnimeState>> _loadLocalAnimeStates() async {
    final states = <String, UserAnimeState>{};

    final historyService = WatchHistoryService();
    for (final anime in await historyService.getHistory()) {
      final watchedEpisodes = await historyService.getWatchedEpisodeNumbers(
        anime.animeId,
      );
      final state = UserAnimeState.fromHistory(
        anime,
        watchedEpisodes: watchedEpisodes,
      );
      states[state.animeId] = state;
    }

    for (final anime in await WatchlistService().getWatchlist()) {
      final watchlistState = UserAnimeState.watchlistUpdate(
        anime,
        updatedAt: anime.addedAt,
      );
      final existing = states[watchlistState.animeId];
      if (existing == null) {
        states[watchlistState.animeId] = watchlistState;
      } else {
        states[watchlistState.animeId] = UserAnimeState.merge(
          existing,
          watchlistState,
        );
      }
    }

    return states;
  }

  Future<void> _applySyncedAnimeState(UserAnimeState state) async {
    if (state.isDeleted) {
      await WatchHistoryService().applySyncedDelete(state.animeId);
      await WatchlistService().applySyncedState(state);
      return;
    }
    await WatchHistoryService().applySyncedState(state);
    await WatchlistService().applySyncedState(state);
  }

  Future<void> _applySyncedSettings(Map<String, dynamic> settings) async {
    if (settings.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final languageCode = settings['languageCode']?.toString();
    if (languageCode == 'pt' || languageCode == 'en') {
      await prefs.setString('language_code', languageCode!);
    }

    final themeStyle = settings['themeStyle']?.toString();
    if (themeStyle == 'modern' || themeStyle == 'classic') {
      await prefs.setString('theme_style', themeStyle!);
    }

    final videoEnhancementLevel = settings['videoEnhancementLevel']?.toString();
    if (videoEnhancementLevel == 'none' ||
        videoEnhancementLevel == 'normal' ||
        videoEnhancementLevel == 'heavy') {
      await prefs.setString('video_enhancement_level', videoEnhancementLevel!);
      await prefs.setBool(
        'enable_video_enhancement',
        videoEnhancementLevel != 'none',
      );
    }

    await SearchHistoryService.applySyncedSearchSettings(settings);
  }

  List<Map<String, dynamic>> _readQueue(SharedPreferences prefs) {
    final raw = prefs.getString(_queueKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _setState(UserSyncConnectionState state) {
    _state = state;
    notifyListeners();
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_session != null && !AppWorkCoordinator.instance.isAppInBackground) {
        _synchronizeBestEffort();
      }
    });
  }

  void _stopAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _postWriteSyncDebounce?.cancel();
    _postWriteSyncDebounce = null;
  }

  void _schedulePostWritePull() {
    if (_session == null) return;
    _postWriteSyncDebounce?.cancel();
    _postWriteSyncDebounce = Timer(const Duration(seconds: 8), () {
      unawaited(pullRemoteState());
    });
  }
}
