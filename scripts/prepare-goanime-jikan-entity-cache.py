#!/usr/bin/env python3
from pathlib import Path
import argparse


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise SystemExit(f'{path}: expected exactly one target, found {text.count(old)}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root
    service = root / 'lib/services/jikan_service.dart'

    replace_once(
        service,
        """  static final Map<int, _CacheEntry<JikanAnime>> _animeByIdCache = {};
  static final Map<int, _CacheEntry<List<JikanAnimeRelation>>>
  _animeRelationsCache = {};
  static DateTime? _nowOverride;
""",
        """  static final Map<int, _CacheEntry<JikanAnime>> _animeByIdCache = {};
  static final Map<int, _CacheEntry<List<JikanAnimeRelation>>>
  _animeRelationsCache = {};
  static final Map<int, Future<JikanAnime?>> _animeByIdInFlight = {};
  static final Map<int, Future<List<JikanAnimeRelation>>>
  _animeRelationsInFlight = {};
  static int get _maxEntityCacheSize => _isDesktop ? 500 : 160;
  static DateTime? _nowOverride;
""",
    )

    replace_once(
        service,
        """  /// Obtém do cache se disponível e não expirado
  List<JikanAnime>? _getFromCache(String key) {
""",
        """  static T? _getEntityFromCache<T>(
    Map<int, _CacheEntry<T>> cache,
    int key,
  ) {
    final entry = cache.remove(key);
    if (entry == null) return null;
    if (entry.isExpired) return null;
    cache[key] = entry;
    return entry.data;
  }

  static void _saveEntityToCache<T>(
    Map<int, _CacheEntry<T>> cache,
    int key,
    T data,
  ) {
    cache.removeWhere((_, entry) => entry.isExpired);
    cache.remove(key);
    cache[key] = _CacheEntry(data);
    while (cache.length > _maxEntityCacheSize) {
      cache.remove(cache.keys.first);
    }
  }

  /// Obtém do cache se disponível e não expirado
  List<JikanAnime>? _getFromCache(String key) {
""",
    )

    old_anime = """  /// Busca anime por ID
  Future<JikanAnime?> getAnimeById(int malId) async {
    if (malId <= 0) return null;
    final cached = _animeByIdCache[malId];
    if (cached != null && !cached.isExpired) return cached.data;

    try {
      await _waitForRateLimit();
      final response = await _client
          .get(
            Uri.parse('$baseUrl/anime/$malId'),
            headers: NetworkHeaders.identityEncoding,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final jsonData = jsonMap(json.decode(response.body)) ?? const {};
        final animeData = jsonMap(jsonData['data']);
        if (animeData == null) return null;
        final anime = JikanAnime.fromJson(animeData);
        _animeByIdCache[malId] = _CacheEntry(anime);
        return anime;
      } else {
        throw Exception('Failed to load anime: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching anime by id: $e');
      return null;
    }
  }
"""
    new_anime = """  /// Busca anime por ID
  Future<JikanAnime?> getAnimeById(int malId) {
    if (malId <= 0) return Future.value();
    final cached = _getEntityFromCache(_animeByIdCache, malId);
    if (cached != null) return Future.value(cached);

    final existing = _animeByIdInFlight[malId];
    if (existing != null) return existing;

    late final Future<JikanAnime?> load;
    load = _fetchAnimeById(malId).whenComplete(() {
      if (identical(_animeByIdInFlight[malId], load)) {
        _animeByIdInFlight.remove(malId);
      }
    });
    _animeByIdInFlight[malId] = load;
    return load;
  }

  Future<JikanAnime?> _fetchAnimeById(int malId) async {
    try {
      await _waitForRateLimit();
      final response = await _client
          .get(
            Uri.parse('$baseUrl/anime/$malId'),
            headers: NetworkHeaders.identityEncoding,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final jsonData = jsonMap(json.decode(response.body)) ?? const {};
        final animeData = jsonMap(jsonData['data']);
        if (animeData == null) return null;
        final anime = JikanAnime.fromJson(animeData);
        _saveEntityToCache(_animeByIdCache, malId, anime);
        return anime;
      }
      throw Exception('Failed to load anime: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching anime by id: $e');
      return null;
    }
  }
"""
    replace_once(service, old_anime, new_anime)

    old_rel = """  Future<List<JikanAnimeRelation>> getAnimeRelations(int malId) async {
    if (malId <= 0) return const [];
    final cached = _animeRelationsCache[malId];
    if (cached != null && !cached.isExpired) return cached.data;

    try {
      await _waitForRateLimit();
      final response = await _client
          .get(
            Uri.parse('$baseUrl/anime/$malId/relations'),
            headers: NetworkHeaders.identityEncoding,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final jsonData = jsonMap(json.decode(response.body)) ?? const {};
        final data = jsonList(jsonData['data']);
        final relations = data
            .whereType<Map<String, dynamic>>()
            .map(JikanAnimeRelation.fromJson)
            .where((relation) => relation.entries.isNotEmpty)
            .toList();
        _animeRelationsCache[malId] = _CacheEntry(relations);
        return relations;
      }
      throw Exception('Failed to load anime relations: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching anime relations: $e');
      return const [];
    }
  }
"""
    new_rel = """  Future<List<JikanAnimeRelation>> getAnimeRelations(int malId) {
    if (malId <= 0) return Future.value(const []);
    final cached = _getEntityFromCache(_animeRelationsCache, malId);
    if (cached != null) return Future.value(cached);

    final existing = _animeRelationsInFlight[malId];
    if (existing != null) return existing;

    late final Future<List<JikanAnimeRelation>> load;
    load = _fetchAnimeRelations(malId).whenComplete(() {
      if (identical(_animeRelationsInFlight[malId], load)) {
        _animeRelationsInFlight.remove(malId);
      }
    });
    _animeRelationsInFlight[malId] = load;
    return load;
  }

  Future<List<JikanAnimeRelation>> _fetchAnimeRelations(int malId) async {
    try {
      await _waitForRateLimit();
      final response = await _client
          .get(
            Uri.parse('$baseUrl/anime/$malId/relations'),
            headers: NetworkHeaders.identityEncoding,
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final jsonData = jsonMap(json.decode(response.body)) ?? const {};
        final data = jsonList(jsonData['data']);
        final relations = data
            .whereType<Map<String, dynamic>>()
            .map(JikanAnimeRelation.fromJson)
            .where((relation) => relation.entries.isNotEmpty)
            .toList();
        _saveEntityToCache(_animeRelationsCache, malId, relations);
        return relations;
      }
      throw Exception('Failed to load anime relations: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching anime relations: $e');
      return const [];
    }
  }
"""
    replace_once(service, old_rel, new_rel)

    replace_once(
        service,
        """    _animeByIdCache.clear();
    _animeRelationsCache.clear();
    _inFlightListLoads.clear();
""",
        """    _animeByIdCache.clear();
    _animeRelationsCache.clear();
    _animeByIdInFlight.clear();
    _animeRelationsInFlight.clear();
    _inFlightListLoads.clear();
""",
    )

    replace_once(
        service,
        """  @visibleForTesting
  static void debugSetNowForTesting(DateTime? now) {
""",
        """  @visibleForTesting
  static int get debugEntityCacheMaxSize => _maxEntityCacheSize;

  @visibleForTesting
  static int get debugAnimeByIdCacheSize => _animeByIdCache.length;

  @visibleForTesting
  static int get debugAnimeRelationsCacheSize => _animeRelationsCache.length;

  @visibleForTesting
  static void debugPrimeEntityCachesForTesting(Iterable<JikanAnime> animes) {
    for (final anime in animes) {
      _saveEntityToCache(_animeByIdCache, anime.malId, anime);
      _saveEntityToCache(
        _animeRelationsCache,
        anime.malId,
        const <JikanAnimeRelation>[],
      );
    }
  }

  @visibleForTesting
  static void debugSetNowForTesting(DateTime? now) {
""",
    )

    test = root / 'test/services/jikan_entity_cache_test.dart'
    test.write_text("""import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/jikan_models.dart';
import 'package:goanime/services/jikan_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    JikanService.httpClient = null;
    JikanService.debugResetCache();
  });

  test('deduplicates concurrent anime-by-id requests', () async {
    JikanService.debugResetCache();
    final release = Completer<void>();
    var requests = 0;
    JikanService.httpClient = MockClient((request) async {
      requests += 1;
      await release.future;
      return http.Response(
        jsonEncode({
          'data': {
            'mal_id': 123,
            'title': 'Fixture Anime',
            'images': {
              'jpg': {'image_url': 'https://example.test/123.jpg'},
            },
          },
        }),
        200,
      );
    });
    final service = JikanService(propagateErrors: true);

    final first = service.getAnimeById(123);
    final second = service.getAnimeById(123);
    await Future<void>.delayed(Duration.zero);
    release.complete();

    final results = await Future.wait([first, second]);
    expect(requests, 1);
    expect(results[0]?.malId, 123);
    expect(results[1]?.malId, 123);
  });

  test('deduplicates concurrent anime-relations requests', () async {
    JikanService.debugResetCache();
    final release = Completer<void>();
    var requests = 0;
    JikanService.httpClient = MockClient((request) async {
      requests += 1;
      await release.future;
      return http.Response(jsonEncode({'data': <Object>[]}), 200);
    });
    final service = JikanService(propagateErrors: true);

    final first = service.getAnimeRelations(321);
    final second = service.getAnimeRelations(321);
    await Future<void>.delayed(Duration.zero);
    release.complete();

    final results = await Future.wait([first, second]);
    expect(requests, 1);
    expect(results[0], isEmpty);
    expect(results[1], isEmpty);
  });

  test('entity caches remain bounded during long sessions', () {
    JikanService.debugResetCache();
    final maxSize = JikanService.debugEntityCacheMaxSize;
    JikanService.debugPrimeEntityCachesForTesting([
      for (var id = 1; id <= maxSize + 50; id++)
        JikanAnime(malId: id, title: 'Anime $id', imageUrl: ''),
    ]);

    expect(JikanService.debugAnimeByIdCacheSize, maxSize);
    expect(JikanService.debugAnimeRelationsCacheSize, maxSize);
  });
}
""", encoding='utf-8')


if __name__ == '__main__':
    main()
