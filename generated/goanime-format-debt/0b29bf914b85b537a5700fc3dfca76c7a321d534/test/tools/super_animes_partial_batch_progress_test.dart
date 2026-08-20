import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../tools/super_animes_anilist_mal_resolver.dart';
import '../../tools/super_animes_catalog_crawl_state.dart';
import '../../tools/super_animes_catalog_harvest_state.dart';
import '../../tools/super_animes_catalog_harvester.dart';
import '../../tools/super_animes_catalog_metadata.dart';
import '../../tools/super_animes_catalog_pipeline.dart';
import '../../tools/super_animes_catalog_crawler.dart';

void main() {
  test(
    'keeps successful AniList batches when a later batch is rate limited',
    () async {
      var aniListCalls = 0;
      final aniListClient = MockClient((request) async {
        aniListCalls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final variables = body['variables'] as Map<String, dynamic>;
        final ids = (variables['ids'] as List<dynamic>).cast<int>();
        if (aniListCalls == 1) {
          expect(ids, List<int>.generate(50, (index) => index + 1));
          return http.Response(
            jsonEncode({
              'data': {
                'Page': {
                  'media': [
                    for (final id in ids) {'id': id, 'idMal': id + 1000},
                  ],
                },
              },
            }),
            200,
          );
        }
        expect(ids, [51]);
        return http.Response(
          'rate limited',
          429,
          headers: const {'retry-after': '3600'},
        );
      });
      final inertClient = MockClient(
        (request) async => http.Response('<html></html>', 200),
      );
      final pipeline = SuperAnimesCatalogPipeline(
        crawler: SuperAnimesCatalogCrawler(
          inertClient,
          minimumDelayBetweenRequests: Duration.zero,
        ),
        harvester: SuperAnimesCatalogHarvester(
          inertClient,
          minimumDelayBetweenRequests: Duration.zero,
        ),
        aniListMalResolver: SuperAnimesAniListMalResolver(
          aniListClient,
          minimumDelayBetweenRequests: Duration.zero,
          sleeper: (_) async {},
        ),
      );
      final metadata = [
        for (var id = 1; id <= 51; id++)
          SuperAnimesCatalogMetadata(
            title: 'anime $id',
            pageUrl: Uri.parse('https://superanimes.com.br/anime/anime-$id'),
            anilistId: id,
          ),
      ];

      final result = await pipeline.run(
        crawlState: SuperAnimesCatalogCrawlState(),
        harvestState: SuperAnimesCatalogHarvestState(metadata: metadata),
        maxCatalogPages: 0,
        maxAnimePages: 0,
      );

      expect(aniListCalls, 2);
      expect(result.aniListEnrichmentComplete, isFalse);
      expect(result.aniListEnrichmentFailure, 'http_error');
      expect(result.crosswalk.entries, hasLength(51));
      for (var index = 0; index < 50; index++) {
        final entry = result.crosswalk.entries[index];
        expect(entry.anilistId, index + 1);
        expect(entry.malId, index + 1001);
      }
      expect(result.crosswalk.entries.last.anilistId, 51);
      expect(result.crosswalk.entries.last.malId, isNull);
      expect(result.complete, isFalse);
    },
  );
}
