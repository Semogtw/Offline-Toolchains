import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:goanime_core/goanime_core.dart';

import '../../services/media/request_generation.dart';

typedef HomeFreshSnapshotLoader<TSnapshot> =
    Future<TSnapshot> Function({required bool forceRefresh});
typedef HomeCachedSnapshotLoader<TSnapshot> = Future<TSnapshot?> Function();

enum HomeSnapshotFailureOperation { initial, refresh }

final class HomeSnapshotController<TSnapshot> extends ChangeNotifier {
  HomeSnapshotController({
    required HomeFreshSnapshotLoader<TSnapshot> loadFresh,
    HomeCachedSnapshotLoader<TSnapshot>? loadCached,
    bool Function(TSnapshot snapshot)? isEmpty,
  }) : _loadFresh = loadFresh,
       _loadCached = loadCached,
       _isEmpty = isEmpty ?? ((_) => false);

  final HomeFreshSnapshotLoader<TSnapshot> _loadFresh;
  final HomeCachedSnapshotLoader<TSnapshot>? _loadCached;
  final bool Function(TSnapshot snapshot) _isEmpty;
  final RequestGeneration _generation = RequestGeneration();

  MediaLoadState<TSnapshot> _state = const MediaLoadState.idle();
  Object? _lastError;
  HomeSnapshotFailureOperation? _lastFailedOperation;
  bool _disposed = false;

  MediaLoadState<TSnapshot> get state => _state;
  Object? get lastError => _lastError;
  HomeSnapshotFailureOperation? get lastFailedOperation => _lastFailedOperation;
  bool get isDisposed => _disposed;

  Future<void> loadInitial() async {
    if (_disposed) return;

    final token = _generation.next();
    _clearFailure();
    _state = const MediaLoadState.loading();
    notifyListeners();

    if (_loadCached != null) {
      unawaited(_publishCachedSnapshot(token));
    }

    try {
      final snapshot = await _loadFresh(forceRefresh: false);
      if (!_canCommit(token)) return;

      _publishFreshSnapshot(snapshot);
    } catch (error) {
      if (!_canCommit(token)) return;

      _publishFailure(
        error,
        HomeSnapshotFailureOperation.initial,
        snapshot: _state.data,
      );
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;

    final previousSnapshot = _state.data;
    final token = _generation.next();
    _clearFailure();
    _state = MediaLoadState.refreshing(snapshot: previousSnapshot);
    notifyListeners();

    try {
      final snapshot = await _loadFresh(forceRefresh: true);
      if (!_canCommit(token)) return;

      _publishFreshSnapshot(snapshot);
    } catch (error) {
      if (!_canCommit(token)) return;

      _publishFailure(
        error,
        HomeSnapshotFailureOperation.refresh,
        snapshot: previousSnapshot,
      );
    }
  }

  Future<void> retry() {
    return switch (_lastFailedOperation) {
      HomeSnapshotFailureOperation.initial => loadInitial(),
      HomeSnapshotFailureOperation.refresh => refresh(),
      null => Future<void>.value(),
    };
  }

  Future<void> _publishCachedSnapshot(int token) async {
    try {
      final snapshot = await _loadCached!();
      if (!_canCommit(token) || !_state.isLoading || snapshot == null) {
        return;
      }

      _state = MediaLoadState.loading(snapshot: snapshot);
      notifyListeners();
    } catch (_) {
      // Cache is opportunistic. Fresh loading remains authoritative.
    }
  }

  bool _canCommit(int token) => !_disposed && _generation.isCurrent(token);

  void _clearFailure() {
    _lastError = null;
    _lastFailedOperation = null;
  }

  void _publishFreshSnapshot(TSnapshot snapshot) {
    _clearFailure();
    _state = _isEmpty(snapshot)
        ? const MediaLoadState.empty()
        : MediaLoadState.success(snapshot);
    notifyListeners();
  }

  void _publishFailure(
    Object error,
    HomeSnapshotFailureOperation operation, {
    TSnapshot? snapshot,
  }) {
    _lastError = error;
    _lastFailedOperation = operation;
    _state = MediaLoadState.error(error.toString(), snapshot: snapshot);
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation.invalidate();
    super.dispose();
  }
}
