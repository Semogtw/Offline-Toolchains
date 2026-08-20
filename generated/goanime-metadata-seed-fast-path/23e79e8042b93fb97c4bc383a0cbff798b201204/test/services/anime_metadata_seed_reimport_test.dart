import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/anime_metadata_cache_models.dart';
import 'package:goanime/services/anime_metadata_cache_service.dart';
import 'package:goanime/services/anime_metadata_seed_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AnimeMetadataCacheService.debugResetDatabase();
  });

  tearDown(AnimeMetadataCacheService.debugResetDatabase);

  test('unchanged bundled seed is not rewritten on every startup', () async {
    final generatedAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 1),
    );
    final payload = AnimeMetadataSeedPayload(
      schemaVersion: AnimeMetadataSeedPayload.currentSchemaVersion,
      generatedAt: generatedAt,
      entries: [
        AnimeMetadataCacheEntry(
          malId: 42,
          title: 'Persistent Seed Anime',
          imageUrl: 'https://cdn.example/42.webp',
          year: generatedAt.year,
          season: 'summer',
          genres: const ['Action'],
          updatedAt: generatedAt,
        ),
      ],
    );
    final cache = AnimeMetadataCacheService();
    var bundledSeedLoads = 0;
    const bundledDigest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final service = AnimeMetadataSeedService(
      cacheService: cache,
      now: () => generatedAt.add(const Duration(minutes: 2)),
      bundledSeedLoader: () async {
        bundledSeedLoads += 1;
        return jsonEncode(payload.toJson());
      },
      bundledSeedDigestLoader: () async => bundledDigest,
    );

    final first = await service.importIfNeeded(manifestUrlOverride: '');
    final second = await service.importIfNeeded(manifestUrlOverride: '');

    expect(first, AnimeMetadataSeedImportResult.imported);
    expect(second, AnimeMetadataSeedImportResult.disabled);
    expect(bundledSeedLoads, 1);
    expect(await cache.count(), 1);

    await cache.clearAll();
    final repaired = await service.importIfNeeded(manifestUrlOverride: '');

    expect(repaired, AnimeMetadataSeedImportResult.imported);
    expect(bundledSeedLoads, 2);
    expect(await cache.count(), 1);
  });
}
