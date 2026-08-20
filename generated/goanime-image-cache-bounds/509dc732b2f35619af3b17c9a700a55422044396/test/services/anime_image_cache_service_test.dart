import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/anime_image_cache_models.dart';
import 'package:goanime/services/anime_image_cache_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../tools/build_franchise_runtime_artifacts.dart' as builder;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    if (databaseFactoryOrNull == null) {
      databaseFactory = databaseFactoryFfi;
    }
  });

  tearDown(() async {
    await AnimeImageCacheService.instance.debugResetForTesting();
  });

  test('imageForMalId retorna entry correta', () async {
    final dbPath = await _buildDatabase();
    await AnimeImageCacheService.instance.debugSetDatabasePathForTesting(
      dbPath,
    );

    final entry = await AnimeImageCacheService.instance.imageForMalId(1);

    expect(entry?.imageUrl, 'https://cdn.example/anime-1.jpg');
    expect(entry?.largeImageUrl, 'https://cdn.example/anime-1-large.jpg');
  });

  test('imageForFranchiseId retorna entry correta', () async {
    final dbPath = await _buildDatabase();
    await AnimeImageCacheService.instance.debugSetDatabasePathForTesting(
      dbPath,
    );

    final entry = await AnimeImageCacheService.instance.imageForFranchiseId(
      'mal_franchise_1',
    );

    expect(entry?.coverImage, 'https://cdn.example/franchise.jpg');
  });

  test('bestImageUrlForAnime prioriza largeImageUrl', () async {
    AnimeImageCacheService.instance.debugSetEntriesForTesting(
      animeImages: [
        _animeImage(
          1,
          imageUrl: 'https://cdn.example/small.jpg',
          largeImageUrl: 'https://cdn.example/large.jpg',
        ),
      ],
    );

    final url = await AnimeImageCacheService.instance.bestImageUrlForAnime(
      malId: 1,
      fallbackImageUrl: 'https://cdn.example/fallback.jpg',
    );

    expect(url, 'https://cdn.example/large.jpg');
  });

  test('bestImageUrlForAnime cai para imageUrl', () async {
    AnimeImageCacheService.instance.debugSetEntriesForTesting(
      animeImages: [_animeImage(1, imageUrl: 'https://cdn.example/small.jpg')],
    );

    final url = await AnimeImageCacheService.instance.bestImageUrlForAnime(
      malId: 1,
      fallbackImageUrl: 'https://cdn.example/fallback.jpg',
    );

    expect(url, 'https://cdn.example/small.jpg');
  });

  test('bestImageUrlForAnime cai para franchise cover', () async {
    AnimeImageCacheService.instance.debugSetEntriesForTesting(
      franchiseImages: [
        FranchiseImageCacheEntry(
          franchiseId: 'mal_franchise_1',
          canonicalMalId: 1,
          coverImage: 'https://cdn.example/franchise.jpg',
          bannerImage: null,
          source: 'franchise_cache',
          cachedAt: DateTime.utc(2026, 5, 19),
        ),
      ],
    );

    final url = await AnimeImageCacheService.instance.bestImageUrlForAnime(
      malId: 1,
      franchiseId: 'mal_franchise_1',
      fallbackImageUrl: 'https://cdn.example/fallback.jpg',
    );

    expect(url, 'https://cdn.example/franchise.jpg');
  });

  test('bestImageUrlForAnime cai para fallbackImageUrl', () async {
    AnimeImageCacheService.instance.debugSetEntriesForTesting();

    final url = await AnimeImageCacheService.instance.bestImageUrlForAnime(
      malId: 999,
      fallbackImageUrl: 'https://cdn.example/fallback.jpg',
    );

    expect(url, 'https://cdn.example/fallback.jpg');
  });

  test('bestBannerUrlForAnime prioriza banner real', () async {
    AnimeImageCacheService.instance.debugSetEntriesForTesting(
      animeImages: [
        _animeImage(
          1,
          imageUrl: 'https://cdn.example/poster.jpg',
          largeImageUrl: 'https://cdn.example/large.jpg',
          bannerImageUrl: 'https://cdn.example/banner.jpg',
        ),
      ],
    );

    final url = await AnimeImageCacheService.instance.bestBannerUrlForAnime(
      malId: 1,
      fallbackImageUrl: 'https://cdn.example/fallback.jpg',
    );

    expect(url, 'https://cdn.example/banner.jpg');
  });

  test('bestBannerUrlForAnime pode evitar fallback para poster', () async {
    AnimeImageCacheService.instance.debugSetEntriesForTesting(
      animeImages: [
        _animeImage(
          1,
          imageUrl: 'https://cdn.example/poster.jpg',
          largeImageUrl: 'https://cdn.example/large.jpg',
        ),
      ],
    );

    final url = await AnimeImageCacheService.instance.bestBannerUrlForAnime(
      malId: 1,
      allowPosterFallback: false,
    );

    expect(url, isNull);
  });

  test(
    'bestBannerUrlForAnime cai para poster grande quando permitido',
    () async {
      AnimeImageCacheService.instance.debugSetEntriesForTesting(
        animeImages: [
          _animeImage(1, largeImageUrl: 'https://cdn.example/large.jpg'),
        ],
      );

      final url = await AnimeImageCacheService.instance.bestBannerUrlForAnime(
        malId: 1,
        fallbackImageUrl: 'https://cdn.example/fallback.jpg',
      );

      expect(url, 'https://cdn.example/large.jpg');
    },
  );

  test('lookup cache permanece limitado em sessoes longas', () async {
    final dbPath = await _buildDatabase();
    await AnimeImageCacheService.instance.debugSetDatabasePathForTesting(
      dbPath,
    );

    for (var malId = 1; malId <= 320; malId++) {
      await AnimeImageCacheService.instance.imageForMalId(malId);
    }

    expect(
      AnimeImageCacheService.instance.debugAnimeImageLookupCount,
      lessThanOrEqualTo(256),
    );
  });

  test('upsert salva metadados sem base64', () async {
    final dbPath = await _buildDatabase();
    await AnimeImageCacheService.instance.debugSetDatabasePathForTesting(
      dbPath,
    );

    await AnimeImageCacheService.instance.upsertAnimeImage(
      _animeImage(50, imageUrl: 'data:image/png;base64,AAAA'),
    );

    final entry = await AnimeImageCacheService.instance.imageForMalId(50);

    expect(entry?.imageUrl, isNull);
  });
}

