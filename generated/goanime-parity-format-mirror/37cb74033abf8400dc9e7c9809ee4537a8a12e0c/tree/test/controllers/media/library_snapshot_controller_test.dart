import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/controllers/media/library_snapshot_controller.dart';
import 'package:goanime_core/goanime_core.dart';

void main() {
  test('loads initial library snapshot and exposes success state', () async {
    final source = _QueuedLibraryDataSource(<Future<List<String>>>[
      Future<List<String>>.value(<String>['one', 'two']),
    ]);
    final controller = LibrarySnapshotController<String>(dataSource: source);

    await controller.loadInitial();

    expect(controller.state.isSuccess, isTrue);
    expect(controller.state.data, <String>['one', 'two']);
    expect(controller.lastError, isNull);
    expect(source.refreshIntents, <bool>[false]);
  });

  test('empty library publishes an empty state', () async {
    final source = _QueuedLibraryDataSource(<Future<List<String>>>[
      Future<List<String>>.value(<String>[]),
    ]);
    final controller = LibrarySnapshotController<String>(dataSource: source);

    await controller.loadInitial();

    expect(controller.state.isEmpty, isTrue);
    expect(controller.state.data, isNull);
  });

  test(
    'refresh preserves snapshot through failure and retries refresh',
    () async {
      final refresh = Completer<List<String>>();
      final retry = Completer<List<String>>();
      final source = _QueuedLibraryDataSource(<Future<List<String>>>[
        Future<List<String>>.value(<String>['stable']),
        refresh.future,
        retry.future,
      ]);
      final controller = LibrarySnapshotController<String>(dataSource: source);

      await controller.loadInitial();
      final refreshFuture = controller.refresh();

      expect(controller.state.isRefreshing, isTrue);
      expect(controller.state.data, <String>['stable']);

      final error = StateError('refresh failed');
      refresh.completeError(error);
      await refreshFuture;

      expect(controller.state.isError, isTrue);
      expect(controller.state.data, <String>['stable']);
      expect(controller.lastError, same(error));
      expect(
        controller.lastFailedOperation,
        LibrarySnapshotFailureOperation.refresh,
      );

      final retryFuture = controller.retry();
      expect(source.refreshIntents, <bool>[false, true, true]);
      retry.complete(<String>['updated']);
      await retryFuture;

      expect(controller.state.isSuccess, isTrue);
      expect(controller.state.data, <String>['updated']);
      expect(controller.lastError, isNull);
    },
  );

  test(
    'initial failure records exact error and retry repeats initial load',
    () async {
      final retry = Completer<List<String>>();
      final error = StateError('initial failed');
      final source = _QueuedLibraryDataSource(<Future<List<String>>>[
        Future<List<String>>.error(error),
        retry.future,
      ]);
      final controller = LibrarySnapshotController<String>(dataSource: source);

      await controller.loadInitial();

      expect(controller.state.isError, isTrue);
      expect(controller.state.data, isNull);
      expect(controller.lastError, same(error));
      expect(
        controller.lastFailedOperation,
        LibrarySnapshotFailureOperation.initial,
      );

      final retryFuture = controller.retry();
      expect(source.refreshIntents, <bool>[false, false]);
      retry.complete(<String>['recovered']);
      await retryFuture;

      expect(controller.state.isSuccess, isTrue);
      expect(controller.state.data, <String>['recovered']);
    },
  );

  test('older refresh completion cannot replace a newer refresh', () async {
    final older = Completer<List<String>>();
    final newer = Completer<List<String>>();
    final source = _QueuedLibraryDataSource(<Future<List<String>>>[
      Future<List<String>>.value(<String>['initial']),
      older.future,
      newer.future,
    ]);
    final controller = LibrarySnapshotController<String>(dataSource: source);

    await controller.loadInitial();
    final olderFuture = controller.refresh();
    final newerFuture = controller.refresh();

    newer.complete(<String>['newer']);
    await newerFuture;
    expect(controller.state.data, <String>['newer']);

    older.complete(<String>['older']);
    await olderFuture;
    expect(controller.state.data, <String>['newer']);
  });
}

final class _QueuedLibraryDataSource implements MediaLibraryDataSource<String> {
  _QueuedLibraryDataSource(this.responses);

  final List<Future<List<String>>> responses;
  final List<bool> refreshIntents = <bool>[];
  int _index = 0;

  @override
  Future<List<String>> load({required bool forceRefresh}) {
    refreshIntents.add(forceRefresh);
    return responses[_index++];
  }
}
