#!/usr/bin/env python3
from pathlib import Path
import argparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root
    service = root / 'lib/services/jikan_service.dart'
    text = service.read_text(encoding='utf-8')

    start_marker = '  Future<HomeData> _loadFreshHomeData() async {'
    end_marker = '  /// Parse da lista de animes de uma resposta HTTP'
    if text.count(start_marker) != 1 or text.count(end_marker) != 1:
        raise SystemExit('Jikan home load markers not found exactly once')
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    replacement = """  Future<HomeData> _loadFreshHomeData() async {
    debugPrint('[JikanService] Loading all home data with shared rate limiting...');

    try {
      final stopwatch = Stopwatch()..start();
      final today = _getCurrentDayOfWeek();

      // Start every logical section together. Individual HTTP requests still
      // pass through _waitForRateLimit(), which serializes request starts at
      // the platform-specific safe interval. This overlaps response/parsing
      // work and avoids an extra 350 ms delay between whole sections.
      final sections = await Future.wait<List<JikanAnime>>([
        getCurrentSeasonAnimes(limit: 25),
        getScheduleForDay(today, limit: 15),
        getTopAnimes(limit: 15),
        getAnimesByGenre(JikanGenreIds.action, limit: 15),
        getAnimesByGenre(JikanGenreIds.romance, limit: 15),
        getAnimesByGenre(JikanGenreIds.comedy, limit: 15),
        getAnimesByGenre(JikanGenreIds.fantasy, limit: 15),
      ]);

      final seasonList = [...sections[0]];
      seasonList.sort((a, b) {
        if (a.airedFromIso == null && b.airedFromIso == null) return 0;
        if (a.airedFromIso == null) return 1;
        if (b.airedFromIso == null) return -1;
        return b.airedFromIso!.compareTo(a.airedFromIso!);
      });

      stopwatch.stop();
      debugPrint(
        '[JikanService] All data loaded in ${stopwatch.elapsedMilliseconds}ms',
      );

      return HomeData(
        seasonAnimes: seasonList,
        todaysReleases: sections[1],
        topAnimes: sections[2],
        actionAnimes: sections[3],
        romanceAnimes: sections[4],
        comedyAnimes: sections[5],
        fantasyAnimes: sections[6],
      );
    } catch (e) {
      if (propagateErrors) rethrow;
      debugPrint('[JikanService] Error loading home data: $e');
      return HomeData(
        seasonAnimes: [],
        todaysReleases: [],
        topAnimes: [],
        actionAnimes: [],
        romanceAnimes: [],
        comedyAnimes: [],
        fantasyAnimes: [],
      );
    }
  }

  @visibleForTesting
  Future<HomeData> debugLoadFreshHomeDataForTesting() => _loadFreshHomeData();

"""
    service.write_text(text[:start] + replacement + text[end:], encoding='utf-8')

    test = root / 'test/services/jikan_home_parallel_load_test.dart'
    test.write_text("""import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/jikan_models.dart';
import 'package:goanime/services/jikan_service.dart';

void main() {
  test('fresh Home starts all logical sections before any one finishes', () async {
    final service = _ConcurrentHomeJikanService();

    final load = service.debugLoadFreshHomeDataForTesting();
    await Future<void>.delayed(Duration.zero);

    expect(service.started.toSet(), {
      'season',
      'today',
      'top',
      'action',
      'romance',
      'comedy',
      'fantasy',
    });

    for (final entry in service.sections.entries) {
      entry.value.complete([_anime(entry.key)]);
    }
    final data = await load;

    expect(data.seasonAnimes.single.title, 'season');
    expect(data.todaysReleases.single.title, 'today');
    expect(data.topAnimes.single.title, 'top');
    expect(data.actionAnimes.single.title, 'action');
    expect(data.romanceAnimes.single.title, 'romance');
    expect(data.comedyAnimes.single.title, 'comedy');
    expect(data.fantasyAnimes.single.title, 'fantasy');
  });

  test('sorting season results does not mutate the provider-owned list', () async {
    final service = _ConcurrentHomeJikanService();
    final first = _anime('older', airedFromIso: '2026-01-01T00:00:00Z');
    final second = _anime('newer', airedFromIso: '2026-02-01T00:00:00Z');
    final providerList = <JikanAnime>[first, second];

    final load = service.debugLoadFreshHomeDataForTesting();
    await Future<void>.delayed(Duration.zero);
    service.sections['season']!.complete(providerList);
    for (final key in service.sections.keys.where((key) => key != 'season')) {
      service.sections[key]!.complete([_anime(key)]);
    }
    final data = await load;

    expect(data.seasonAnimes.map((anime) => anime.title), ['newer', 'older']);
    expect(providerList.map((anime) => anime.title), ['older', 'newer']);
  });
}

class _ConcurrentHomeJikanService extends JikanService {
  _ConcurrentHomeJikanService() : super(propagateErrors: true);

  final List<String> started = [];
  final Map<String, Completer<List<JikanAnime>>> sections = {
    for (final key in const [
      'season',
      'today',
      'top',
      'action',
      'romance',
      'comedy',
      'fantasy',
    ])
      key: Completer<List<JikanAnime>>(),
  };

  Future<List<JikanAnime>> _start(String key) {
    started.add(key);
    return sections[key]!.future;
  }

  @override
  Future<List<JikanAnime>> getCurrentSeasonAnimes({int page = 1, int limit = 20}) =>
      _start('season');

  @override
  Future<List<JikanAnime>> getScheduleForDay(String day, {int limit = 25}) =>
      _start('today');

  @override
  Future<List<JikanAnime>> getTopAnimes({int page = 1, int limit = 20}) =>
      _start('top');

  @override
  Future<List<JikanAnime>> getAnimesByGenre(
    int genreId, {
    int page = 1,
    int limit = 20,
  }) {
    return switch (genreId) {
      JikanGenreIds.action => _start('action'),
      JikanGenreIds.romance => _start('romance'),
      JikanGenreIds.comedy => _start('comedy'),
      JikanGenreIds.fantasy => _start('fantasy'),
      _ => Future.value(const <JikanAnime>[]),
    };
  }
}

JikanAnime _anime(String title, {String? airedFromIso}) {
  return JikanAnime(
    malId: title.hashCode,
    title: title,
    imageUrl: '',
    airedFromIso: airedFromIso,
  );
}
""", encoding='utf-8')


if __name__ == '__main__':
    main()
