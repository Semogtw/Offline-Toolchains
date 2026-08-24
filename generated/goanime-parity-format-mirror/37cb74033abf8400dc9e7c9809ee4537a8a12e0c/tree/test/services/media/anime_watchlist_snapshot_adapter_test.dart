import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/watchlist_anime.dart';
import 'package:goanime/services/media/anime_watchlist_snapshot_adapter.dart';
import 'package:goanime/services/watchlist_service.dart';

void main() {
  test(
    'AnimeWatchlistSnapshotAdapter delegates every load to WatchlistService',
    () async {
      final service = _CountingWatchlistService();
      final adapter = AnimeWatchlistSnapshotAdapter(service);

      expect(await adapter.load(forceRefresh: false), hasLength(1));
      expect(await adapter.load(forceRefresh: true), hasLength(1));
      expect(service.loadCalls, 2);
    },
  );
}

final class _CountingWatchlistService extends WatchlistService {
  int loadCalls = 0;

  @override
  Future<List<WatchlistAnime>> getWatchlist() async {
    loadCalls += 1;
    return <WatchlistAnime>[
      WatchlistAnime(
        animeId: '1',
        title: 'Stable Anime',
        coverImage: '',
        myAnimeListUrl: 'https://myanimelist.net/anime/1',
        addedAt: DateTime.utc(2026, 8, 24),
      ),
    ];
  }
}
