import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/anime_franchise_models.dart';
import 'package:goanime/models/catalog_display_entry.dart';
import 'package:goanime/models/franchise_availability_cache_models.dart';
import 'package:goanime/models/jikan_models.dart';
import 'package:goanime/services/catalog_franchise_display_service.dart';
import 'package:goanime/services/anime_franchise_cache_service.dart';
import 'package:goanime/services/franchise_availability_cache_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (databaseFactoryOrNull == null) {
    databaseFactory = databaseFactoryFfi;
  }

  late AnimeFranchiseCacheService cacheService;
  late CatalogFranchiseDisplayService service;

  setUp(() async {
    cacheService = AnimeFranchiseCacheService();
    await AnimeFranchiseCacheService.debugResetDatabase();
    FranchiseAvailabilityCacheService.debugSetPayloadForTesting(
      FranchiseAvailabilityCachePayload.empty(),
    );
    service = CatalogFranchiseDisplayService(cacheService: cacheService);
  });

  tearDown(() async {
    await AnimeFranchiseCacheService.debugResetDatabase();
    await FranchiseAvailabilityCacheService.debugResetForTesting();
  });

  test('keeps normal anime when there is no cached franchise', () async {
    final entries = await service.collapseCachedFranchises([
      _anime(1, 'Single'),
    ]);

    expect(entries, hasLength(1));
    expect(entries.single.type, CatalogDisplayEntryType.singleAnime);
    expect(entries.single.anime.malId, 1);
  });

  test('batch cache lookup maps every indexed MAL id in one result', () async {
    await cacheService.save(_franchise());

    final franchises = await cacheService.getByMalIds([1, 2, 99, -1, 2]);

    expect(franchises.keys.toSet(), {1, 2});
    expect(franchises[1]?.franchiseId, 'mal_franchise_1');
    expect(franchises[2]?.franchiseId, 'mal_franchise_1');
  });

  test('batch cache lookup preserves expiration semantics', () async {
    await cacheService.save(
      _franchise(expiresAt: DateTime.now().subtract(const Duration(days: 1))),
    );

    expect(await cacheService.getByMalIds([1, 2]), isEmpty);
    final stale = await cacheService.getByMalIds([1, 2], allowExpired: true);
    expect(stale.keys.toSet(), {1, 2});
    expect(stale.values.every((franchise) => franchise.isStale), isTrue);
  });

  test(
    'collapses cached seasons by franchise id without title matching',
    () async {
      final franchise = _franchise();
      await cacheService.save(franchise);

      final entries = await service.collapseCachedFranchises([
        _anime(2, 'Completely Different Local Title'),
        _anime(1, 'Another Local Title'),
        _anime(99, 'Unrelated'),
      ]);

      expect(entries, hasLength(2));
      expect(entries.first.type, CatalogDisplayEntryType.franchise);
      expect(entries.first.franchise!.franchiseId, 'mal_franchise_1');
      expect(entries.first.selectedMalId, 1);
      expect(entries.first.anime.title, 'Official Franchise');
      expect(entries.last.type, CatalogDisplayEntryType.singleAnime);
      expect(entries.last.anime.malId, 99);
    },
  );

  test(
    'does not collapse expired franchise cache as fresh catalog data',
    () async {
      await cacheService.save(
        _franchise(expiresAt: DateTime.now().subtract(const Duration(days: 1))),
      );

      final entries = await service.collapseCachedFranchises([
        _anime(1, 'Season 1'),
        _anime(2, 'Season 2'),
      ]);

      expect(entries.map((entry) => entry.type), [
        CatalogDisplayEntryType.singleAnime,
        CatalogDisplayEntryType.singleAnime,
      ]);
    },
  );

  test('collapses using injected franchise payload in tests', () async {
    final franchise = _franchise();
    FranchiseAvailabilityCacheService.debugSetPayloadForTesting(
      FranchiseAvailabilityCachePayload(
        schemaVersion: FranchiseAvailabilityCachePayload.currentSchemaVersion,
        generatedAt: '2026-05-18T00:00:00Z',
        franchises: [franchise],
        franchiseIdByMalId: const {1: 'mal_franchise_1', 2: 'mal_franchise_1'},
        latestMainlineMalIdByFranchiseId: const {'mal_franchise_1': 2},
      ),
    );

    final entries = await service.collapseFranchises([
      _anime(2, 'Season 2'),
      _anime(1, 'Season 1'),
    ]);

    expect(entries, hasLength(1));
    expect(entries.single.type, CatalogDisplayEntryType.franchise);
    expect(entries.single.anime.malId, 1);
    expect(entries.single.selectedMalId, 1);
    expect(entries.single.anime.title, 'Official Franchise');
  });

  test('latest mode selects newest available mainline entry', () async {
    final franchise = _franchise();
    FranchiseAvailabilityCacheService.debugSetPayloadForTesting(
      FranchiseAvailabilityCachePayload(
        schemaVersion: FranchiseAvailabilityCachePayload.currentSchemaVersion,
        generatedAt: '2026-05-18T00:00:00Z',
        franchises: [franchise],
        franchiseIdByMalId: const {1: 'mal_franchise_1', 2: 'mal_franchise_1'},
        latestMainlineMalIdByFranchiseId: const {'mal_franchise_1': 2},
      ),
    );

    final entries = await service.collapseFranchises([
      _anime(1, 'Season 1'),
      _anime(2, 'Season 2'),
    ], mode: CatalogFranchiseDisplayMode.latest);

    expect(entries, hasLength(1));
    expect(entries.single.anime.malId, 2);
    expect(entries.single.selectedMalId, 2);
  });

  test(
    'source mode keeps the listed season instead of old canonical entry',
    () async {
      final franchise = _franchise();
      FranchiseAvailabilityCacheService.debugSetPayloadForTesting(
        FranchiseAvailabilityCachePayload(
          schemaVersion: FranchiseAvailabilityCachePayload.currentSchemaVersion,
          generatedAt: '2026-05-18T00:00:00Z',
          franchises: [franchise],
          franchiseIdByMalId: const {
            1: 'mal_franchise_1',
            2: 'mal_franchise_1',
          },
          latestMainlineMalIdByFranchiseId: const {'mal_franchise_1': 2},
        ),
      );

      final entries = await service.collapseFranchises([
        _anime(2, 'Season 2'),
        _anime(1, 'Season 1'),
      ], mode: CatalogFranchiseDisplayMode.source);

      expect(entries, hasLength(1));
      expect(entries.single.type, CatalogDisplayEntryType.franchise);
      expect(entries.single.anime.malId, 2);
      expect(entries.single.selectedMalId, 2);
    },
  );

  test(
    'does not collapse hidden crossover entries through franchise index',
    () async {
      final franchise = _franchise(
        extras: [
          AnimeFranchiseEntry(
            malId: 3,
            anime: _anime(3, 'Crossover'),
            relationType: 'Prequel',
            kind: AnimeFranchiseEntryKind.tv,
            group: FranchiseEntryGroup.extra,
            isAvailable: true,
            isMainline: false,
            label: 'Crossover',
            sortIndex: 2,
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
          AnimeFranchiseGraphEdge(
            sourceMalId: 1,
            targetMalId: 3,
            relationType: 'Character',
          ),
        ],
      );
      FranchiseAvailabilityCacheService.debugSetPayloadForTesting(
        FranchiseAvailabilityCachePayload(
          schemaVersion: FranchiseAvailabilityCachePayload.currentSchemaVersion,
          generatedAt: '2026-05-18T00:00:00Z',
          franchises: [franchise],
          franchiseIdByMalId: const {
            1: 'mal_franchise_1',
            2: 'mal_franchise_1',
            3: 'mal_franchise_1',
          },
          latestMainlineMalIdByFranchiseId: const {'mal_franchise_1': 2},
        ),
      );

      final entries = await service.collapseFranchises([
        _anime(3, 'Crossover'),
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.type, CatalogDisplayEntryType.singleAnime);
      expect(entries.single.anime.malId, 3);
    },
  );

  test(
    'can suppress indexed hidden entries for search result de-duplication',
    () async {
      final franchise = _franchise(
        extras: [
          AnimeFranchiseEntry(
            malId: 3,
            anime: _anime(3, 'Crossover'),
            relationType: 'Prequel',
            kind: AnimeFranchiseEntryKind.tv,
            group: FranchiseEntryGroup.extra,
            isAvailable: true,
            isMainline: false,
            label: 'Crossover',
            sortIndex: 2,
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
          AnimeFranchiseGraphEdge(
            sourceMalId: 1,
            targetMalId: 3,
            relationType: 'Character',
          ),
        ],
      );
      FranchiseAvailabilityCacheService.debugSetPayloadForTesting(
        FranchiseAvailabilityCachePayload(
          schemaVersion: FranchiseAvailabilityCachePayload.currentSchemaVersion,
          generatedAt: '2026-05-18T00:00:00Z',
          franchises: [franchise],
          franchiseIdByMalId: const {
            1: 'mal_franchise_1',
            2: 'mal_franchise_1',
            3: 'mal_franchise_1',
          },
          latestMainlineMalIdByFranchiseId: const {'mal_franchise_1': 2},
        ),
      );

      final entries = await service.collapseFranchises([
        _anime(3, 'Crossover'),
        _anime(99, 'Standalone'),
      ], suppressIndexedHiddenEntries: true);

      expect(entries, hasLength(1));
      expect(entries.single.type, CatalogDisplayEntryType.singleAnime);
      expect(entries.single.anime.malId, 99);
    },
  );

  test(
    'suppresses weak local season placeholders after emitting franchise card',
    () async {
      final franchise = _franchise(displayTitle: 'Overlord');
      FranchiseAvailabilityCacheService.debugSetPayloadForTesting(
        FranchiseAvailabilityCachePayload(
          schemaVersion: FranchiseAvailabilityCachePayload.currentSchemaVersion,
          generatedAt: '2026-05-18T00:00:00Z',
          franchises: [franchise],
          franchiseIdByMalId: const {
            1: 'mal_franchise_1',
            2: 'mal_franchise_1',
          },
          latestMainlineMalIdByFranchiseId: const {'mal_franchise_1': 2},
        ),
      );

      final entries = await service.collapseFranchises([
        _placeholder('Overlord 2'),
        _placeholder('Overlord 3'),
        _anime(1, 'Overlord'),
        _placeholder('Overlord Ple Ple Pleiades'),
        _placeholder('Standalone'),
      ], suppressIndexedHiddenEntries: true);

      expect(entries, hasLength(2));
      expect(entries.first.type, CatalogDisplayEntryType.franchise);
      expect(entries.first.anime.title, 'Overlord');
      expect(entries.last.type, CatalogDisplayEntryType.singleAnime);
      expect(entries.last.anime.title, 'Standalone');
    },
  );
}

AnimeFranchise _franchise({
  DateTime? expiresAt,
  List<AnimeFranchiseEntry> extras = const [],
  List<AnimeFranchiseGraphEdge> graphEdges = const [],
  String displayTitle = 'Official Franchise',
}) {
  final now = DateTime.now();
  return AnimeFranchise(
    franchiseId: 'mal_franchise_1',
    canonicalMalId: 1,
    displayTitle: displayTitle,
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
      ...extras,
    ],
    graphEdges: graphEdges,
    savedAt: now,
    expiresAt: expiresAt ?? now.add(const Duration(days: 1)),
  );
}

JikanAnime _anime(int malId, String title) {
  return JikanAnime(malId: malId, title: title, imageUrl: '$malId.jpg');
}

JikanAnime _placeholder(String title) {
  return JikanAnime(malId: -title.hashCode.abs(), title: title, imageUrl: '');
}
