import 'package:flutter_test/flutter_test.dart';

import '../../tools/super_animes_catalog_crosswalk.dart';
import '../../tools/super_animes_catalog_crawl_state.dart';
import '../../tools/super_animes_catalog_harvest_state.dart';
import '../../tools/super_animes_catalog_pipeline.dart';

void main() {
  test('clean exhausted audit is complete', () {
    final result = SuperAnimesCatalogPipelineResult(
      crawlState: SuperAnimesCatalogCrawlState(),
      harvestState: SuperAnimesCatalogHarvestState(),
      crosswalk: const SuperAnimesCatalogCrosswalk(entries: [], conflicts: []),
    );

    expect(result.hasRejectedMetadata, isFalse);
    expect(result.hasIdentityConflicts, isFalse);
    expect(result.complete, isTrue);
  });

  test('parser-rejected metadata keeps audit partial', () {
    final rejected = Uri.parse(
      'https://superanimes.com.br/anime/death-note-1535',
    );
    final result = SuperAnimesCatalogPipelineResult(
      crawlState: SuperAnimesCatalogCrawlState(),
      harvestState: SuperAnimesCatalogHarvestState(
        rejectedAnimePages: [rejected],
      ),
      crosswalk: const SuperAnimesCatalogCrosswalk(entries: [], conflicts: []),
    );

    expect(result.metadataFrontierComplete, isTrue);
    expect(result.hasRejectedMetadata, isTrue);
    expect(result.complete, isFalse);
  });

  test('identity conflict keeps otherwise exhausted audit partial', () {
    final page = Uri.parse('https://superanimes.com.br/anime/death-note-1535');
    final result = SuperAnimesCatalogPipelineResult(
      crawlState: SuperAnimesCatalogCrawlState(),
      harvestState: SuperAnimesCatalogHarvestState(),
      crosswalk: SuperAnimesCatalogCrosswalk(
        entries: const [],
        conflicts: [
          SuperAnimesCatalogCrosswalkConflict(
            anilistId: 1535,
            malIds: const [1535, 9999],
            pageUrls: [page],
          ),
        ],
      ),
    );

    expect(result.hasIdentityConflicts, isTrue);
    expect(result.complete, isFalse);
  });
}
