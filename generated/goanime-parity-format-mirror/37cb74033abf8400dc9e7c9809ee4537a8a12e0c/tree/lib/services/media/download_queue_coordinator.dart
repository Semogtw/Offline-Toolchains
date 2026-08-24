import 'dart:async';

final class DownloadConcurrencyPolicy {
  DownloadConcurrencyPolicy({required this.maxConcurrent}) {
    if (maxConcurrent <= 0) {
      throw ArgumentError.value(
        maxConcurrent,
        'maxConcurrent',
        'Must be positive.',
      );
    }
  }

  final int maxConcurrent;
}

final class MediaDownloadQueueCancelledException implements Exception {
  const MediaDownloadQueueCancelledException([
    this.message = 'Download queue job was cancelled.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Cooperative control shared by queued download executors.
///
/// Executors decide where a pause/cancellation checkpoint is safe. The queue
/// never closes sockets, writes persistence or knows content formats.
final class DownloadControl {
  bool _cancelled = false;
  bool _paused = false;
  Completer<void>? _resumeCompleter;
  final Completer<void> _cancelledCompleter = Completer<void>();

  bool get isCancelled => _cancelled;
  bool get isPaused => _paused;
  Future<void> get whenCancelled => _cancelledCompleter.future;

  void throwIfCancelled() {
    if (_cancelled) {
      throw const MediaDownloadQueueCancelledException();
    }
  }

  /// Waits while paused and then checks cancellation.
  ///
  /// Long-running executors should call this at safe transfer boundaries.
  Future<void> checkpoint() async {
    throwIfCancelled();
    while (_paused && !_cancelled) {
      final resume = _resumeCompleter ??= Completer<void>();
      await resume.future;
    }
    throwIfCancelled();
  }

  void _pause() {
    if (_cancelled || _paused) return;
    _paused = true;
    _resumeCompleter = Completer<void>();
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    final resume = _resumeCompleter;
    _resumeCompleter = null;
    if (resume != null && !resume.isCompleted) resume.complete();
  }

  void _cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _paused = false;
    final resume = _resumeCompleter;
    _resumeCompleter = null;
    if (resume != null && !resume.isCompleted) resume.complete();
    if (!_cancelledCompleter.isCompleted) _cancelledCompleter.complete();
  }
}

/// Media-neutral FIFO download queue.
///
/// [K] is intentionally generic: Anime can key by download id while Manga can
/// key chapter transfers by `(downloadId, canonicalChapterId)`. Payload,
/// persistence, transport and verification remain executor responsibilities.
final class DownloadQueueCoordinator<K> {
  DownloadQueueCoordinator({required DownloadConcurrencyPolicy policy})
    : _policy = policy;

  DownloadConcurrencyPolicy _policy;
  final List<_QueuedDownloadJob<K>> _pending = <_QueuedDownloadJob<K>>[];
  final Map<K, _QueuedDownloadJob<K>> _known = <K, _QueuedDownloadJob<K>>{};
  final Map<K, _QueuedDownloadJob<K>> _active = <K, _QueuedDownloadJob<K>>{};
  bool _disposed = false;
  bool _drainScheduled = false;

  DownloadConcurrencyPolicy get policy => _policy;
  int get pendingCount => _pending.length;
  int get activeCount => _active.length;
  bool get isDisposed => _disposed;

  bool isKnown(K key) => _known.containsKey(key);
  bool isActive(K key) => _active.containsKey(key);

  Future<T> enqueue<T>({
    required K key,
    required FutureOr<T> Function(DownloadControl control) operation,
  }) {
    if (_disposed) {
      throw StateError('DownloadQueueCoordinator is disposed.');
    }
    if (_known.containsKey(key)) {
      throw StateError(
        'A download queue job is already pending or active for $key.',
      );
    }

    final completer = Completer<Object?>();
    final job = _QueuedDownloadJob<K>(
      key: key,
      control: DownloadControl(),
      operation: (control) async => operation(control),
      completer: completer,
    );
    _known[key] = job;
    _pending.add(job);
    _drain();
    return completer.future.then((value) => value as T);
  }

  /// Retry is a semantic alias for enqueue after a previous terminal result.
  Future<T> retry<T>({
    required K key,
    required FutureOr<T> Function(DownloadControl control) operation,
  }) {
    return enqueue<T>(key: key, operation: operation);
  }

  bool pause(K key) {
    if (_disposed) return false;
    final job = _known[key];
    if (job == null) return false;
    job.paused = true;
    job.control._pause();
    return true;
  }

  bool resume(K key) {
    if (_disposed) return false;
    final job = _known[key];
    if (job == null || (!job.paused && !job.control.isPaused)) return false;
    job.paused = false;
    job.control._resume();
    _drain();
    return true;
  }

  bool cancel(K key) {
    if (_disposed) return false;
    final job = _known[key];
    if (job == null) return false;

    job.control._cancel();
    if (_active.containsKey(key)) {
      return true;
    }

    _pending.remove(job);
    _known.remove(key);
    job.cancel();
    _drain();
    return true;
  }

  void updatePolicy(DownloadConcurrencyPolicy policy) {
    if (_disposed) {
      throw StateError('DownloadQueueCoordinator is disposed.');
    }
    _policy = policy;
    _drain();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;

    final pending = List<_QueuedDownloadJob<K>>.of(_pending);
    _pending.clear();
    for (final job in pending) {
      _known.remove(job.key);
      job.control._cancel();
      job.cancel();
    }
    for (final job in _active.values) {
      job.control._cancel();
    }
  }

  void _drain() {
    if (_disposed || _drainScheduled) return;
    _drainScheduled = true;
    scheduleMicrotask(() {
      _drainScheduled = false;
      if (_disposed) return;

      while (_active.length < _policy.maxConcurrent) {
        final index = _pending.indexWhere((job) => !job.paused);
        if (index < 0) return;
        final job = _pending.removeAt(index);
        _active[job.key] = job;
        unawaited(_run(job));
      }
    });
  }

  Future<void> _run(_QueuedDownloadJob<K> job) async {
    try {
      job.control.throwIfCancelled();
      final value = await job.operation(job.control);
      job.control.throwIfCancelled();
      job.complete(value);
    } catch (error, stackTrace) {
      if (job.control.isCancelled) {
        job.cancel();
      } else {
        job.fail(error, stackTrace);
      }
    } finally {
      _active.remove(job.key);
      _known.remove(job.key);
      _drain();
    }
  }
}

final class _QueuedDownloadJob<K> {
  _QueuedDownloadJob({
    required this.key,
    required this.control,
    required this.operation,
    required this.completer,
  });

  final K key;
  final DownloadControl control;
  final Future<Object?> Function(DownloadControl control) operation;
  final Completer<Object?> completer;
  bool paused = false;

  void complete(Object? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  void fail(Object error, StackTrace stackTrace) {
    if (!completer.isCompleted) completer.completeError(error, stackTrace);
  }

  void cancel() {
    if (!completer.isCompleted) {
      completer.completeError(const MediaDownloadQueueCancelledException());
    }
  }
}
