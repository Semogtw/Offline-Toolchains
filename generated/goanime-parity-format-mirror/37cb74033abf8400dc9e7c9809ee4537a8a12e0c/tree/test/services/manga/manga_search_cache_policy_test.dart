import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/manga/manga_provider_policy.dart';
import 'package:goanime/services/manga/manga_request_scheduler.dart';
import 'package:goanime/services/manga/manga_search_coordinator.dart';
import 'package:goanime/services/manga/manga_source_registry.dart';
import 'package:goanime_core/goanime_core.dart';

import '../../helpers/fake_manga_source_provider.dart';

void main() {
  test('Manga search cache is bounded and renews LRU recency on hit', () async {
    var searchCount = 0;
    final provider = FakeMangaSourceProvider(
      sourceId: 'ptbr.cache',
      searchHandler: (request) async {
        searchCount++;
        final id = request.query.toLowerCase();
        return MangaSearchPage(
          items: [
            MangaSourceOccurrence(
              sourceId: 'ptbr.cache',
              mangaId: id,
              title: request.query,
            ),
          ],
        );
      },
    );
    const providerPolicy = MangaProviderPolicy(
      sourceId: 'ptbr.cache',
      maxConcurrent: 2,
      minimumRequestSpacing: Duration.zero,
    );
    final registry = MangaSourceRegistry(
      providers: [provider],
      policies: const {'ptbr.cache': providerPolicy},
    );
    final scheduler = MangaRequestScheduler(
      policies: const {'ptbr.cache': providerPolicy},
    );
    final coordinator = MangaSearchCoordinator(
      registry: registry,
      scheduler: scheduler,
      cachePolicy: const CachePolicy(ttl: Duration(minutes: 5), maxEntries: 2),
    );

    await coordinator.search('one', ownerToken: Object()).toList();
    await coordinator.search('two', ownerToken: Object()).toList();
    await coordinator.search('one', ownerToken: Object()).toList();
    expect(searchCount, 2, reason: 'one should be a cache hit and become MRU');

    await coordinator.search('three', ownerToken: Object()).toList();
    expect(searchCount, 3);

    await coordinator.search('two', ownerToken: Object()).toList();
    expect(
      searchCount,
      4,
      reason: 'two should have been evicted after one renewed its recency',
    );

    scheduler.dispose();
  });
}
