import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Anime and Manga delegate equivalent provider scheduling', () {
    final unified = File(
      'lib/services/unified_source_service.dart',
    ).readAsStringSync();
    final aggregator = File(
      'lib/services/source/episode_aggregator.dart',
    ).readAsStringSync();
    final animeSearch = File(
      'lib/services/providers/anime_provider_search_service.dart',
    ).readAsStringSync();
    final manga = File(
      'lib/services/manga/manga_request_scheduler.dart',
    ).readAsStringSync();

    expect(unified, contains('ProviderRequestScheduler'));
    expect(unified, contains('provider.providerKey'));
    expect(unified, isNot(contains('_AsyncPermitPool')));

    expect(aggregator, contains('ProviderRequestScheduler'));
    expect(aggregator, contains('match.provider.providerKey'));
    expect(aggregator, isNot(contains('Future<void> runWithConcurrency')));

    expect(animeSearch, contains('ProviderRequestScheduler'));
    expect(animeSearch, contains('provider.providerKey'));
    expect(animeSearch, contains('RequestPriority.prefetch'));
    expect(animeSearch, isNot(contains('provider.searchAnime(query).timeout')));

    expect(manga, contains('ProviderRequestScheduler'));
  });
}
