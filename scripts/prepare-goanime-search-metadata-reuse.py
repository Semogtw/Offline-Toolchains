#!/usr/bin/env python3
from pathlib import Path

path = Path('lib/services/jikan_service.dart')
text = path.read_text()

old = '''    final metadataResults = await _searchMetadataCache(
      query,
      limit: limit,
      availabilityMode: availabilityMode,
    );
    if (metadataResults.isNotEmpty) {
      final metadataByKey = <String, JikanAnime>{};
'''
new = '''    final metadataResults = await _searchMetadataCache(
      query,
      limit: limit,
      availabilityMode: availabilityMode,
    );
    if (metadataResults.isNotEmpty) {
      _saveToCache(
        _metadataSearchCacheKey(query, limit, availabilityMode),
        metadataResults,
      );
      unawaited(
        _refreshMetadataCacheFromOnlineSearch(
          query,
          limit: limit,
          availabilityMode: availabilityMode,
        ),
      );
      final metadataByKey = <String, JikanAnime>{};
'''
if text.count(old) != 1:
    raise SystemExit(f'searchCached target count={text.count(old)}')
text = text.replace(old, new, 1)

old = '''    final cacheKey = [
      'metadata',
      normalizedQuery.toLowerCase(),
      limit,
      availabilityMode.name,
    ].join('_');

    return _loadCachedList(cacheKey, () async {
'''
new = '''    final cacheKey = _metadataSearchCacheKey(
      normalizedQuery,
      limit,
      availabilityMode,
    );

    return _loadCachedList(cacheKey, () async {
'''
if text.count(old) != 1:
    raise SystemExit(f'metadata key target count={text.count(old)}')
text = text.replace(old, new, 1)

marker = '''  Future<List<JikanAnime>> _searchMetadataCache(
    String query, {
'''
addition = '''  String _metadataSearchCacheKey(
    String query,
    int limit,
    AnimeAvailabilityMode availabilityMode,
  ) {
    return [
      'metadata',
      query.trim().toLowerCase(),
      limit,
      availabilityMode.name,
    ].join('_');
  }

'''
if text.count(marker) != 1:
    raise SystemExit(f'helper marker count={text.count(marker)}')
path.write_text(text.replace(marker, addition + marker, 1))

helper = Path('test/services/jikan_service_search_test_helpers.dart')
text = helper.read_text()
old = '''  final bool throwOnSearch;
  final List<AnimeMetadataCacheEntry> savedEntries = [];

  @override
'''
new = '''  final bool throwOnSearch;
  final List<AnimeMetadataCacheEntry> savedEntries = [];
  int searchCalls = 0;

  @override
'''
if text.count(old) != 1:
    raise SystemExit(f'fake fields target count={text.count(old)}')
text = text.replace(old, new, 1)
old = '''  }) async {
    if (throwOnSearch) throw StateError('metadata cache failed');
    return searchResults.take(limit).toList();
  }
'''
new = '''  }) async {
    searchCalls += 1;
    if (throwOnSearch) throw StateError('metadata cache failed');
    return searchResults.take(limit).toList();
  }
'''
if text.count(old) != 1:
    raise SystemExit(f'fake search target count={text.count(old)}')
helper.write_text(text.replace(old, new, 1))

cases = Path('test/services/jikan_service_search_test_cases_1.dart')
text = cases.read_text()
marker = "  test('getAnimeExtrasById parses studios and themes', () async {\n"
addition = '''  test('local search reuses metadata cache for immediate enrichment', () async {
    AvailabilityService.debugSetAvailableTitles(['cowboy bebop']);
    final metadataCache = _FakeAnimeMetadataCacheService(
      searchResults: [
        AnimeMetadataCacheEntry(
          malId: 1,
          title: 'Cowboy Bebop',
          imageUrl: 'https://cdn.example/cowboy.webp',
          updatedAt: DateTime.utc(2026, 5, 15),
        ),
      ],
    );
    JikanService.debugSetAnimeMetadataCacheService(metadataCache);
    JikanService.httpClient = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'pagination': {'has_next_page': false},
          'data': <Object>[],
        }),
        200,
      ),
    );

    final service = JikanService();
    final local = await service.searchCachedAnimes('cowboy', limit: 20);
    final enriched = await service.searchAnimeMetadata('cowboy', limit: 20);

    expect(local.single.title, 'Cowboy Bebop');
    expect(enriched.single.title, 'Cowboy Bebop');
    expect(metadataCache.searchCalls, 1);
  });

'''
if text.count(marker) != 1:
    raise SystemExit(f'test marker count={text.count(marker)}')
cases.write_text(text.replace(marker, addition + marker, 1))
