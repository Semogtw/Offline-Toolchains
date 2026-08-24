import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/controllers/media/home_snapshot_controller.dart';

void main() {
  test('HomeSnapshotController loads the initial fresh snapshot', () async {
    final controller = HomeSnapshotController<String>(
      loadFresh: ({required bool forceRefresh}) async {
        expect(forceRefresh, isFalse);
        return 'fresh';
      },
    );
    addTearDown(controller.dispose);

    final load = controller.loadInitial();

    expect(controller.state.isLoading, isTrue);

    await load;

    expect(controller.state.isSuccess, isTrue);
    expect(controller.state.data, 'fresh');
    expect(controller.lastError, isNull);
    expect(controller.lastFailedOperation, isNull);
  });

  test('cached snapshot is visible while the fresh load is pending', () async {
    final cached = Completer<String?>();
    final fresh = Completer<String>();
    final controller = HomeSnapshotController<String>(
      loadCached: () => cached.future,
      loadFresh: ({required bool forceRefresh}) => fresh.future,
    );
    addTearDown(controller.dispose);

    final load = controller.loadInitial();
    cached.complete('cached');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.isLoading, isTrue);
    expect(controller.state.data, 'cached');

    fresh.complete('fresh');
    await load;

    expect(controller.state.isSuccess, isTrue);
    expect(controller.state.data, 'fresh');
  });

  test('late cached snapshot cannot replace a fresh snapshot', () async {
    final cached = Completer<String?>();
    final fresh = Completer<String>();
    final controller = HomeSnapshotController<String>(
      loadCached: () => cached.future,
      loadFresh: ({required bool forceRefresh}) => fresh.future,
    );
    addTearDown(controller.dispose);

    final load = controller.loadInitial();
    fresh.complete('fresh');
    await load;

    expect(controller.state.isSuccess, isTrue);
    expect(controller.state.data, 'fresh');

    cached.complete('stale cache');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.isSuccess, isTrue);
    expect(controller.state.data, 'fresh');
  });

  test(
    'fresh initial failure keeps an already published cached snapshot',
    () async {
      final cached = Completer<String?>();
      final fresh = Completer<String>();
      final controller = HomeSnapshotController<String>(
        loadCached: () => cached.future,
        loadFresh: ({required bool forceRefresh}) => fresh.future,
      );
      addTearDown(controller.dispose);

      final load = controller.loadInitial();
      cached.complete('cached');
      await Future<void>.delayed(Duration.zero);

      final error = StateError('fresh failed');
      fresh.completeError(error);
      await load;

      expect(controller.state.isError, isTrue);
      expect(controller.state.data, 'cached');
      expect(identical(controller.lastError, error), isTrue);
      expect(
        controller.lastFailedOperation,
        HomeSnapshotFailureOperation.initial,
      );
    },
  );

  test('refresh keeps the snapshot through failure and retry', () async {
    final firstRefresh = Completer<String>();
    final secondRefresh = Completer<String>();
    var refreshCalls = 0;
    final controller = HomeSnapshotController<String>(
      loadFresh: ({required bool forceRefresh}) {
        if (!forceRefresh) return Future.value('initial');
        refreshCalls += 1;
        return refreshCalls == 1 ? firstRefresh.future : secondRefresh.future;
      },
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();

    final refresh = controller.refresh();
    expect(controller.state.isRefreshing, isTrue);
    expect(controller.state.data, 'initial');

    final error = StateError('refresh failed');
    firstRefresh.completeError(error);
    await refresh;

    expect(controller.state.isError, isTrue);
    expect(controller.state.data, 'initial');
    expect(identical(controller.lastError, error), isTrue);
    expect(
      controller.lastFailedOperation,
      HomeSnapshotFailureOperation.refresh,
    );

    final retry = controller.retry();
    expect(controller.state.isRefreshing, isTrue);
    expect(controller.state.data, 'initial');

    secondRefresh.complete('refreshed');
    await retry;

    expect(refreshCalls, 2);
    expect(controller.state.isSuccess, isTrue);
    expect(controller.state.data, 'refreshed');
    expect(controller.lastError, isNull);
    expect(controller.lastFailedOperation, isNull);
  });

  test('older refresh completion cannot replace a newer snapshot', () async {
    final firstRefresh = Completer<String>();
    final secondRefresh = Completer<String>();
    var refreshCalls = 0;
    final controller = HomeSnapshotController<String>(
      loadFresh: ({required bool forceRefresh}) {
        if (!forceRefresh) return Future.value('initial');
        refreshCalls += 1;
        return refreshCalls == 1 ? firstRefresh.future : secondRefresh.future;
      },
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();

    final older = controller.refresh();
    final newer = controller.refresh();

    secondRefresh.complete('newer');
    await newer;
    expect(controller.state.data, 'newer');

    firstRefresh.complete('older');
    await older;

    expect(controller.state.isSuccess, isTrue);
    expect(controller.state.data, 'newer');
  });
}
