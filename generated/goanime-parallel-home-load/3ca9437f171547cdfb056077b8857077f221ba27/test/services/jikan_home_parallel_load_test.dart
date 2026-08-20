import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/jikan_models.dart';
import 'package:goanime/services/availability_service.dart';
import 'package:goanime/services/jikan_service.dart';

void main() {
  test(
    'fresh Home starts all logical sections before any one finishes',
    () async {
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
    },
  );

  test(
    'sorting season results does not mutate the provider-owned list',
    () async {
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
    },
  );
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
  Future<List<JikanAnime>> getCurrentSeasonAnimes({
    int page = 1,
    int limit = 20,
  }) => _start('season');

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
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
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
