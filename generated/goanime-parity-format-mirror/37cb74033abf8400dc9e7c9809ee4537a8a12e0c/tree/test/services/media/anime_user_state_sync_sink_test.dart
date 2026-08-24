import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/history_anime.dart';
import 'package:goanime/models/user_anime_state.dart';
import 'package:goanime/models/watchlist_anime.dart';
import 'package:goanime/services/media/anime_user_state_event_adapter.dart';
import 'package:goanime/services/media/anime_user_state_sync_sink.dart';
import 'package:goanime_core/goanime_core.dart';

void main() {
  const adapter = AnimeUserStateEventAdapter();

  test(
    'coalesces the three events of one full state into one legacy write',
    () async {
      final recorded = <UserAnimeState>[];
      final sink = AnimeUserStateSyncSink(
        recordState: (state) async => recorded.add(state),
      );
      final state = UserAnimeState(
        animeId: '42',
        title: 'Anime',
        coverImage: 'cover.jpg',
        saved: true,
        status: UserAnimeStatus.watching,
        score: 9,
        episodeNumber: 4,
        progress: 0.5,
        updatedAt: DateTime.utc(2026, 8, 24, 13),
      );

      await sink.sync(<UserMediaStateEvent<dynamic>>[
        ...adapter.fromState(state),
      ]);

      expect(recorded, <UserAnimeState>[state]);
    },
  );

  test('keeps distinct partial states as distinct legacy writes', () async {
    final recorded = <UserAnimeState>[];
    final sink = AnimeUserStateSyncSink(
      recordState: (state) async => recorded.add(state),
    );
    final playback = UserAnimeState.playbackUpdate(
      HistoryAnime(
        animeId: '42',
        title: 'Anime',
        coverImage: 'cover.jpg',
        watchedAt: '2026-08-24T12:00:00.000Z',
        lastEpisode: 'Episódio 3',
        episodeNumber: 3,
        progress: 0.4,
      ),
    );
    final library = UserAnimeState.watchlistUpdate(
      WatchlistAnime(
        animeId: '42',
        title: 'Anime',
        coverImage: 'cover.jpg',
        myAnimeListUrl: 'https://myanimelist.net/anime/42',
        addedAt: DateTime.utc(2026, 8, 24, 13),
      ),
    );

    await sink.sync(<UserMediaStateEvent<dynamic>>[
      ...adapter.fromState(playback),
      ...adapter.fromState(library),
    ]);

    expect(recorded, <UserAnimeState>[playback, library]);
  });

  test('rejects a non-Anime event instead of silently dropping it', () async {
    final state = UserAnimeState.tombstone('42');
    final sink = AnimeUserStateSyncSink(recordState: (_) async {});

    await expectLater(
      sink.sync(<UserMediaStateEvent<dynamic>>[
        UserMediaStateEvent<UserAnimeState>(
          mediaKind: MediaKind.manga,
          entityId: '42',
          category: UserMediaStateCategory.progress,
          updatedAt: DateTime.utc(2026, 8, 24, 13),
          tombstone: true,
          partial: true,
          payload: state,
        ),
      ]),
      throwsArgumentError,
    );
  });
}
