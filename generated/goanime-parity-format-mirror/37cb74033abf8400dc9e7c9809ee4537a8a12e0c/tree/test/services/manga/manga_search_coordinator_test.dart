import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/manga/manga_availability_models.dart';
import 'package:goanime/services/manga/manga_provider_policy.dart';
import 'package:goanime/services/manga/manga_request_scheduler.dart';
import 'package:goanime/services/manga/manga_search_coordinator.dart';
import 'package:goanime/services/manga/manga_source_registry.dart';
import 'package:goanime_core/goanime_core.dart';

import '../../helpers/fake_manga_source_provider.dart';

void main() {
  test(
    'emits readable results progressively and collapses trusted A B match',
    () async {
      final aSearch = Completer<MangaSearchPage>();
      final bSearch = Completer<MangaSearchPage>();
      final cSearch = Completer<MangaSearchPage>();
      final providers = [
        _provider('ptbr.a', aSearch),
        _provider('ptbr.b', bSearch),
        _provider('ptbr.c', cSearch),
      ];
      final policies = {
        for (final provider in providers)
          provider.sourceId: MangaProviderPolicy(
            sourceId: provider.sourceId,
            maxConcurrent: 1,
            minimumRequestSpacing: Duration.zero,
          ),
      };
      final registry = MangaSourceRegistry(
        providers: providers,
        policies: policies,
      );
      final scheduler = MangaRequestScheduler(policies: policies);
      var nextWorkId = 0;
      final coordinator = MangaSearchCoordinator(
        registry: registry,
        scheduler: scheduler,
        newWorkId: () => 'mw_${++nextWorkId}',
      );
      final events = <MangaSearchUpdate>[];
      final done = Completer<void>();
      coordinator
          .search('Example', ownerToken: Object())
          .listen(events.add, onDone: done.complete);

      aSearch.complete(_page('ptbr.a', 'a-1'));
      await _flush();

      expect(events, hasLength(1));
      expect(events.single.isComplete, isFalse);
      expect(events.single.results, hasLength(1));
      expect(events.single.results.single.sourceLinks, hasLength(1));
      expect(
        events.single.results.single.sourceLinks.single.occurrence.sourceId,
        'ptbr.a',
      );

      bSearch.complete(_page('ptbr.b', 'b-1'));
      cSearch.completeError(StateError('provider unavailable'));
      await done.future;

      expect(events.last.isComplete, isTrue);
      expect(events.last.results, hasLength(1));
      expect(events.last.results.single.work.workId, 'mw_1');
      expect(
        events.last.results.single.sourceLinks
            .map((link) => link.occurrence.sourceId)
            .toSet(),
        {'ptbr.a', 'ptbr.b'},
      );
      expect(events.last.results.single.evidence, hasLength(2));
    },
  );

  test(
    'an older generation cannot emit or persist after a newer search starts',
    () async {
      final oldSearch = Completer<MangaSearchPage>();
      final persistence = _RecordingSearchPersistence();
      final provider = FakeMangaSourceProvider(
        sourceId: 'ptbr.a',
        searchHandler: (request) {
          if (request.query == 'old') return oldSearch.future;
          return Future.value(_page('ptbr.a', 'new-1', title: 'New Work'));
        },
        detailsHandler: (occurrence) async => MangaSourceDetails(
          occurrence: occurrence,
          externalIds: [
            MangaExternalId(namespace: 'mangadex', value: occurrence.mangaId),
          ],
        ),
      );
      const policy = MangaProviderPolicy(
        sourceId: 'ptbr.a',
        maxConcurrent: 2,
        minimumRequestSpacing: Duration.zero,
      );
      final registry = MangaSourceRegistry(
        providers: [provider],
        policies: const {'ptbr.a': policy},
      );
      final scheduler = MangaRequestScheduler(
        policies: const {'ptbr.a': policy},
      );
      var nextWorkId = 0;
      final coordinator = MangaSearchCoordinator(
        registry: registry,
        scheduler: scheduler,
        persistence: persistence,
        newWorkId: () => 'mw_${++nextWorkId}',
      );
      final oldEvents = <MangaSearchUpdate>[];
      final oldDone = Completer<void>();
      coordinator
          .search('old', ownerToken: Object())
          .listen(oldEvents.add, onDone: oldDone.complete);

      final newEvents = await coordinator
          .search('new', ownerToken: Object())
          .toList();
      expect(newEvents.last.isComplete, isTrue);
      expect(newEvents.last.results.single.work.canonicalTitle, 'New Work');
      expect(
        persistence.records
            .map((record) => record.work.canonicalTitle)
            .toList(),
        ['New Work'],
      );

      oldSearch.complete(_page('ptbr.a', 'old-1', title: 'Old Work'));
      await oldDone.future;
      expect(oldEvents, isEmpty);
      expect(
        persistence.records
            .map((record) => record.work.canonicalTitle)
            .toList(),
        ['New Work'],
      );
    },
  );

  test(
    'serves cached results immediately for identical query within TTL',
    () async {
      var searchCount = 0;
      final provider = FakeMangaSourceProvider(
        sourceId: 'ptbr.a',
        searchHandler: (request) {
          searchCount++;
          return Future.value(
            _page('ptbr.a', 'cached-1', title: 'Cached Work'),
          );
        },
        detailsHandler: (occurrence) async =>
            MangaSourceDetails(occurrence: occurrence),
      );
      const policy = MangaProviderPolicy(
        sourceId: 'ptbr.a',
        maxConcurrent: 2,
        minimumRequestSpacing: Duration.zero,
      );
      final registry = MangaSourceRegistry(
        providers: [provider],
        policies: const {'ptbr.a': policy},
      );
      final scheduler = MangaRequestScheduler(
        policies: const {'ptbr.a': policy},
      );
      final coordinator = MangaSearchCoordinator(
        registry: registry,
        scheduler: scheduler,
        cacheTtl: const Duration(minutes: 5),
      );

      final firstResults = await coordinator
          .search('Cached Query', ownerToken: Object())
          .toList();
      expect(
        firstResults.last.results.single.work.canonicalTitle,
        'Cached Work',
      );
      expect(searchCount, 1);

      final cachedResults = await coordinator
          .search('cached query', ownerToken: Object())
          .toList();
      expect(
        cachedResults.last.results.single.work.canonicalTitle,
        'Cached Work',
      );
      expect(cachedResults.last.isComplete, isTrue);
      expect(searchCount, 1); // Provider not called again due to cache hit
    },
  );

  test(
    'evicts least-recent search when CachePolicy capacity is exceeded',
    () async {
      var searchCount = 0;
      final provider = FakeMangaSourceProvider(
        sourceId: 'ptbr.a',
        searchHandler: (request) {
          searchCount++;
          return Future.value(
            _page(
              'ptbr.a',
              '${request.query}-$searchCount',
              title: request.query,
            ),
          );
        },
        detailsHandler: (occurrence) async =>
            MangaSourceDetails(occurrence: occurrence),
      );
      const providerPolicy = MangaProviderPolicy(
        sourceId: 'ptbr.a',
        maxConcurrent: 2,
        minimumRequestSpacing: Duration.zero,
      );
      final registry = MangaSourceRegistry(
        providers: [provider],
        policies: const {'ptbr.a': providerPolicy},
      );
      final scheduler = MangaRequestScheduler(
        policies: const {'ptbr.a': providerPolicy},
      );
      final coordinator = MangaSearchCoordinator(
        registry: registry,
        scheduler: scheduler,
        cachePolicy: const CachePolicy(
          ttl: Duration(minutes: 5),
          maxEntries: 1,
          staleWhileRevalidate: false,
        ),
      );

      await coordinator.search('first', ownerToken: Object()).toList();
      await coordinator.search('second', ownerToken: Object()).toList();
      expect(searchCount, 2);

      await coordinator.search('first', ownerToken: Object()).toList();
      expect(
        searchCount,
        3,
        reason: 'the first query must have been evicted when capacity is one',
      );
    },
  );
}

final class _RecordingSearchPersistence implements MangaSearchPersistence {
  final List<MangaAvailabilityRecord> records = [];

  @override
  Future<void> persist(MangaAvailabilityRecord record) async {
    records.add(record);
  }
}

FakeMangaSourceProvider _provider(
  String sourceId,
  Completer<MangaSearchPage> search,
) {
  return FakeMangaSourceProvider(
    sourceId: sourceId,
    searchHandler: (_) => search.future,
    detailsHandler: (occurrence) async => MangaSourceDetails(
      occurrence: occurrence,
      authors: const ['Shared Author'],
      externalIds: const [
        MangaExternalId(namespace: 'mangadex', value: 'trusted-work'),
      ],
    ),
  );
}

MangaSearchPage _page(
  String sourceId,
  String mangaId, {
  String title = 'Example Work',
}) {
  return MangaSearchPage(
    items: [
      MangaSourceOccurrence(sourceId: sourceId, mangaId: mangaId, title: title),
    ],
  );
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
