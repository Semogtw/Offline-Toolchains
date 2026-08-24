import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/history_anime.dart';
import 'package:goanime/models/user_anime_state.dart';
import 'package:goanime/models/watchlist_anime.dart';
import 'package:goanime/services/media/anime_user_state_event_adapter.dart';
import 'package:goanime_core/goanime_core.dart';

void main() {
  const adapter = AnimeUserStateEventAdapter();

  test('full anime state emits all three independent domain events', () {
    final state = UserAnimeState(
      animeId: '42',
      title: 'Anime',
      coverImage: 'cover.jpg',
      saved: true,
      status: UserAnimeStatus.watching,
      score: 8,
      episodeNumber: 3,
      progress: 0.5,
      updatedAt: DateTime.utc(2026, 8, 24, 12),
      playbackUpdatedAt: DateTime.utc(2026, 8, 24, 10),
      watchlistUpdatedAt: DateTime.utc(2026, 8, 24, 11),
      ratingUpdatedAt: DateTime.utc(2026, 8, 24, 12),
    );

    final events = adapter.fromState(state);

    expect(events.map((event) => event.category), <UserMediaStateCategory>[
      UserMediaStateCategory.rating,
      UserMediaStateCategory.library,
      UserMediaStateCategory.progress,
    ]);
    expect(events.every((event) => event.mediaKind == MediaKind.anime), isTrue);
    expect(events.every((event) => !event.partial), isTrue);
    expect(events.every((event) => !event.tombstone), isTrue);
    expect(events.every((event) => identical(event.payload, state)), isTrue);
  });

  test(
    'playback tombstone maps only to progress with its domain timestamp',
    () {
      final deletedAt = DateTime.utc(2026, 8, 24, 10);
      final state = UserAnimeState.playbackTombstone(
        '42',
        deletedAt: deletedAt,
      );

      final events = adapter.fromState(state);

      expect(events, hasLength(1));
      expect(events.single.category, UserMediaStateCategory.progress);
      expect(events.single.updatedAt, deletedAt);
      expect(events.single.tombstone, isTrue);
      expect(events.single.partial, isTrue);
    },
  );

  test('watchlist removal maps to a library tombstone', () {
    final removedAt = DateTime.utc(2026, 8, 24, 11);
    final state = UserAnimeState.watchlistRemoval('42', removedAt: removedAt);

    final events = adapter.fromState(state);

    expect(events, hasLength(1));
    expect(events.single.category, UserMediaStateCategory.library);
    expect(events.single.updatedAt, removedAt);
    expect(events.single.tombstone, isTrue);
    expect(events.single.partial, isTrue);
  });

  test('composite sparse state emits each partial domain independently', () {
    final state = UserAnimeState.fromJson(<String, dynamic>{
      'animeId': '42',
      'title': 'Anime',
      'coverImage': 'cover.jpg',
      'saved': true,
      'score': 9,
      'updatedAt': '2026-08-24T12:00:00.000Z',
      'watchlistUpdatedAt': '2026-08-24T11:00:00.000Z',
      'ratingUpdatedAt': '2026-08-24T12:00:00.000Z',
    });

    final events = adapter.fromState(state);

    expect(events.map((event) => event.category), <UserMediaStateCategory>[
      UserMediaStateCategory.rating,
      UserMediaStateCategory.library,
    ]);
    expect(events.every((event) => event.partial), isTrue);
    expect(events.every((event) => !event.tombstone), isTrue);
  });

  test('global anime tombstone fans out to every shared state category', () {
    final state = UserAnimeState.tombstone('42');

    final events = adapter.fromState(state);

    expect(events, hasLength(3));
    expect(
      events.map((event) => event.category).toSet(),
      UserMediaStateCategory.values.toSet(),
    );
    expect(events.every((event) => event.tombstone), isTrue);
    expect(events.every((event) => !event.partial), isTrue);
  });

  test('normal partial updates are not misclassified as tombstones', () {
    final playback = UserAnimeState.playbackUpdate(
      HistoryAnime(
        animeId: '42',
        title: 'Anime',
        coverImage: 'cover.jpg',
        watchedAt: '2026-08-24T10:00:00.000Z',
        lastEpisode: 'Episódio 3',
        episodeNumber: 3,
        progress: 0.5,
      ),
    );
    final watchlist = UserAnimeState.watchlistUpdate(
      WatchlistAnime(
        animeId: '42',
        title: 'Anime',
        coverImage: 'cover.jpg',
        myAnimeListUrl: 'https://myanimelist.net/anime/42',
        addedAt: DateTime.utc(2026, 8, 24, 11),
      ),
    );
    final rating = UserAnimeState.ratingUpdate(
      animeId: '42',
      score: 9,
      updatedAt: DateTime.utc(2026, 8, 24, 12),
    );

    expect(adapter.fromState(playback).single.tombstone, isFalse);
    expect(adapter.fromState(watchlist).single.tombstone, isFalse);
    expect(adapter.fromState(rating).single.tombstone, isFalse);
  });
}
