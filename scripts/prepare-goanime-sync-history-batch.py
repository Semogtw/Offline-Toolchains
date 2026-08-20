#!/usr/bin/env python3
from pathlib import Path
import argparse


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise SystemExit(f'{path}: expected exactly one target')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root

    history = root / 'lib/services/watch_history_service.dart'
    marker = """  Future<List<HistoryAnime>> getContinueWatching({int limit = 10}) async {
"""
    method = """  Future<Map<String, Set<int>>> getWatchedEpisodeNumbersForHistory(
    Iterable<HistoryAnime> history,
  ) async {
    final historyByAnimeId = <String, HistoryAnime>{
      for (final anime in history)
        if (anime.animeId.isNotEmpty) anime.animeId: anime,
    };
    if (historyByAnimeId.isEmpty) return const <String, Set<int>>{};

    try {
      final prefs = await SharedPreferences.getInstance();
      final result = <String, Set<int>>{};
      for (final entry in historyByAnimeId.entries) {
        final animeId = entry.key;
        final anime = entry.value;
        final key = _watchedEpisodesKey(animeId);
        final values = prefs.getStringList(key) ?? const <String>[];
        final episodes = _parseWatchedEpisodeValues(values);
        var normalizedValues = _encodeWatchedEpisodeValues(episodes);

        if (episodes.isEmpty) {
          final episodeNumber = anime.episodeNumber;
          if (episodeNumber != null &&
              episodeNumber > 0 &&
              _isEpisodeWatchedProgress(anime.progress)) {
            episodes.add(episodeNumber);
            normalizedValues = _encodeWatchedEpisodeValues(episodes);
          }
        }

        if (!listEquals(values, normalizedValues)) {
          if (normalizedValues.isEmpty) {
            await prefs.remove(key);
          } else {
            await prefs.setStringList(key, normalizedValues);
          }
        }
        result[animeId] = episodes;
      }
      return result;
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to read watched episodes in batch '
        '(${error.runtimeType}).',
      );
      return {
        for (final animeId in historyByAnimeId.keys) animeId: <int>{},
      };
    }
  }

"""
    replace_once(history, marker, method + marker)

    sync = root / 'lib/services/user_sync_service.dart'
    old = """    final historyService = WatchHistoryService();
    for (final anime in await historyService.getHistory()) {
      final watchedEpisodes = await historyService.getWatchedEpisodeNumbers(
        anime.animeId,
      );
      final state = UserAnimeState.fromHistory(
        anime,
        watchedEpisodes: watchedEpisodes,
      );
      states[state.animeId] = state;
    }
"""
    new = """    final historyService = WatchHistoryService();
    final history = await historyService.getHistory();
    final watchedEpisodesByAnimeId = await historyService
        .getWatchedEpisodeNumbersForHistory(history);
    for (final anime in history) {
      final state = UserAnimeState.fromHistory(
        anime,
        watchedEpisodes:
            watchedEpisodesByAnimeId[anime.animeId] ?? const <int>{},
      );
      states[state.animeId] = state;
    }
"""
    replace_once(sync, old, new)

    test = root / 'test/services/watch_history_batch_test.dart'
    test.write_text("""import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/history_anime.dart';
import 'package:goanime/services/watch_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    if (databaseFactoryOrNull == null) databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'watched_episodes_marked': ['3', 'bad', '1', '3', '-2'],
    });
    await WatchHistoryService.debugResetDatabase();
  });

  tearDown(() async {
    await WatchHistoryService.debugResetDatabase();
  });

  test('batch watched markers reuse history fallback and normalize prefs', () async {
    final service = WatchHistoryService();
    final history = <HistoryAnime>[
      _history('marked', episode: 9, progress: 0.2),
      _history('fallback', episode: 7, progress: 0.9),
      _history('partial', episode: 2, progress: 0.5),
    ];

    final result = await service.getWatchedEpisodeNumbersForHistory(history);

    expect(result['marked'], {1, 3});
    expect(result['fallback'], {7});
    expect(result['partial'], isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('watched_episodes_marked'), ['1', '3']);
    expect(prefs.getStringList('watched_episodes_fallback'), ['7']);
    expect(prefs.getStringList('watched_episodes_partial'), isNull);
  });
}

HistoryAnime _history(
  String animeId, {
  required int episode,
  required double progress,
}) {
  return HistoryAnime(
    animeId: animeId,
    title: animeId,
    coverImage: '',
    watchedAt: '2026-08-19T00:00:00Z',
    updatedAt: '2026-08-19T00:00:00Z',
    lastEpisode: 'Episode $episode',
    episodeNumber: episode,
    progress: progress,
  );
}
""", encoding='utf-8')


if __name__ == '__main__':
    main()
