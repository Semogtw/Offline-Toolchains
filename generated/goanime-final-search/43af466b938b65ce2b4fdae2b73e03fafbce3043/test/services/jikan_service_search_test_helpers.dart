part of 'jikan_service_search_test.dart';

Map<String, Object?> _animeJson(
  int malId,
  String title, {
  String? status,
  String? season,
  int? year,
  String? airedFrom,
  List<Map<String, Object?>> genres = const [],
}) {
  return {
    'mal_id': malId,
    'title': title,
    'title_english': null,
    'title_japanese': null,
    'title_synonyms': const [],
    'images': {
      'jpg': {'image_url': ''},
    },
    'status': status,
    'season': season,
    'year': year,
    'aired': {'from': airedFrom},
    'genres': genres,
  };
}

class _FakeAnimeMetadataCacheService extends AnimeMetadataCacheService {
  _FakeAnimeMetadataCacheService({
    this.searchResults = const [],
    this.catalogResults = const [],
    this.throwOnSearch = false,
  });

  final List<AnimeMetadataCacheEntry> searchResults;
  final List<AnimeMetadataCacheEntry> catalogResults;
  final bool throwOnSearch;
  final List<AnimeMetadataCacheEntry> savedEntries = [];
  int searchCalls = 0;

  @override
  Future<List<AnimeMetadataCacheEntry>> search(
    String query, {
    int limit = 30,
  }) async {
    searchCalls += 1;
    if (throwOnSearch) throw StateError('metadata cache failed');
    return searchResults.take(limit).toList();
  }

  @override
  Future<List<AnimeMetadataCacheEntry>> catalogCandidates({
    int limit = 120,
    bool allowExpired = true,
  }) async {
    return catalogResults.take(limit).toList();
  }

  @override
  Future<void> upsertEntries(
    List<AnimeMetadataCacheEntry> entries, {
    String? seedSource,
  }) async {
    savedEntries.addAll(entries);
  }
}
