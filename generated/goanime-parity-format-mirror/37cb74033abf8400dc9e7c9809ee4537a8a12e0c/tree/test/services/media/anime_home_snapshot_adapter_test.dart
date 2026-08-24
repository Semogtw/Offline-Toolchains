import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/jikan_models.dart';
import 'package:goanime/services/jikan_service.dart';
import 'package:goanime/services/media/anime_home_snapshot_adapter.dart';

void main() {
  test('AnimeHomeSnapshotAdapter reads expired persisted snapshots', () async {
    final cached = _homeData(1, 'Cached');
    final service = _FakeHomeJikanService(cached: cached);
    final adapter = AnimeHomeSnapshotAdapter(jikanService: service);

    expect(await adapter.loadCached(), same(cached));
    expect(service.allowExpiredValues, [true]);
  });

  test('AnimeHomeSnapshotAdapter forwards fresh refresh intent', () async {
    final fresh = _homeData(2, 'Fresh');
    final service = _FakeHomeJikanService(fresh: fresh);
    final adapter = AnimeHomeSnapshotAdapter(jikanService: service);

    expect(await adapter.loadFresh(forceRefresh: false), same(fresh));
    expect(await adapter.loadFresh(forceRefresh: true), same(fresh));
    expect(service.forceRefreshValues, [false, true]);
  });

  test('AnimeHomeSnapshotAdapter bounds a stalled fresh load', () async {
    final service = _FakeHomeJikanService(
      freshFuture: Completer<HomeData>().future,
    );
    final adapter = AnimeHomeSnapshotAdapter(
      jikanService: service,
      freshTimeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      adapter.loadFresh(forceRefresh: false),
      throwsA(isA<TimeoutException>()),
    );
  });
}

final class _FakeHomeJikanService extends JikanService {
  _FakeHomeJikanService({this.cached, this.fresh, this.freshFuture})
    : super(propagateErrors: true);

  final HomeData? cached;
  final HomeData? fresh;
  final Future<HomeData>? freshFuture;
  final List<bool> allowExpiredValues = [];
  final List<bool> forceRefreshValues = [];

  @override
  Future<HomeData?> loadCachedHomeDataSnapshot({bool allowExpired = false}) {
    allowExpiredValues.add(allowExpired);
    return Future.value(cached);
  }

  @override
  Future<HomeData> loadHomeData({bool forceRefresh = false}) {
    forceRefreshValues.add(forceRefresh);
    final pending = freshFuture;
    if (pending != null) return pending;
    return Future.value(fresh ?? _homeData(3, 'Default'));
  }
}

HomeData _homeData(int id, String title) {
  final anime = JikanAnime(malId: id, title: title, imageUrl: '');
  return HomeData(
    seasonAnimes: [anime],
    todaysReleases: const [],
    topAnimes: const [],
    actionAnimes: const [],
    romanceAnimes: const [],
    comedyAnimes: const [],
    fantasyAnimes: const [],
  );
}
