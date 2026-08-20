from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one target, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True)
    args = parser.parse_args()
    root = Path(args.root)

    service = root / 'lib/services/anime_metadata_seed_service.dart'
    replace_once(
        service,
        "typedef AnimeMetadataBundledSeedLoader = Future<String> Function();\n",
        "typedef AnimeMetadataBundledSeedLoader = Future<String> Function();\n"
        "typedef AnimeMetadataBundledSeedDigestLoader = Future<String> Function();\n",
    )
    replace_once(
        service,
        "    AnimeMetadataBundledSeedLoader? bundledSeedLoader,\n    AnimeMetadataSeedWriter? seedWriter,\n",
        "    AnimeMetadataBundledSeedLoader? bundledSeedLoader,\n"
        "    AnimeMetadataBundledSeedDigestLoader? bundledSeedDigestLoader,\n"
        "    AnimeMetadataSeedWriter? seedWriter,\n",
    )
    replace_once(
        service,
        "       _bundledSeedLoader =\n           bundledSeedLoader ??\n           (() => rootBundle.loadString(bundledSeedAssetPath)),\n       _seedWriter = seedWriter;\n",
        "       _bundledSeedLoader =\n           bundledSeedLoader ??\n           (() => rootBundle.loadString(bundledSeedAssetPath)),\n"
        "       _bundledSeedDigestLoader =\n"
        "           bundledSeedDigestLoader ??\n"
        "           (() => rootBundle.loadString(bundledSeedDigestAssetPath)),\n"
        "       _seedWriter = seedWriter;\n",
    )
    replace_once(
        service,
        "  static const String bundledSeedAssetPath =\n      'assets/data/anime_metadata_seed.json';\n",
        "  static const String bundledSeedAssetPath =\n"
        "      'assets/data/anime_metadata_seed.json';\n"
        "  static const String bundledSeedDigestAssetPath =\n"
        "      'assets/data/anime_metadata_seed.json.sha256';\n",
    )
    replace_once(
        service,
        "  static const String _bundledSeedGenerationKey =\n      'anime_metadata_seed.bundled_generation';\n",
        "  static const String _bundledSeedGenerationKey =\n"
        "      'anime_metadata_seed.bundled_generation';\n"
        "  static const String _bundledSeedDigestKey =\n"
        "      'anime_metadata_seed.bundled_digest';\n"
        "  static const String _bundledSeedSentinelKey =\n"
        "      'anime_metadata_seed.bundled_sentinel';\n",
    )
    replace_once(
        service,
        "  final AnimeMetadataBundledSeedLoader _bundledSeedLoader;\n  final AnimeMetadataSeedWriter? _seedWriter;\n",
        "  final AnimeMetadataBundledSeedLoader _bundledSeedLoader;\n"
        "  final AnimeMetadataBundledSeedDigestLoader _bundledSeedDigestLoader;\n"
        "  final AnimeMetadataSeedWriter? _seedWriter;\n",
    )

    old_import = '''  Future<bool> _importBundledSeed(DateTime currentTime) async {
    try {
      final payload = AnimeMetadataSeedPayload.fromJson(
        jsonDecode(await _bundledSeedLoader()),
      );
      if (!payload.isCompatible ||
          payload.entries.isEmpty ||
          payload.generatedAt.toUtc().isAfter(
            currentTime.add(_maxFutureSkew),
          ) ||
          !_hasUniqueCacheKeys(payload.entries) ||
          !_entriesMatchPublicationTime(
            payload.entries,
            payload.generatedAt.toUtc(),
          )) {
        return false;
      }

      final preferences = _preferences ?? await SharedPreferences.getInstance();
      final generation = payload.generatedAt.toUtc().toIso8601String();
      if (_seedWriter == null &&
          preferences.getString(_bundledSeedGenerationKey) == generation) {
        final sentinel = await _cacheService.getByCacheKey(
          payload.entries.first.cacheKey,
          allowExpired: true,
        );
        if (sentinel != null) return false;
      }

      await _writeEntries(payload.entries, 'bundled-seed');
      await preferences.setString(_bundledSeedGenerationKey, generation);
      return true;
    } catch (error) {
      await AppLogService.warning(
        'anime-metadata-seed',
        'Bundled seed import failed: $error',
      );
      return false;
    }
  }
'''
    new_import = '''  Future<bool> _importBundledSeed(DateTime currentTime) async {
    try {
      final preferences = _preferences ?? await SharedPreferences.getInstance();
      final bundledDigest = await _readBundledSeedDigest();
      if (_seedWriter == null &&
          bundledDigest != null &&
          preferences.getString(_bundledSeedDigestKey) == bundledDigest) {
        final sentinelKey = preferences.getString(_bundledSeedSentinelKey);
        if (sentinelKey != null && sentinelKey.isNotEmpty) {
          final sentinel = await _cacheService.getByCacheKey(
            sentinelKey,
            allowExpired: true,
          );
          if (sentinel != null) return false;
        }
      }

      final payload = AnimeMetadataSeedPayload.fromJson(
        jsonDecode(await _bundledSeedLoader()),
      );
      if (!payload.isCompatible ||
          payload.entries.isEmpty ||
          payload.generatedAt.toUtc().isAfter(
            currentTime.add(_maxFutureSkew),
          ) ||
          !_hasUniqueCacheKeys(payload.entries) ||
          !_entriesMatchPublicationTime(
            payload.entries,
            payload.generatedAt.toUtc(),
          )) {
        return false;
      }

      final generation = payload.generatedAt.toUtc().toIso8601String();
      if (_seedWriter == null &&
          preferences.getString(_bundledSeedGenerationKey) == generation) {
        final sentinelKey = payload.entries.first.cacheKey;
        final sentinel = await _cacheService.getByCacheKey(
          sentinelKey,
          allowExpired: true,
        );
        if (sentinel != null) {
          if (bundledDigest != null) {
            await preferences.setString(_bundledSeedDigestKey, bundledDigest);
          }
          await preferences.setString(_bundledSeedSentinelKey, sentinelKey);
          return false;
        }
      }

      await _writeEntries(payload.entries, 'bundled-seed');
      await preferences.setString(_bundledSeedGenerationKey, generation);
      if (bundledDigest != null) {
        await preferences.setString(_bundledSeedDigestKey, bundledDigest);
      }
      await preferences.setString(
        _bundledSeedSentinelKey,
        payload.entries.first.cacheKey,
      );
      return true;
    } catch (error) {
      await AppLogService.warning(
        'anime-metadata-seed',
        'Bundled seed import failed: $error',
      );
      return false;
    }
  }

  Future<String?> _readBundledSeedDigest() async {
    try {
      final digest = (await _bundledSeedDigestLoader()).trim().toLowerCase();
      return _sha256Pattern.hasMatch(digest) ? digest : null;
    } catch (_) {
      return null;
    }
  }
'''
    replace_once(service, old_import, new_import)

    builder = root / 'tools/build_anime_metadata_seed.dart'
    replace_once(
        builder,
        "  final payloadBytes = utf8.encode(payloadJson);\n  final gzipBytes = gzip.encode(payloadBytes);\n  final digest = sha256.convert(gzipBytes).toString();\n",
        "  final payloadBytes = utf8.encode(payloadJson);\n"
        "  final bundledDigest = sha256.convert(payloadBytes).toString();\n"
        "  final gzipBytes = gzip.encode(payloadBytes);\n"
        "  final digest = sha256.convert(gzipBytes).toString();\n",
    )
    replace_once(
        builder,
        "  final jsonFile = File('$_outputDir/anime_metadata_seed.json');\n  final gzipFile = File('$_outputDir/anime_metadata_seed.json.gz');\n",
        "  final jsonFile = File('$_outputDir/anime_metadata_seed.json');\n"
        "  final bundledShaFile = File(\n"
        "    '$_outputDir/anime_metadata_seed.json.sha256',\n"
        "  );\n"
        "  final gzipFile = File('$_outputDir/anime_metadata_seed.json.gz');\n",
    )
    replace_once(
        builder,
        "  await jsonFile.writeAsString(payloadJson);\n  await gzipFile.writeAsBytes(gzipBytes);\n",
        "  await jsonFile.writeAsString(payloadJson);\n"
        "  await bundledShaFile.writeAsString('$bundledDigest\\n');\n"
        "  await gzipFile.writeAsBytes(gzipBytes);\n",
    )

    workflow = root / '.github/workflows/anime_metadata_cache.yml'
    replace_once(
        workflow,
        "          test -f anime_metadata_seed.json\n          test -f anime_metadata_seed.json.gz\n",
        "          test -f anime_metadata_seed.json\n"
        "          test -f anime_metadata_seed.json.sha256\n"
        "          test -f anime_metadata_seed.json.gz\n",
    )
    replace_once(
        workflow,
        "          gzip -t anime_metadata_seed.json.gz\n          sha256sum -c anime_metadata_seed.sha256\n",
        "          gzip -t anime_metadata_seed.json.gz\n"
        "          printf '%s  %s\\n' \"$(cat anime_metadata_seed.json.sha256)\" anime_metadata_seed.json | sha256sum -c -\n"
        "          sha256sum -c anime_metadata_seed.sha256\n",
    )
    replace_once(
        workflow,
        "          cp dist/anime_metadata_cache/anime_metadata_seed.json \\\n            assets/data/anime_metadata_seed.json\n          cp dist/anime_metadata_cache/broadcast_schedule.json \\\n",
        "          cp dist/anime_metadata_cache/anime_metadata_seed.json \\\n"
        "            assets/data/anime_metadata_seed.json\n"
        "          cp dist/anime_metadata_cache/anime_metadata_seed.json.sha256 \\\n"
        "            assets/data/anime_metadata_seed.json.sha256\n"
        "          cp dist/anime_metadata_cache/broadcast_schedule.json \\\n",
    )
    replace_once(
        workflow,
        "          git add assets/data/anime_metadata_seed.json \\\n            assets/data/broadcast_schedule.json\n",
        "          git add assets/data/anime_metadata_seed.json \\\n"
        "            assets/data/anime_metadata_seed.json.sha256 \\\n"
        "            assets/data/broadcast_schedule.json\n",
    )

    pubspec = root / 'pubspec.yaml'
    replace_once(
        pubspec,
        "    - assets/data/anime_metadata_seed.json\n",
        "    - assets/data/anime_metadata_seed.json\n"
        "    - assets/data/anime_metadata_seed.json.sha256\n",
    )

    test = root / 'test/services/anime_metadata_seed_reimport_test.dart'
    replace_once(
        test,
        "    final cache = AnimeMetadataCacheService();\n    final service = AnimeMetadataSeedService(\n",
        "    final cache = AnimeMetadataCacheService();\n"
        "    var bundledSeedLoads = 0;\n"
        "    const bundledDigest =\n"
        "        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';\n"
        "    final service = AnimeMetadataSeedService(\n",
    )
    replace_once(
        test,
        "      bundledSeedLoader: () async => jsonEncode(payload.toJson()),\n    );\n",
        "      bundledSeedLoader: () async {\n"
        "        bundledSeedLoads += 1;\n"
        "        return jsonEncode(payload.toJson());\n"
        "      },\n"
        "      bundledSeedDigestLoader: () async => bundledDigest,\n"
        "    );\n",
    )
    replace_once(
        test,
        "    expect(second, AnimeMetadataSeedImportResult.disabled);\n    expect(await cache.count(), 1);\n\n    await cache.clearAll();\n",
        "    expect(second, AnimeMetadataSeedImportResult.disabled);\n"
        "    expect(bundledSeedLoads, 1);\n"
        "    expect(await cache.count(), 1);\n\n"
        "    await cache.clearAll();\n",
    )
    replace_once(
        test,
        "    expect(repaired, AnimeMetadataSeedImportResult.imported);\n    expect(await cache.count(), 1);\n",
        "    expect(repaired, AnimeMetadataSeedImportResult.imported);\n"
        "    expect(bundledSeedLoads, 2);\n"
        "    expect(await cache.count(), 1);\n",
    )


if __name__ == '__main__':
    main()
