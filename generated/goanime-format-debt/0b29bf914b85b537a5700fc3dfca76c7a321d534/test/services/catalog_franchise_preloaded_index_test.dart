import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/anime_franchise_models.dart';
import 'package:goanime/models/catalog_display_entry.dart';
import 'package:goanime/models/franchise_availability_cache_models.dart';
import 'package:goanime/models/jikan_models.dart';
import 'package:goanime/services/anime_franchise_cache_service.dart';
import 'package:goanime/services/catalog_franchise_display_service.dart';
import 'package:goanime/services/franchise_availability_cache_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (databaseFactoryOrNull == null) {
    databaseFactory = databaseFactoryFfi;
  }

  late CatalogFranchiseDisplayService service;

  setUp(() async {
    await AnimeFranchiseCacheService.debugResetDatabase();
    FranchiseAvailabilityCacheService.debugSetPayloadForTesting(
      FranchiseAvailabilityCachePayload.empty(),
    );
    service = CatalogFranchiseDisplayService(
      cacheService: AnimeFranchiseCacheService(),
    );
  });

  tearDown(() async {
    await AnimeFranchiseCacheService.debugResetDatabase();
    await FranchiseAvailabilityCacheService.debugResetForTesting();
  });

  test('reuses a preloaded franchise index across catalog sections', () async {
    final franchise = _franchise();
    final indexed = <int, AnimeFranchise>{1: franchise, 2: franchise};

    final sourceSection = await service.collapseCachedFranchises(
      [_anime(2, 'Season 2'), _anime(1, 'Season 1')],
      mode: CatalogFranchiseDisplayMode.source,
      indexedFranchises: indexed,
    );
    final canonicalSection = await service.collapseCachedFranchises([
      _anime(1, 'Season 1'),
      _anime(2, 'Season 2'),
    ], indexedFranchises: indexed);

    expect(sourceSection, hasLength(1));
    expect(sourceSection.single.type, CatalogDisplayEntryType.franchise);
    expect(sourceSection.single.selectedMalId, 2);
    expect(sourceSection.single.anime.malId, 2);

    expect(canonicalSection, hasLength(1));
    expect(canonicalSection.single.type, CatalogDisplayEntryType.franchise);
    expect(canonicalSection.single.selectedMalId, 1);
    expect(canonicalSection.single.anime.malId, 1);
  });
}

AnimeFranchise _franchise() {
  final now = DateTime.now();
  return AnimeFranchise(
    franchiseId: 'mal_franchise_1',
    canonicalMalId: 1,
    displayTitle: 'Official Franchise',
    coverImage: 'cover.jpg',
    entries: [
      AnimeFranchiseEntry(
        malId: 1,
        anime: _anime(1, 'Season 1'),
        relationType: 'Self',
        kind: AnimeFranchiseEntryKind.tv,
        group: FranchiseEntryGroup.mainline,
        isAvailable: true,
        isMainline: true,
        label: 'Temporada 1',
        sortIndex: 0,
        unavailableReason: null,
        isCanonical: true,
      ),
      AnimeFranchiseEntry(
        malId: 2,
        anime: _anime(2, 'Season 2'),
        relationType: 'Sequel',
        kind: AnimeFranchiseEntryKind.tv,
        group: FranchiseEntryGroup.mainline,
        isAvailable: true,
        isMainline: true,
        label: 'Temporada 2',
        sortIndex: 1,
        unavailableReason: null,
        isCanonical: false,
      ),
    ],
    graphEdges: const [
      AnimeFranchiseGraphEdge(
        sourceMalId: 1,
        targetMalId: 2,
        relationType: 'Sequel',
      ),
    ],
    savedAt: now,
    expiresAt: now.add(const Duration(days: 1)),
  );
}

JikanAnime _anime(int malId, String title) {
  return JikanAnime(malId: malId, title: title, imageUrl: '$malId.jpg');
}
