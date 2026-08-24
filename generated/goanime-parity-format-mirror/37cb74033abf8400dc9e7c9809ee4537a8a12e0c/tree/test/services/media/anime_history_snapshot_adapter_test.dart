import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/history_anime.dart';
import 'package:goanime/services/media/anime_history_snapshot_adapter.dart';
import 'package:goanime/services/watch_history_service.dart';

void main() {
  test(
    'AnimeHistorySnapshotAdapter delegates every load to WatchHistoryService',
    () async {
      final service = _CountingWatchHistoryService();
      final adapter = AnimeHistorySnapshotAdapter(service);

      expect(await adapter.load(forceRefresh: false), hasLength(1));
      expect(await adapter.load(forceRefresh: true), hasLength(1));
      expect(service.loadCalls, 2);
    },
  );
}

final class _CountingWatchHistoryService extends WatchHistoryService {
  int loadCalls = 0;

  @override
  Future<List<HistoryAnime>> getHistory() async {
    loadCalls += 1;
    return <HistoryAnime>[
      HistoryAnime(
        animeId: '1',
        title: 'Stable Anime',
        coverImage: '',
        watchedAt: DateTime.utc(2026, 8, 24).toIso8601String(),
        lastEpisode: 'Episódio 1',
      ),
    ];
  }
}
