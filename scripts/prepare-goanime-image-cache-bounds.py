#!/usr/bin/env python3
from pathlib import Path
import argparse


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    newline = '\r\n' if '\r\n' in text else '\n'
    old = old.replace('\n', newline)
    new = new.replace('\n', newline)
    if text.count(old) != 1:
        raise SystemExit(f'{path}: expected exactly one target')
    path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root
    service = root / 'lib/services/anime_image_cache_service.dart'
    test = root / 'test/services/anime_image_cache_service_test.dart'

    replace_once(
        service,
        "  static const String _databasePrefix = 'franchise_availability_asset';\n",
        "  static const String _databasePrefix = 'franchise_availability_asset';\n"
        "  static const int _lookupCacheMaxEntries = 256;\n",
    )
    replace_once(
        service,
        "    return _animeImageLookups.putIfAbsent(\n"
        "      malId,\n"
        "      () => _loadImageForMalId(malId),\n"
        "    );",
        "    return _boundedLookup(\n"
        "      _animeImageLookups,\n"
        "      malId,\n"
        "      () => _loadImageForMalId(malId),\n"
        "    );",
    )
    replace_once(
        service,
        "    return _franchiseImageLookups.putIfAbsent(\n"
        "      franchiseId,\n"
        "      () => _loadImageForFranchiseId(franchiseId),\n"
        "    );",
        "    return _boundedLookup(\n"
        "      _franchiseImageLookups,\n"
        "      franchiseId,\n"
        "      () => _loadImageForFranchiseId(franchiseId),\n"
        "    );",
    )
    replace_once(
        service,
        "      return _bestImageLookups.putIfAbsent(\n"
        "        key,\n"
        "        () => _resolveBestImageUrlForAnime(\n",
        "      return _boundedLookup(\n"
        "        _bestImageLookups,\n"
        "        key,\n"
        "        () => _resolveBestImageUrlForAnime(\n",
    )
    replace_once(
        service,
        "      return _bestImageLookups.putIfAbsent(\n"
        "        key,\n"
        "        () => _resolveBestBannerUrlForAnime(\n",
        "      return _boundedLookup(\n"
        "        _bestImageLookups,\n"
        "        key,\n"
        "        () => _resolveBestBannerUrlForAnime(\n",
    )
    replace_once(
        service,
        "  @visibleForTesting\n"
        "  Future<void> debugSetDatabasePathForTesting(String path) async {",
        "  Future<T> _boundedLookup<K, T>(\n"
        "    Map<K, Future<T>> cache,\n"
        "    K key,\n"
        "    Future<T> Function() loader,\n"
        "  ) {\n"
        "    final cached = cache.remove(key);\n"
        "    if (cached != null) {\n"
        "      cache[key] = cached;\n"
        "      return cached;\n"
        "    }\n"
        "\n"
        "    final future = loader();\n"
        "    cache[key] = future;\n"
        "    while (cache.length > _lookupCacheMaxEntries) {\n"
        "      cache.remove(cache.keys.first);\n"
        "    }\n"
        "    return future;\n"
        "  }\n"
        "\n"
        "  @visibleForTesting\n"
        "  int get debugAnimeImageLookupCount => _animeImageLookups.length;\n"
        "\n"
        "  @visibleForTesting\n"
        "  int get debugFranchiseImageLookupCount => _franchiseImageLookups.length;\n"
        "\n"
        "  @visibleForTesting\n"
        "  int get debugBestImageLookupCount => _bestImageLookups.length;\n"
        "\n"
        "  @visibleForTesting\n"
        "  Future<void> debugSetDatabasePathForTesting(String path) async {",
    )
    replace_once(
        test,
        "  test('upsert salva metadados sem base64', () async {",
        "  test('lookup cache permanece limitado em sessoes longas', () async {\n"
        "    final dbPath = await _buildDatabase();\n"
        "    await AnimeImageCacheService.instance.debugSetDatabasePathForTesting(\n"
        "      dbPath,\n"
        "    );\n"
        "\n"
        "    for (var malId = 1; malId <= 320; malId++) {\n"
        "      await AnimeImageCacheService.instance.imageForMalId(malId);\n"
        "    }\n"
        "\n"
        "    expect(\n"
        "      AnimeImageCacheService.instance.debugAnimeImageLookupCount,\n"
        "      lessThanOrEqualTo(256),\n"
        "    );\n"
        "  });\n"
        "\n"
        "  test('upsert salva metadados sem base64', () async {",
    )


if __name__ == '__main__':
    main()
