import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/history_anime.dart';
import 'package:goanime/services/media/anime_progress_event_adapter.dart';
import 'package:goanime_core/goanime_core.dart';

void main() {
  test('maps anime playback progress without changing time units', () {
    final history = HistoryAnime(
      animeId: 'anime-1',
      title: 'Anime',
      coverImage: '',
      watchedAt: '2026-08-24T10:00:00Z',
      updatedAt: '2026-08-24T11:00:00Z',
      lastEpisode: 'Episódio 7',
      episodeNumber: 7,
      progress: 0.5,
      positionSeconds: 321,
      durationSeconds: 642,
      isDubMode: true,
    );

    final event = const AnimeProgressEventAdapter().fromHistory(history);

    expect(event, isNotNull);
    expect(event!.mediaKind, MediaKind.anime);
    expect(event.entityId, 'anime-1');
    expect(event.unitId, 'episode:7');
    expect(event.updatedAt, DateTime.utc(2026, 8, 24, 11));
    expect(event.completed, isFalse);
    expect(event.payload.episodeNumber, 7);
    expect(event.payload.positionSeconds, 321);
    expect(event.payload.durationSeconds, 642);
    expect(event.payload.progress, 0.5);
    expect(event.payload.isDubMode, isTrue);
  });

  test(
    'uses anime completion semantics and rejects legacy rows without unit identity',
    () {
      final completed = HistoryAnime(
        animeId: 'anime-1',
        title: 'Anime',
        coverImage: '',
        watchedAt: '2026-08-24T10:00:00Z',
        lastEpisode: 'Episódio 3',
        episodeNumber: 3,
        progress: 0.85,
      );
      final legacy = HistoryAnime(
        animeId: 'anime-1',
        title: 'Anime',
        coverImage: '',
        watchedAt: '2026-08-24T10:00:00Z',
        lastEpisode: 'Episódio desconhecido',
      );

      final adapter = const AnimeProgressEventAdapter();

      expect(adapter.fromHistory(completed)!.completed, isTrue);
      expect(adapter.fromHistory(legacy), isNull);
    },
  );
}
