import 'package:flutter/foundation.dart';
import 'package:goanime_core/goanime_core.dart';

import '../../services/media/request_generation.dart';

enum LibrarySnapshotFailureOperation { initial, refresh }

final class LibrarySnapshotController<TItem> extends ChangeNotifier {
  LibrarySnapshotController({required MediaLibraryDataSource<TItem> dataSource})
    : _dataSource = dataSource;

  final MediaLibraryDataSource<TItem> _dataSource;
  final RequestGeneration _generation = RequestGeneration();

  MediaLoadState<List<TItem>> _state = const MediaLoadState.idle();
  Object? _lastError;
  LibrarySnapshotFailureOperation? _lastFailedOperation;
  bool _disposed = false;

  MediaLoadState<List<TItem>> get state => _state;
  Object? get lastError => _lastError;
  LibrarySnapshotFailureOperation? get lastFailedOperation =>
      _lastFailedOperation;
  bool get isDisposed => _disposed;

  Future<void> loadInitial() async {
    if (_disposed) return;

    final token = _generation.next();
    _clearFailure();
    _state = const MediaLoadState.loading();
    notifyListeners();

    try {
      final items = await _dataSource.load(forceRefresh: false);
      if (!_canCommit(token)) return;
      _publishItems(items);
    } catch (error) {
      if (!_canCommit(token)) return;
      _publishFailure(error, LibrarySnapshotFailureOperation.initial);
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
      final items = await _dataSource.load(forceRefresh: true);
      if (!_canCommit(token)) return;
      _publishItems(items);
    } catch (error) {
      if (!_canCommit(token)) return;
      _publishFailure(
        error,
        LibrarySnapshotFailureOperation.refresh,
        snapshot: previousSnapshot,
      );
    }
  }

  Future<void> retry() {
    return switch (_lastFailedOperation) {
      LibrarySnapshotFailureOperation.initial => loadInitial(),
      LibrarySnapshotFailureOperation.refresh => refresh(),
      null => Future<void>.value(),
    };
  }

  bool _canCommit(int token) => !_disposed && _generation.isCurrent(token);

  void _clearFailure() {
    _lastError = null;
    _lastFailedOperation = null;
  }

  void _publishItems(List<TItem> items) {
    _clearFailure();
    final snapshot = List<TItem>.unmodifiable(items);
    _state = snapshot.isEmpty
        ? const MediaLoadState.empty()
        : MediaLoadState.success(snapshot);
    notifyListeners();
  }

  void _publishFailure(
    Object error,
    LibrarySnapshotFailureOperation operation, {
    List<TItem>? snapshot,
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
