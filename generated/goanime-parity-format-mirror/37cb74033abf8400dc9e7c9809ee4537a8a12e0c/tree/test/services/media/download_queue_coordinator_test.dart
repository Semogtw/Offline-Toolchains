import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/media/download_queue_coordinator.dart';

void main() {
  test('DownloadConcurrencyPolicy validates runtime concurrency', () {
    expect(
      () => DownloadConcurrencyPolicy(maxConcurrent: 0),
      throwsArgumentError,
    );
    expect(DownloadConcurrencyPolicy(maxConcurrent: 2).maxConcurrent, 2);
  });

  test('bounds concurrency and preserves FIFO order', () async {
    final coordinator = DownloadQueueCoordinator<String>(
      policy: DownloadConcurrencyPolicy(maxConcurrent: 2),
    );
    final started = <String>[];
    final first = Completer<void>();
    final second = Completer<void>();
    final third = Completer<void>();

    final f1 = coordinator.enqueue<void>(
      key: '1',
      operation: (_) {
        started.add('1');
        return first.future;
      },
    );
    final f2 = coordinator.enqueue<void>(
      key: '2',
      operation: (_) {
        started.add('2');
        return second.future;
      },
    );
    final f3 = coordinator.enqueue<void>(
      key: '3',
      operation: (_) {
        started.add('3');
        return third.future;
      },
    );

    await _flush();
    expect(started, ['1', '2']);
    expect(coordinator.activeCount, 2);
    expect(coordinator.pendingCount, 1);

    first.complete();
    await f1;
    await _flush();
    expect(started, ['1', '2', '3']);

    second.complete();
    third.complete();
    await Future.wait([f2, f3]);
    coordinator.dispose();
  });

  test(
    'rejects duplicate queued or active keys and allows retry after terminal',
    () async {
      final coordinator = DownloadQueueCoordinator<String>(
        policy: DownloadConcurrencyPolicy(maxConcurrent: 1),
      );
      final blocker = Completer<void>();

      final first = coordinator.enqueue<void>(
        key: 'same',
        operation: (_) => blocker.future,
      );
      expect(
        () => coordinator.enqueue<void>(key: 'same', operation: (_) async {}),
        throwsStateError,
      );

      blocker.complete();
      await first;

      await coordinator.retry<void>(key: 'same', operation: (_) async {});
      coordinator.dispose();
    },
  );

  test('pauses a pending job until resume without consuming a slot', () async {
    final coordinator = DownloadQueueCoordinator<String>(
      policy: DownloadConcurrencyPolicy(maxConcurrent: 1),
    );
    final blocker = Completer<void>();
    var pausedStarted = false;

    final running = coordinator.enqueue<void>(
      key: 'running',
      operation: (_) => blocker.future,
    );
    final paused = coordinator.enqueue<void>(
      key: 'paused',
      operation: (_) async {
        pausedStarted = true;
      },
    );

    expect(coordinator.pause('paused'), isTrue);
    blocker.complete();
    await running;
    await _flush();
    expect(pausedStarted, isFalse);
    expect(coordinator.activeCount, 0);
    expect(coordinator.pendingCount, 1);

    expect(coordinator.resume('paused'), isTrue);
    await paused;
    expect(pausedStarted, isTrue);
    coordinator.dispose();
  });

  test(
    'active pause and resume are honored at cooperative checkpoint',
    () async {
      final coordinator = DownloadQueueCoordinator<String>(
        policy: DownloadConcurrencyPolicy(maxConcurrent: 1),
      );
      final reachedCheckpoint = Completer<void>();
      final releaseBeforeCheckpoint = Completer<void>();
      var passedCheckpoint = false;

      final future = coordinator.enqueue<void>(
        key: 'active',
        operation: (control) async {
          reachedCheckpoint.complete();
          await releaseBeforeCheckpoint.future;
          await control.checkpoint();
          passedCheckpoint = true;
        },
      );

      await reachedCheckpoint.future;
      expect(coordinator.pause('active'), isTrue);
      releaseBeforeCheckpoint.complete();
      await _flush();
      expect(passedCheckpoint, isFalse);

      expect(coordinator.resume('active'), isTrue);
      await future;
      expect(passedCheckpoint, isTrue);
      coordinator.dispose();
    },
  );

  test('cancels pending and active jobs with typed cancellation', () async {
    final coordinator = DownloadQueueCoordinator<String>(
      policy: DownloadConcurrencyPolicy(maxConcurrent: 1),
    );
    final activeCheckpoint = Completer<void>();
    final release = Completer<void>();

    final active = coordinator.enqueue<void>(
      key: 'active',
      operation: (control) async {
        activeCheckpoint.complete();
        await release.future;
        await control.checkpoint();
      },
    );
    final pending = coordinator.enqueue<void>(
      key: 'pending',
      operation: (_) async {},
    );

    await activeCheckpoint.future;
    expect(coordinator.cancel('pending'), isTrue);
    await expectLater(
      pending,
      throwsA(isA<MediaDownloadQueueCancelledException>()),
    );

    expect(coordinator.cancel('active'), isTrue);
    release.complete();
    await expectLater(
      active,
      throwsA(isA<MediaDownloadQueueCancelledException>()),
    );
    coordinator.dispose();
  });

  test(
    'updated concurrency policy immediately drains newly available slots',
    () async {
      final coordinator = DownloadQueueCoordinator<String>(
        policy: DownloadConcurrencyPolicy(maxConcurrent: 1),
      );
      final first = Completer<void>();
      final second = Completer<void>();
      final started = <String>[];

      final f1 = coordinator.enqueue<void>(
        key: '1',
        operation: (_) {
          started.add('1');
          return first.future;
        },
      );
      final f2 = coordinator.enqueue<void>(
        key: '2',
        operation: (_) {
          started.add('2');
          return second.future;
        },
      );
      await _flush();
      expect(started, ['1']);

      coordinator.updatePolicy(DownloadConcurrencyPolicy(maxConcurrent: 2));
      await _flush();
      expect(started, ['1', '2']);

      first.complete();
      second.complete();
      await Future.wait([f1, f2]);
      coordinator.dispose();
    },
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