Future<String> _buildDatabase() async {
  final dir = await Directory.systemTemp.createTemp('anime_image_cache_');
  addTearDown(() async {
    await AnimeImageCacheService.instance.debugResetForTesting();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });
  final input = File('${dir.path}/franchise_availability_map.json');
  final dbPath = '${dir.path}/franchise_availability.db';
  await input.writeAsString(jsonEncode(_payload()));
  final result = await builder.buildFranchiseRuntimeArtifacts(
    builder.FranchiseRuntimeArtifactOptions(
      inputPath: input.path,
      buildSqlite: false,
    ),
  );
  await builder.buildFranchiseSqliteDatabase(result.sourcePayload, dbPath);
  return dbPath;
}

AnimeImageCacheEntry _animeImage(
  int malId, {
  String? imageUrl,
  String? largeImageUrl,
  String? bannerImageUrl,
}) {
  return AnimeImageCacheEntry(
    malId: malId,
    imageUrl: imageUrl,
    largeImageUrl: largeImageUrl,
    bannerImageUrl: bannerImageUrl,
    source: 'jikan',
    cachedAt: DateTime.utc(2026, 5, 19),
    updatedAt: null,
    isFallback: false,
  );
}

Map<String, dynamic> _payload() {
  return {
    'schemaVersion': 1,
    'generatedAt': '2026-05-19T00:00:00Z',
    'franchises': [
      {
        'franchiseId': 'mal_franchise_1',
        'canonicalMalId': 1,
        'displayTitle': 'Test Franchise',
        'coverImage': 'https://cdn.example/franchise.jpg',
        'entries': [
          {
            'malId': 1,
            'anime': {
              'mal_id': 1,
              'title': 'Anime 1',
              'images': {
                'jpg': {
                  'image_url': 'https://cdn.example/anime-1.jpg',
                  'large_image_url': 'https://cdn.example/anime-1-large.jpg',
                },
              },
            },
            'relationType': 'Self',
            'kind': 'tv',
            'group': 'mainline',
            'isAvailable': true,
            'isMainline': true,
            'label': 'Temporada 1',
            'sortIndex': 0,
            'isCanonical': true,
          },
        ],
        'savedAt': '2026-05-19T00:00:00Z',
        'expiresAt': '2026-06-01T00:00:00Z',
        'schemaVersion': 1,
        'isStale': false,
      },
    ],
    'index': [
      {'malId': 1, 'franchiseId': 'mal_franchise_1'},
    ],
    'latestMainlineMalIdByFranchiseId': {'mal_franchise_1': 1},
  };
}
