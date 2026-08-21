#!/usr/bin/env python3
from pathlib import Path

cache_path = Path('lib/services/anime_franchise_cache_service.dart')
text = cache_path.read_text()
old = '''  Future<AnimeFranchise?> getByMalId(
    int malId, {
    bool allowExpired = false,
  }) async {
    if (malId <= 0) return null;
    final db = await database;
    final indexRows = await db.query(
      indexTableName,
      where: 'malId = ?',
      whereArgs: [malId],
      limit: 1,
    );
    if (indexRows.isEmpty) return null;
    final franchiseId = indexRows.first['franchiseId']?.toString();
    if (franchiseId == null || franchiseId.isEmpty) return null;
    return getByFranchiseId(franchiseId, allowExpired: allowExpired);
  }
'''
new = '''  Future<AnimeFranchise?> getByMalId(
    int malId, {
    bool allowExpired = false,
  }) async {
    if (malId <= 0) return null;
    final franchises = await getByMalIds(
      [malId],
      allowExpired: allowExpired,
    );
    return franchises[malId];
  }

  Future<Map<int, AnimeFranchise>> getByMalIds(
    Iterable<int> malIds, {
    bool allowExpired = false,
  }) async {
    final ids = malIds.where((id) => id > 0).toSet().toList(growable: false);
    if (ids.isEmpty) return const <int, AnimeFranchise>{};

    final db = await database;
    final staleCutoff = DateTime.now().toUtc().subtract(expiredRetention);
    final parsedByFranchiseId = <String, AnimeFranchise?>{};
    final franchises = <int, AnimeFranchise>{};
    const batchSize = 400;

    for (var offset = 0; offset < ids.length; offset += batchSize) {
      final end = offset + batchSize < ids.length
          ? offset + batchSize
          : ids.length;
      final chunk = ids.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT i.malId AS indexedMalId, c.* '
        'FROM $indexTableName i '
        'INNER JOIN $cacheTableName c ON c.franchiseId = i.franchiseId '
        'WHERE i.malId IN ($placeholders)',
        chunk,
      );

      for (final row in rows) {
        final malId = _asInt(row['indexedMalId']);
        final franchiseId = row['franchiseId']?.toString();
        if (malId == null || franchiseId == null || franchiseId.isEmpty) {
          continue;
        }

        final franchise = parsedByFranchiseId.putIfAbsent(
          franchiseId,
          () => _franchiseFromRow(row),
        );
        if (franchise == null) continue;
        final isExpired = franchise.isExpired;
        if (!allowExpired && isExpired) continue;
        if (allowExpired &&
            isExpired &&
            !franchise.expiresAt.toUtc().isAfter(staleCutoff)) {
          continue;
        }
        franchises[malId] = franchise.copyWith(isStale: isExpired);
      }
    }
    return franchises;
  }
'''
if text.count(old) != 1:
    raise SystemExit(f'cache target count={text.count(old)}')
cache_path.write_text(text.replace(old, new, 1))

display_path = Path('lib/services/catalog_franchise_display_service.dart')
text = display_path.read_text()
old = '''    final indexedFranchiseByMalId =
        indexedFranchises ?? await loadIndexedFranchisesFor(animes);
    final result = <CatalogDisplayEntry>[];
'''
new = '''    final indexedFranchiseByMalId =
        indexedFranchises ?? await loadIndexedFranchisesFor(animes);
    final missingIndexedMalIds = animes
        .map((anime) => anime.malId)
        .where(
          (malId) => malId > 0 && !indexedFranchiseByMalId.containsKey(malId),
        )
        .toSet();
    final cachedFranchiseByMalId = missingIndexedMalIds.isEmpty
        ? const <int, AnimeFranchise>{}
        : await _cacheService.getByMalIds(missingIndexedMalIds);
    final result = <CatalogDisplayEntry>[];
'''
if text.count(old) != 1:
    raise SystemExit(f'display setup target count={text.count(old)}')
text = text.replace(old, new, 1)
old = '''      final cachedFranchise = indexedFranchise == null && anime.malId > 0
          ? await _cacheService.getByMalId(anime.malId)
          : null;
'''
new = '''      final cachedFranchise = indexedFranchise == null && anime.malId > 0
          ? cachedFranchiseByMalId[anime.malId]
          : null;
'''
if text.count(old) != 1:
    raise SystemExit(f'display lookup target count={text.count(old)}')
display_path.write_text(text.replace(old, new, 1))

test_path = Path('test/services/catalog_franchise_display_service_test.dart')
text = test_path.read_text()
marker = "  test(\n    'collapses cached seasons by franchise id without title matching',\n"
addition = '''  test('batch cache lookup maps every indexed MAL id in one result', () async {
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

'''
if text.count(marker) != 1:
    raise SystemExit(f'test marker count={text.count(marker)}')
test_path.write_text(text.replace(marker, addition + marker, 1))
