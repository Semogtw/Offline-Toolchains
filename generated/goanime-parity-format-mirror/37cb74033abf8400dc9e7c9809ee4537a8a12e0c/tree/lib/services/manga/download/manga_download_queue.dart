import '../../media/download_queue_coordinator.dart';

final class MangaDownloadQueueCancelledException implements Exception {
  const MangaDownloadQueueCancelledException();

  @override
  String toString() => 'Manga download queue job was cancelled before start.';
}

typedef MangaDownloadChapterJobKey = ({
  String downloadId,
  String canonicalChapterId,
});

final class MangaDownloadQueue {
  MangaDownloadQueue({this.maxConcurrentChapters = 2})
    : _coordinator = DownloadQueueCoordinator<MangaDownloadChapterJobKey>(
        policy: DownloadConcurrencyPolicy(maxConcurrent: maxConcurrentChapters),
      );

  final int maxConcurrentChapters;
  final DownloadQueueCoordinator<MangaDownloadChapterJobKey> _coordinator;
  final Set<MangaDownloadChapterJobKey> _trackedKeys =
      <MangaDownloadChapterJobKey>{};
  bool _disposed = false;

  int get pendingCount => _coordinator.pendingCount;
  int get activeCount => _coordinator.activeCount;

  Future<T> enqueue<T>({
    required String downloadId,
    required String canonicalChapterId,
    required Future<T> Function() operation,
  }) {
    if (_disposed) throw StateError('MangaDownloadQueue is disposed.');
    final key = (
      downloadId: downloadId.trim(),
      canonicalChapterId: canonicalChapterId.trim(),
    );
    if (key.downloadId.isEmpty || key.canonicalChapterId.isEmpty) {
      throw ArgumentError(
        'Download and canonical chapter ids must not be empty.',
      );
    }
    if (_coordinator.isKnown(key)) {
      throw StateError(
        'A manga chapter transfer is already queued or active for '
        '${key.downloadId}/${key.canonicalChapterId}.',
      );
    }

    _trackedKeys.add(key);
    late final Future<T> future;
    try {
      future = _coordinator.enqueue<T>(key: key, operation: (_) => operation());
    } catch (_) {
      _trackedKeys.remove(key);
      rethrow;
    }

    return future
        .catchError((Object error, StackTrace stackTrace) {
          if (error is MediaDownloadQueueCancelledException) {
            throw const MangaDownloadQueueCancelledException();
          }
          Error.throwWithStackTrace(error, stackTrace);
        })
        .whenComplete(() => _trackedKeys.remove(key));
  }

  bool cancelPending({
    required String downloadId,
    required String canonicalChapterId,
  }) {
    if (_disposed) return false;
    final key = (
      downloadId: downloadId.trim(),
      canonicalChapterId: canonicalChapterId.trim(),
    );
    if (!_coordinator.isKnown(key) || _coordinator.isActive(key)) {
      return false;
    }
    return _coordinator.cancel(key);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;

    // Preserve the pre-migration contract: disposal prevents new work and
    // cancels jobs that have not started, but an active chapter transfer is
    // allowed to finish at its existing domain cancellation boundaries.
    for (final key in List<MangaDownloadChapterJobKey>.of(_trackedKeys)) {
      if (!_coordinator.isActive(key)) {
        _coordinator.cancel(key);
      }
    }
  }
}
