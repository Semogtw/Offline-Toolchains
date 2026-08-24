import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Home bootstrap delegates catalog snapshots and keeps history single-flight',
    () {
      final state = File('lib/screens/home_screen.dart').readAsStringSync();
      final data = File('lib/screens/home_screen_data.dart').readAsStringSync();
      final adapter = File(
        'lib/services/media/anime_home_snapshot_adapter.dart',
      ).readAsStringSync();

      // Catalog cache/fresh coordination now belongs to the shared lifecycle.
      expect(state, contains('HomeSnapshotController<HomeData>'));
      expect(state, contains('AnimeHomeSnapshotAdapter'));
      expect(state, isNot(contains('_cachedSnapshotLoadInFlight')));
      expect(data, isNot(contains('Future<void> _loadCachedHomeData()')));

      // The Anime adapter preserves the persisted-cache behavior that existed
      // before the lifecycle migration, including accepting expired snapshots
      // during bootstrap while a fresh catalog load runs.
      expect(adapter, contains('Future<HomeData?> loadCached()'));
      expect(adapter, contains('allowExpired: true'));
      expect(adapter, contains('Future<HomeData> loadFresh'));

      // Continue Watching is secondary local state and retains its dedicated
      // single-flight + trailing forced refresh semantics (PERF-N05).
      expect(state, contains('_continueWatchingLoadInFlight'));
      expect(
        data,
        contains('_loadContinueWatching({bool forceRefresh = false})'),
      );
      expect(data, contains('final future = _drainContinueWatchingLoads();'));
      expect(data, contains('while (_continueWatchingRerunRequested);'));
      expect(data, contains('_readContinueWatching()'));

      // Failure logging for the remaining secondary storage read is preserved.
      expect(data, contains('[Home] Continue watching load failed:'));
    },
  );
}
