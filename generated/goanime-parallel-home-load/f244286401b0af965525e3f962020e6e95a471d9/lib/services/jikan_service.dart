import 'package:goanime_core/goanime_core.dart';
// ignore_for_file: inference_failure_on_instance_creation, unawaited_futures
// Existing callbacks/fixtures still rely on implicit async or dynamic JSON shapes; keep new strict rules enabled elsewhere.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime_metadata_cache_models.dart';
import '../models/jikan_models.dart';
import '../models/season_catalog_filter.dart';
import '../utils/anime_deduplication.dart';

import '../utils/network_headers.dart';
import 'anime_metadata_cache_service.dart';
import 'availability_service.dart';
import 'new_release_scanner.dart';

/// Cache entry com timestamp para expiração
class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;

  _CacheEntry(this.data) : timestamp = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(timestamp) > JikanService._listCacheTtl;
}

/// Resultado do carregamento da Home com todos os dados
class HomeData {
  final List<JikanAnime> seasonAnimes;
  final List<JikanAnime> todaysReleases;
  final List<JikanAnime> topAnimes;
  final List<JikanAnime> actionAnimes;
  final List<JikanAnime> romanceAnimes;
  final List<JikanAnime> comedyAnimes;
  final List<JikanAnime> fantasyAnimes;
  final DateTime loadedAt;

  HomeData({
    required this.seasonAnimes,
    required this.todaysReleases,
    required this.topAnimes,
    required this.actionAnimes,
    required this.romanceAnimes,
    required this.comedyAnimes,
    required this.fantasyAnimes,
    DateTime? loadedAt,
  }) : loadedAt = loadedAt ?? DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(loadedAt) > JikanService._homeDataTtl;

  /// Serializa para JSON para persistência
  Map<String, dynamic> toJson() => {
    'seasonAnimes': seasonAnimes.map((a) => a.toJson()).toList(),
    'todaysReleases': todaysReleases.map((a) => a.toJson()).toList(),
    'topAnimes': topAnimes.map((a) => a.toJson()).toList(),
    'actionAnimes': actionAnimes.map((a) => a.toJson()).toList(),
    'romanceAnimes': romanceAnimes.map((a) => a.toJson()).toList(),
    'comedyAnimes': comedyAnimes.map((a) => a.toJson()).toList(),
    'fantasyAnimes': fantasyAnimes.map((a) => a.toJson()).toList(),
    'loadedAt': loadedAt.toIso8601String(),
  };

  /// Deserializa do JSON
  factory HomeData.fromJson(Map<String, dynamic> json) {
    return HomeData(
      seasonAnimes: jsonList(
        json['seasonAnimes'],
      ).map(jsonMap).nonNulls.map(JikanAnime.fromJson).toList(),
      todaysReleases: jsonList(
        json['todaysReleases'] ?? [],
      ).map(jsonMap).nonNulls.map(JikanAnime.fromJson).toList(),
      topAnimes: jsonList(
        json['topAnimes'],
      ).map(jsonMap).nonNulls.map(JikanAnime.fromJson).toList(),
      actionAnimes: jsonList(
        json['actionAnimes'],
      ).map(jsonMap).nonNulls.map(JikanAnime.fromJson).toList(),
      romanceAnimes: jsonList(
        json['romanceAnimes'],
      ).map(jsonMap).nonNulls.map(JikanAnime.fromJson).toList(),
      comedyAnimes: jsonList(
        json['comedyAnimes'],
      ).map(jsonMap).nonNulls.map(JikanAnime.fromJson).toList(),
      fantasyAnimes: jsonList(
        json['fantasyAnimes'],
      ).map(jsonMap).nonNulls.map(JikanAnime.fromJson).toList(),
      loadedAt:
          DateTime.tryParse(jsonString(json['loadedAt']) ?? '') ??
          DateTime.now(),
    );
  }
}

class JikanBrowsePage {
  final List<JikanAnime> animes;
  final int nextPage;
  final bool hasMore;

  const JikanBrowsePage({
    required this.animes,
    required this.nextPage,
    required this.hasMore,
  });
}

class JikanService {
  JikanService({this.propagateErrors = false});

  final bool propagateErrors;

  static const String baseUrl = 'https://api.jikan.moe/v4';
  static const String _homeDataCacheKey = 'jikan_home_data_cache';

  // Cache em memória singleton para toda a app
  static HomeData? _homeDataCache;
  static Future<HomeData>? _homeDataLoadFuture;
  static final Map<String, _CacheEntry<List<JikanAnime>>> _cache = {};
  static final Map<String, Future<List<JikanAnime>>> _inFlightListLoads = {};
  static bool get _isDesktop => Platform.isWindows || Platform.isLinux;
  static int get _maxCacheSize => _isDesktop ? 150 : 50;
  static Duration get _listCacheTtl =>
      _isDesktop ? const Duration(hours: 2) : const Duration(minutes: 30);
  static Duration get _homeDataTtl =>
      _isDesktop ? const Duration(hours: 1) : const Duration(minutes: 30);
  static http.Client? httpClient;
  static AnimeMetadataCacheService _metadataCacheService =
      AnimeMetadataCacheService();
  static final Map<int, _CacheEntry<JikanAnime>> _animeByIdCache = {};
  static final Map<int, _CacheEntry<List<JikanAnimeRelation>>>
  _animeRelationsCache = {};
  static DateTime? _nowOverride;

  // Shared client for connection keep-alive
  static final http.Client _defaultClient = http.Client();
  static http.Client get _client => httpClient ?? _defaultClient;

  /// Limpa cache expirado
  static void _cleanExpiredCache() {
    _cache.removeWhere((key, entry) => entry.isExpired);
    if (_cache.length > _maxCacheSize) {
      final keysToRemove = _cache.keys
          .take(_cache.length - _maxCacheSize)
          .toList();
      for (final key in keysToRemove) {
        _cache.remove(key);
      }
    }
  }

  /// Obtém do cache se disponível e não expirado
  List<JikanAnime>? _getFromCache(String key) {
    _cleanExpiredCache();
    final entry = _cache[key];
    if (entry != null && !entry.isExpired) {
      debugPrint('[JikanService] Cache hit: $key');
      return entry.data;
    }
    return null;
  }

  /// Salva no cache
  void _saveToCache(String key, List<JikanAnime> data) {
    _cache[key] = _CacheEntry(data);
  }

  Future<List<JikanAnime>> _loadCachedList(
    String key,
    Future<List<JikanAnime>> Function() loader,
  ) async {
    final cached = _getFromCache(key);
    if (cached != null) return _filterAnimeList(cached);

    final inFlight = _inFlightListLoads[key];
    if (inFlight != null) return _filterAnimeList(await inFlight);

    final loadFuture = loader();
    _inFlightListLoads[key] = loadFuture;

    try {
      final result = deduplicateAnimeList(await loadFuture);
      _saveToCache(key, result);
      return result;
    } finally {
      if (identical(_inFlightListLoads[key], loadFuture)) {
        _inFlightListLoads.remove(key);
      }
    }
  }

  /// Carrega cache persistente do SharedPreferences
  Future<HomeData?> _loadPersistedHomeData({bool allowExpired = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_homeDataCacheKey);
      if (jsonStr != null) {
        final data = HomeData.fromJson(
          jsonMap(json.decode(jsonStr)) ?? const {},
        );
        if (allowExpired || !data.isExpired) {
          debugPrint('[JikanService] Loaded home data from persistent cache');
          return data;
        }
      }
    } catch (e) {
      debugPrint('[JikanService] Error loading persisted cache: $e');
    }
    return null;
  }

  /// Salva cache persistente no SharedPreferences
  Future<void> _persistHomeData(HomeData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_homeDataCacheKey, json.encode(data.toJson()));
      debugPrint('[JikanService] Home data persisted to cache');
    } catch (e) {
      debugPrint('[JikanService] Error persisting cache: $e');
    }
  }

  Future<HomeData?> loadCachedHomeDataSnapshot({
    bool allowExpired = false,
  }) async {
    final memoryCache = _homeDataCache;
    if (memoryCache != null && (allowExpired || !memoryCache.isExpired)) {
      return memoryCache;
    }

    return _loadPersistedHomeData(allowExpired: allowExpired);
  }

  /// Método principal: Carrega todos os dados da Home de uma vez
  /// Usa paralelo controlado para buscar tudo rapidamente
  /// Retorna cache se disponível, senão busca da API
  Future<HomeData> loadHomeData({bool forceRefresh = false}) async {
    await AvailabilityService.initialize();

    // Retorna cache em memória se disponível
    if (!forceRefresh && _homeDataCache != null && !_homeDataCache!.isExpired) {
      debugPrint('[JikanService] Returning memory cached home data');
      return _filterHomeData(_homeDataCache!);
    }

    final inFlightLoad = _homeDataLoadFuture;
    if (inFlightLoad != null) {
      debugPrint('[JikanService] Joining in-flight home data load');
      return _filterHomeData(await inFlightLoad);
    }

    HomeData? persistedFallback;

    // Tenta carregar do cache persistente primeiro
    if (!forceRefresh) {
      final persisted = await _loadPersistedHomeData();
      if (persisted != null) {
        final filtered = _filterHomeData(persisted);
        if (_hasCompleteHomeData(filtered)) {
          _homeDataCache = filtered;
          return filtered;
        }
        persistedFallback = filtered;
      } else {
        persistedFallback = await _loadPersistedHomeData(allowExpired: true);
      }
    }

    final loadFuture = _loadFreshHomeData().then((freshData) {
      final merged = _mergeMissingHomeData(
        freshData,
        persistedFallback ?? _homeDataCache,
      );
      _homeDataCache = merged;
      if (_hasCompleteHomeData(merged)) {
        unawaited(_persistHomeData(merged));
      }
      return merged;
    });
    _homeDataLoadFuture = loadFuture;

    try {
      return await loadFuture;
    } finally {
      if (identical(_homeDataLoadFuture, loadFuture)) {
        _homeDataLoadFuture = null;
      }
    }
  }

  Future<HomeData> _loadFreshHomeData() async {
    debugPrint(
      '[JikanService] Loading all home data with shared rate limiting...',
    );

    try {
      final stopwatch = Stopwatch()..start();
      final today = _getCurrentDayOfWeek();

      // Start every logical section together. Individual HTTP requests still
      // pass through _waitForRateLimit(), which serializes request starts at
      // the platform-specific safe interval. This overlaps response/parsing
      // work and avoids an extra 350 ms delay between whole sections.
      final sections = await Future.wait<List<JikanAnime>>([
        getCurrentSeasonAnimes(limit: 25),
        getScheduleForDay(today, limit: 15),
        getTopAnimes(limit: 15),
        getAnimesByGenre(JikanGenreIds.action, limit: 15),
        getAnimesByGenre(JikanGenreIds.romance, limit: 15),
        getAnimesByGenre(JikanGenreIds.comedy, limit: 15),
        getAnimesByGenre(JikanGenreIds.fantasy, limit: 15),
      ]);

      final seasonList = [...sections[0]];
      seasonList.sort((a, b) {
        if (a.airedFromIso == null && b.airedFromIso == null) return 0;
        if (a.airedFromIso == null) return 1;
        if (b.airedFromIso == null) return -1;
        return b.airedFromIso!.compareTo(a.airedFromIso!);
      });

      stopwatch.stop();
      debugPrint(
        '[JikanService] All data loaded in ${stopwatch.elapsedMilliseconds}ms',
      );

      return HomeData(
        seasonAnimes: seasonList,
        todaysReleases: sections[1],
        topAnimes: sections[2],
        actionAnimes: sections[3],
        romanceAnimes: sections[4],
        comedyAnimes: sections[5],
        fantasyAnimes: sections[6],
      );
    } catch (e) {
      if (propagateErrors) rethrow;
      debugPrint('[JikanService] Error loading home data: $e');
      return HomeData(
        seasonAnimes: [],
        todaysReleases: [],
        topAnimes: [],
        actionAnimes: [],
        romanceAnimes: [],
        comedyAnimes: [],
        fantasyAnimes: [],
      );
    }
  }

  @visibleForTesting
  Future<HomeData> debugLoadFreshHomeDataForTesting() => _loadFreshHomeData();

  /// Parse da lista de animes de uma resposta HTTP
  List<JikanAnime> _parseAnimeList(
    http.Response response, {
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) {
    try {
      final jikanResponse = _parseJikanAnimeResponse(response);

      // Enfileira todos os animes descobertos na API para scan no background
      unawaited(NewReleaseScanner.scanAnimes(jikanResponse.data));

      return _filterAnimeList(
        jikanResponse.data,
        availabilityMode: availabilityMode,
      );
    } catch (e) {
      debugPrint('[JikanService] Error parsing anime list: $e');
      return [];
    }
  }

  JikanResponse<JikanAnime> _parseJikanAnimeResponse(http.Response response) {
    final jsonData = jsonMap(json.decode(response.body)) ?? const {};
    return JikanResponse<JikanAnime>.fromJson(
      jsonData,
      (json) => JikanAnime.fromJson(json),
    );
  }

  HomeData _filterHomeData(HomeData data) {
    return HomeData(
      seasonAnimes: data
          .seasonAnimes, // Bypassa o Availability cache para mostrar novidades e acionar o scanner
      todaysReleases: data.todaysReleases, // Idem
      topAnimes: _filterAnimeList(data.topAnimes),
      actionAnimes: _filterAnimeList(data.actionAnimes),
      romanceAnimes: _filterAnimeList(data.romanceAnimes),
      comedyAnimes: _filterAnimeList(data.comedyAnimes),
      fantasyAnimes: _filterAnimeList(data.fantasyAnimes),
      loadedAt: data.loadedAt,
    );
  }

  HomeData _mergeMissingHomeData(HomeData freshData, HomeData? fallbackData) {
    if (fallbackData == null) return freshData;

    final filteredFallback = _filterHomeData(fallbackData);
    return HomeData(
      seasonAnimes: freshData.seasonAnimes.isNotEmpty
          ? freshData.seasonAnimes
          : filteredFallback.seasonAnimes,
      todaysReleases: freshData.todaysReleases.isNotEmpty
          ? freshData.todaysReleases
          : filteredFallback.todaysReleases,
      topAnimes: freshData.topAnimes.isNotEmpty
          ? freshData.topAnimes
          : filteredFallback.topAnimes,
      actionAnimes: freshData.actionAnimes.isNotEmpty
          ? freshData.actionAnimes
          : filteredFallback.actionAnimes,
      romanceAnimes: freshData.romanceAnimes.isNotEmpty
          ? freshData.romanceAnimes
          : filteredFallback.romanceAnimes,
      comedyAnimes: freshData.comedyAnimes.isNotEmpty
          ? freshData.comedyAnimes
          : filteredFallback.comedyAnimes,
      fantasyAnimes: freshData.fantasyAnimes.isNotEmpty
          ? freshData.fantasyAnimes
          : filteredFallback.fantasyAnimes,
      loadedAt: _hasAnyHomeData(freshData)
          ? freshData.loadedAt
          : filteredFallback.loadedAt,
    );
  }

  bool _hasAnyHomeData(HomeData data) {
    return data.seasonAnimes.isNotEmpty ||
        data.todaysReleases.isNotEmpty ||
        data.topAnimes.isNotEmpty ||
        data.actionAnimes.isNotEmpty ||
        data.romanceAnimes.isNotEmpty ||
        data.comedyAnimes.isNotEmpty ||
        data.fantasyAnimes.isNotEmpty;
  }

  bool _hasCompleteHomeData(HomeData data) {
    return data.seasonAnimes.isNotEmpty &&
        data.topAnimes.isNotEmpty &&
        data.actionAnimes.isNotEmpty &&
        data.romanceAnimes.isNotEmpty &&
        data.comedyAnimes.isNotEmpty &&
        data.fantasyAnimes.isNotEmpty;
  }

  List<JikanAnime> _filterAnimeList(
    Iterable<JikanAnime> animes, {
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) {
    final filtered = animes.where((anime) {
      if (!_isSafeForCatalog(anime)) return false;

      return AvailabilityService.isAvailable(
        anime.title,
        englishTitle: anime.titleEnglish,
        japaneseTitle: anime.titleJapanese,
        synonyms: anime.titleSynonyms,
        mode: availabilityMode,
      );
    });
    return deduplicateAnimeList(filtered);
  }

  bool _isSafeForCatalog(JikanAnime anime) {
    final rating = anime.rating?.toLowerCase() ?? '';
    if (rating.contains('rx') ||
        rating.contains('hentai') ||
        rating.contains('r+')) {
      return false;
    }
    return !anime.genres.any(
      (g) =>
          g.malId == 12 ||
          g.malId == 49 ||
          g.name.toLowerCase() == 'hentai' ||
          g.name.toLowerCase() == 'erotica',
    );
  }

  // Rate limiting para métodos individuais
  static DateTime? _lastRequestTime;
  static Future<void> _rateLimitTail = Future.value();
  static Duration get _minRequestInterval => _isDesktop
      ? const Duration(milliseconds: 300)
      : const Duration(milliseconds: 400);
  static int get _categorySearchPageSpan => _isDesktop ? 10 : 8;

  /// Aguarda o intervalo mínimo entre requisições
  Future<void> _waitForRateLimit() async {
    final previousTail = _rateLimitTail;
    final completer = Completer<void>();
    _rateLimitTail = completer.future;

    await previousTail;
    try {
      if (_lastRequestTime != null) {
        final elapsed = DateTime.now().difference(_lastRequestTime!);
        if (elapsed < _minRequestInterval) {
          await Future.delayed(_minRequestInterval - elapsed);
        }
      }
      _lastRequestTime = DateTime.now();
    } finally {
      completer.complete();
    }
  }

  /// Métodos individuais (usados pela SearchScreen e outras telas)

  /// Busca os top animes
  Future<List<JikanAnime>> getTopAnimes({int page = 1, int limit = 20}) async {
    await AvailabilityService.initialize();

    final cacheKey = 'top_${page}_$limit';
    return _loadCachedList(cacheKey, () {
      return _loadFilteredAnimePages(
        page: page,
        limit: limit,
        requestPage: (sourcePage) async {
          await _waitForRateLimit();
          return _client.get(
            Uri.parse(
              '$baseUrl/top/anime?page=$sourcePage&limit=$limit&sfw=true',
            ),
            headers: NetworkHeaders.identityEncoding,
          );
        },
      );
    }).catchError((Object e) {
      debugPrint('Error fetching top animes: $e');
      if (propagateErrors) throw e;
      return <JikanAnime>[];
    });
  }

  /// Busca animes da temporada atual
  Future<List<JikanAnime>> getCurrentSeasonAnimes({
    int page = 1,
    int limit = 20,
  }) async {
    await AvailabilityService.initialize();

    Object? liveError;
    try {
      final cacheKey = 'season_${page}_$limit';
      final live = await _loadCachedList(cacheKey, () {
        return _loadFilteredAnimePages(
          page: page,
          limit: limit,
          requestPage: (sourcePage) async {
            await _waitForRateLimit();
            return _client.get(
              Uri.parse(
                '$baseUrl/seasons/now?page=$sourcePage&limit=$limit&sfw=true',
              ),
              headers: NetworkHeaders.identityEncoding,
            );
          },
        );
      });
      if (live.isNotEmpty) return live;
    } catch (error) {
      liveError = error;
      debugPrint('Error fetching current season animes: $error');
    }

    final fallback = await _browseMetadataCachePage(
      seasonFilter: SeasonCatalogFilter.currentSeason(_now()),
      orderBy: 'members',
      sort: 'desc',
      page: page,
      limit: limit,
    );
    if (fallback.animes.isNotEmpty) return fallback.animes;

    if (liveError != null && propagateErrors) throw liveError;
    return const <JikanAnime>[];
  }

  /// Busca animes por gênero
  /// Gêneros disponíveis:
  /// - Action: 1
  /// - Adventure: 2
  /// - Comedy: 4
  /// - Drama: 8
  /// - Fantasy: 10
  /// - Horror: 14
  /// - Mystery: 7
  /// - Romance: 22
  /// - Sci-Fi: 24
  /// - Slice of Life: 36
  /// - Sports: 30
  /// - Supernatural: 37
  Future<List<JikanAnime>> getAnimesByGenre(
    int genreId, {
    int page = 1,
    int limit = 20,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    await AvailabilityService.initialize();

    final cacheKey =
        'genre_${genreId}_${page}_${limit}_${availabilityMode.name}';
    return _loadCachedList(cacheKey, () {
      return _searchCategoryAnimes(
        genres: [genreId],
        orderBy: 'score',
        sort: 'desc',
        page: page,
        limit: limit,
        availabilityMode: availabilityMode,
      );
    }).catchError((Object e) {
      debugPrint('Error fetching animes by genre: $e');
      if (propagateErrors) throw e;
      return <JikanAnime>[];
    });
  }

  Future<List<JikanAnime>> getAnimesByProducer(
    int producerId, {
    int page = 1,
    int limit = 20,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    await AvailabilityService.initialize();

    final cacheKey =
        'producer_${producerId}_${page}_${limit}_${availabilityMode.name}';
    return _loadCachedList(cacheKey, () {
      return _searchBrowsableAnimes(
        producers: [producerId],
        orderBy: 'score',
        sort: 'desc',
        page: page,
        limit: limit,
        availabilityMode: availabilityMode,
      );
    }).catchError((Object e) {
      debugPrint('Error fetching animes by producer: $e');
      if (propagateErrors) throw e;
      return <JikanAnime>[];
    });
  }

  /// Busca animes populares (ordenados por membros)
  Future<List<JikanAnime>> getPopularAnimes({
    int page = 1,
    int limit = 20,
  }) async {
    await AvailabilityService.initialize();

    final cacheKey = 'popular_${page}_$limit';
    return _loadCachedList(cacheKey, () async {
      await _waitForRateLimit();
      final response = await _client.get(
        Uri.parse(
          '$baseUrl/anime?order_by=members&sort=desc&page=$page&limit=$limit&sfw=true',
        ),
        headers: NetworkHeaders.identityEncoding,
      );

      if (response.statusCode == 200) {
        return _parseAnimeList(response);
      }
      throw Exception('Failed to load popular animes: ${response.statusCode}');
    }).catchError((Object e) {
      debugPrint('Error fetching popular animes: $e');
      return <JikanAnime>[];
    });
  }

  /// Busca animes em exibição
  Future<List<JikanAnime>> getAiringAnimes({
    int page = 1,
    int limit = 20,
  }) async {
    await AvailabilityService.initialize();

    final cacheKey = 'airing_${page}_$limit';
    return _loadCachedList(cacheKey, () async {
      await _waitForRateLimit();
      final response = await _client.get(
        Uri.parse(
          '$baseUrl/anime?status=airing&order_by=score&sort=desc&page=$page&limit=$limit&sfw=true',
        ),
        headers: NetworkHeaders.identityEncoding,
      );

      if (response.statusCode == 200) {
        return _parseAnimeList(response);
      }
      throw Exception('Failed to load airing animes: ${response.statusCode}');
    }).catchError((Object e) {
      debugPrint('Error fetching airing animes: $e');
      return <JikanAnime>[];
    });
  }

  Future<List<JikanAnime>> getScheduleForDay(
    String day, {
    int limit = 25,
  }) async {
    await AvailabilityService.initialize();

    final normalizedDay = day.toLowerCase().trim();
    final cacheKey = 'schedule_${normalizedDay}_$limit';
    return _loadCachedList(cacheKey, () async {
      await _waitForRateLimit();
      final response = await _client.get(
        Uri.parse('$baseUrl/schedules/$normalizedDay?sfw=true&limit=$limit'),
        headers: NetworkHeaders.identityEncoding,
      );

      if (response.statusCode == 200) {
        return _sortByPopularity(_parseAnimeList(response));
      }
      throw Exception('Failed to load schedule: ${response.statusCode}');
    }).catchError((Object e) {
      debugPrint('Error fetching schedule for $normalizedDay: $e');
      if (propagateErrors) throw e;
      return <JikanAnime>[];
    });
  }

  List<JikanAnime> _sortByPopularity(List<JikanAnime> animes) {
    return [...animes]
      ..sort((a, b) => (b.members ?? 0).compareTo(a.members ?? 0));
  }

  /// Busca recomendações de animes
  Future<List<JikanAnime>> getRecommendedAnimes({int page = 1}) async {
    await AvailabilityService.initialize();

    final cacheKey = 'recommended_$page';
    return _loadCachedList(cacheKey, () async {
      await _waitForRateLimit();
      final response = await _client.get(
        Uri.parse('$baseUrl/recommendations/anime?page=$page'),
        headers: NetworkHeaders.identityEncoding,
      );

      if (response.statusCode == 200) {
        final jsonData = jsonMap(json.decode(response.body)) ?? const {};
        final data = jsonList(jsonData['data']);

        // Extrai animes das recomendações
        final List<JikanAnime> animes = [];
        for (final item in data.take(20).map(jsonMap).nonNulls) {
          final entries = jsonList(item['entry']);
          if (entries.isNotEmpty) {
            for (final entry in entries.map(jsonMap).nonNulls) {
              try {
                animes.add(JikanAnime.fromJson(entry));
              } catch (e) {
                debugPrint('Error parsing recommendation entry: $e');
              }
            }
          }
        }

        return _filterAnimeList(animes);
      }
      throw Exception(
        'Failed to load recommended animes: ${response.statusCode}',
      );
    }).catchError((Object e) {
      debugPrint('Error fetching recommended animes: $e');
      return <JikanAnime>[];
    });
  }

  /// Busca anime por ID
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

  Future<List<JikanAnimeRelation>> getAnimeRelations(int malId) async {
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

  Future<
    ({
      JikanAnimeExtras? extras,
      String? broadcastDay,
      String? broadcastTime,
      String? broadcastString,
      String? status,
    })
  >
  getAnimeFullById(int malId) async {
    if (malId <= 0) {
      return (
        extras: null,
        broadcastDay: null,
        broadcastTime: null,
        broadcastString: null,
        status: null,
      );
    }

    try {
      await _waitForRateLimit();
      final response = await _client.get(
        Uri.parse('$baseUrl/anime/$malId/full'),
        headers: NetworkHeaders.identityEncoding,
      );

      if (response.statusCode == 200) {
        final jsonData = jsonMap(json.decode(response.body)) ?? const {};
        final data = jsonMap(jsonData['data']);
        if (data == null) {
          return (
            extras: null,
            broadcastDay: null,
            broadcastTime: null,
            broadcastString: null,
            status: null,
          );
        }
        final broadcast = jsonMap(data['broadcast']);
        return (
          extras: JikanAnimeExtras.fromAnimeJson(data),
          broadcastDay: jsonString(broadcast?['day']),
          broadcastTime: jsonString(broadcast?['time']),
          broadcastString: jsonString(broadcast?['string']),
          status: jsonString(data['status']),
        );
      }
      throw Exception('Failed to load anime extras: ${response.statusCode}');
    } catch (e) {
      debugPrint('Error fetching anime extras by id: $e');
      return (
        extras: null,
        broadcastDay: null,
        broadcastTime: null,
        broadcastString: null,
        status: null,
      );
    }
  }

  Future<JikanAnimeExtras?> getAnimeExtrasById(int malId) async {
    final result = await getAnimeFullById(malId);
    return result.extras;
  }

  Future<JikanNamedResource?> findProducerByName(String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return null;

    try {
      await _waitForRateLimit();
      final url = Uri.parse(baseUrl).replace(
        path: '${Uri.parse(baseUrl).path}/producers',
        queryParameters: {'q': normalizedName, 'limit': '10'},
      );
      final response = await _client.get(
        url,
        headers: NetworkHeaders.identityEncoding,
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to search producer: ${response.statusCode}');
      }

      final decoded = jsonMap(json.decode(response.body)) ?? const {};
      final data = jsonList(decoded['data']);
      final exact = data.whereType<Map<String, dynamic>>().firstWhere(
        (producer) => _producerMatchesName(producer, normalizedName),
        orElse: () => const {},
      );
      if (exact.isEmpty) return null;

      final titles = exact['titles'] as List<dynamic>? ?? const [];
      final defaultTitle = titles.whereType<Map<String, dynamic>>().firstWhere(
        (title) => title['type'] == 'Default',
        orElse: () => const {},
      );
      return JikanNamedResource(
        malId: jsonIntOr(exact['mal_id'], 0),
        name: defaultTitle['title']?.toString() ?? normalizedName,
        url: exact['url']?.toString(),
      );
    } catch (e) {
      debugPrint('Error searching producer by name: $e');
      return null;
    }
  }

  bool _producerMatchesName(Map<String, dynamic> producer, String name) {
    final expected = name.toLowerCase();
    final titles = producer['titles'] as List<dynamic>? ?? const [];
    return titles.whereType<Map<String, dynamic>>().any((title) {
      return title['title']?.toString().trim().toLowerCase() == expected;
    });
  }

  /// Busca animes por termo de pesquisa
  Future<List<JikanAnime>> searchAnimes(
    String query, {
    List<int>? genres,
    String? orderBy,
    String? sort,
    int page = 1,
    int limit = 20,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
    SeasonCatalogFilter? seasonFilter,
  }) async {
    await AvailabilityService.initialize();

    final normalizedQuery = query.trim();
    final cacheKey = [
      'search',
      normalizedQuery.toLowerCase(),
      genres?.join(',') ?? '',
      orderBy ?? '',
      sort ?? '',
      page,
      limit,
      availabilityMode.name,
      seasonFilter?.year ?? '',
      seasonFilter?.jikanSeason ?? '',
    ].join('_');

    return _loadCachedList(cacheKey, () async {
      if (seasonFilter != null) {
        final seasonPage = await _searchSeasonAnimePage(
          seasonFilter: seasonFilter,
          query: normalizedQuery,
          genres: genres,
          orderBy: orderBy,
          sort: sort,
          page: page,
          limit: limit,
          availabilityMode: availabilityMode,
        );
        return seasonPage.animes;
      }

      if (normalizedQuery.isEmpty) {
        return _searchBrowsableAnimes(
          genres: genres,
          orderBy: orderBy,
          sort: sort,
          page: page,
          limit: limit,
          availabilityMode: availabilityMode,
        );
      }

      final metadataCacheResults = await _searchMetadataCache(
        normalizedQuery,
        limit: limit,
        availabilityMode: availabilityMode,
      );
      if (metadataCacheResults.isNotEmpty) {
        unawaited(
          _refreshMetadataCacheFromOnlineSearch(
            normalizedQuery,
            genres: genres,
            orderBy: orderBy,
            sort: sort,
            limit: limit,
            availabilityMode: availabilityMode,
          ),
        );
        return metadataCacheResults;
      }

      final response = await _getAnimeSearchPage(
        query: normalizedQuery,
        genres: genres,
        orderBy: orderBy,
        sort: sort,
        page: page,
        limit: limit,
      );

      if (response.statusCode == 200) {
        final animes = await _parseSearchAnimeListWithAvailabilityCache(
          response,
          availabilityMode: availabilityMode,
          limit: limit,
        );
        unawaited(_saveMetadataCache(animes));
        return animes;
      }
      throw Exception('Failed to search animes: ${response.statusCode}');
    }).catchError((Object e) {
      debugPrint('Error searching animes: $e');
      return <JikanAnime>[];
    });
  }

  Future<JikanBrowsePage> browseAnimes({
    List<int>? genres,
    String? orderBy,
    String? sort,
    int page = 1,
    int limit = 20,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
    SeasonCatalogFilter? seasonFilter,
  }) async {
    await AvailabilityService.initialize();

    Object? liveError;
    JikanBrowsePage? liveResult;
    try {
      liveResult = seasonFilter != null
          ? await _searchSeasonAnimePage(
              seasonFilter: seasonFilter,
              query: '',
              genres: genres,
              orderBy: orderBy,
              sort: sort,
              page: page,
              limit: limit,
              availabilityMode: availabilityMode,
            )
          : await _searchBrowsableAnimePage(
              genres: genres,
              orderBy: orderBy,
              sort: sort,
              page: page,
              limit: limit,
              availabilityMode: availabilityMode,
            );
      if (liveResult.animes.isNotEmpty) return liveResult;
    } catch (error) {
      liveError = error;
      debugPrint('Error browsing animes: $error');
    }

    final fallback = await _browseMetadataCachePage(
      genres: genres,
      orderBy: orderBy,
      sort: sort,
      page: page,
      limit: limit,
      availabilityMode: availabilityMode,
      seasonFilter: seasonFilter,
    );
    if (fallback.animes.isNotEmpty) return fallback;

    if (liveError != null && propagateErrors) throw liveError;
    if (liveResult != null) return liveResult;
    return JikanBrowsePage(animes: const [], nextPage: page, hasMore: false);
  }

  Future<JikanBrowsePage> _browseMetadataCachePage({
    List<int>? genres,
    String? orderBy,
    String? sort,
    required int page,
    required int limit,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
    SeasonCatalogFilter? seasonFilter,
  }) async {
    if (page <= 0 || limit <= 0) {
      return JikanBrowsePage(animes: const [], nextPage: page, hasMore: false);
    }

    try {
      final entries = await _metadataCacheService.catalogCandidates(
        limit: 400,
        allowExpired: true,
      );
      final candidates = entries
          .map((entry) => entry.toJikanAnime())
          .where(_isSafeForCatalog)
          .where((anime) => _matchesMetadataGenreFilter(anime, genres))
          .where((anime) {
            if (seasonFilter == null) {
              return _isCachedAvailable(anime, availabilityMode);
            }
            if (!_matchesSeasonFilter(anime, seasonFilter)) return false;
            return _isSeasonCatalogVisible(
              anime,
              seasonFilter,
              availabilityMode,
            );
          })
          .toList();

      _sortSeasonResults(candidates, orderBy: orderBy, sort: sort);
      final deduped = deduplicateAnimeList(candidates);
      final start = (page - 1) * limit;
      if (start >= deduped.length) {
        return JikanBrowsePage(
          animes: const [],
          nextPage: page,
          hasMore: false,
        );
      }
      final end = start + limit < deduped.length
          ? start + limit
          : deduped.length;
      return JikanBrowsePage(
        animes: deduped.sublist(start, end),
        nextPage: page + 1,
        hasMore: end < deduped.length,
      );
    } catch (error) {
      debugPrint('[JikanService] Metadata catalog fallback failed: $error');
      return JikanBrowsePage(animes: const [], nextPage: page, hasMore: false);
    }
  }

  bool _matchesMetadataGenreFilter(JikanAnime anime, List<int>? genreIds) {
    if (genreIds == null || genreIds.isEmpty) return true;
    final names = anime.genres
        .map((genre) => genre.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
    return genreIds.every((id) {
      final expected = _genreNameById[id];
      return expected != null && names.contains(expected);
    });
  }

  static const Map<int, String> _genreNameById = {
    JikanGenreIds.action: 'action',
    JikanGenreIds.adventure: 'adventure',
    JikanGenreIds.comedy: 'comedy',
    JikanGenreIds.drama: 'drama',
    JikanGenreIds.fantasy: 'fantasy',
    JikanGenreIds.horror: 'horror',
    JikanGenreIds.mystery: 'mystery',
    JikanGenreIds.romance: 'romance',
    JikanGenreIds.sciFi: 'sci-fi',
    JikanGenreIds.sliceOfLife: 'slice of life',
    JikanGenreIds.sports: 'sports',
    JikanGenreIds.supernatural: 'supernatural',
  };

  Future<List<JikanAnime>> getSeasonAnimes(
    SeasonCatalogFilter seasonFilter, {
    int page = 1,
    int limit = 20,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    final result = await browseAnimes(
      seasonFilter: seasonFilter,
      page: page,
      limit: limit,
      availabilityMode: availabilityMode,
    );
    return result.animes;
  }

  Future<JikanBrowsePage> _searchBrowsableAnimePage({
    List<int>? genres,
    String? orderBy,
    String? sort,
    required int page,
    required int limit,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    final endPage = page + _categorySearchPageSpan - 1;
    final results = <JikanAnime>[];
    final seenAnimeKeys = <String>{};
    var hasMore = true;
    var lastScannedPage = page - 1;

    for (var sourcePage = page; sourcePage <= endPage; sourcePage++) {
      final response = await _getAnimeSearchPage(
        query: '',
        genres: genres,
        orderBy: orderBy,
        sort: sort,
        page: sourcePage,
        limit: limit,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to browse animes: ${response.statusCode}');
      }

      lastScannedPage = sourcePage;
      final pageResults = _parseAnimeList(
        response,
        availabilityMode: availabilityMode,
      );
      for (final anime in pageResults) {
        if (seenAnimeKeys.add(canonicalAnimeKey(anime))) {
          results.add(anime);
          if (results.length >= limit) {
            return JikanBrowsePage(
              animes: results,
              nextPage: lastScannedPage + 1,
              hasMore: _responseHasNextPage(response),
            );
          }
        }
      }

      hasMore = _responseHasNextPage(response);
      if (!hasMore) break;
    }

    return JikanBrowsePage(
      animes: results,
      nextPage: lastScannedPage + 1,
      hasMore: hasMore,
    );
  }

  Future<JikanBrowsePage> _searchSeasonAnimePage({
    required SeasonCatalogFilter seasonFilter,
    String query = '',
    List<int>? genres,
    String? orderBy,
    String? sort,
    required int page,
    required int limit,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    final endPage = page + _categorySearchPageSpan - 1;
    final results = <JikanAnime>[];
    final seenAnimeKeys = <String>{};
    var hasMore = true;
    var lastScannedPage = page - 1;

    for (var sourcePage = page; sourcePage <= endPage; sourcePage++) {
      final response = await _getSeasonAnimePage(
        seasonFilter: seasonFilter,
        page: sourcePage,
        limit: limit,
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to browse season animes: ${response.statusCode}',
        );
      }

      lastScannedPage = sourcePage;
      final rawResults = _parseJikanAnimeResponse(response).data;
      unawaited(NewReleaseScanner.scanAnimes(rawResults));

      final pageResults = _filterSeasonAnimeList(
        rawResults,
        seasonFilter: seasonFilter,
        query: query,
        genres: genres,
        orderBy: orderBy,
        sort: sort,
        availabilityMode: availabilityMode,
      );

      for (final anime in pageResults) {
        if (seenAnimeKeys.add(canonicalAnimeKey(anime))) {
          results.add(anime);
          if (results.length >= limit) {
            return JikanBrowsePage(
              animes: results,
              nextPage: lastScannedPage + 1,
              hasMore: _responseHasNextPage(response),
            );
          }
        }
      }

      hasMore = _responseHasNextPage(response);
      if (!hasMore) break;
    }

    return JikanBrowsePage(
      animes: results,
      nextPage: lastScannedPage + 1,
      hasMore: hasMore,
    );
  }

  Future<List<JikanAnime>> searchCachedAnimes(
    String query, {
    int limit = 20,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    final titles = await AvailabilityService.searchLocalTitles(
      query,
      mode: availabilityMode,
      limit: limit,
    );

    final metadataResults = await _searchMetadataCache(
      query,
      limit: limit,
      availabilityMode: availabilityMode,
    );
    if (metadataResults.isNotEmpty) {
      final metadataByKey = <String, JikanAnime>{};
      for (final anime in metadataResults) {
        for (final key in _sourceTitleKeys(anime)) {
          metadataByKey.putIfAbsent(key, () => anime);
        }
      }

      final merged = <JikanAnime>[];
      final seen = <String>{};
      for (final title in titles) {
        final keys = canonicalTitleMatchKeys(title);
        final cached = keys
            .map((key) => metadataByKey[key])
            .whereType<JikanAnime>()
            .firstOrNull;
        final anime =
            cached ??
            JikanAnime(
              malId: _stableLocalMalId(title),
              title: _formatCachedTitle(title),
              imageUrl: '',
            );
        if (seen.add(canonicalAnimeKey(anime))) merged.add(anime);
        if (merged.length >= limit) break;
      }

      for (final anime in metadataResults) {
        if (!seen.add(canonicalAnimeKey(anime))) continue;
        merged.add(anime);
        if (merged.length >= limit) break;
      }

      return merged;
    }

    return deduplicateAnimeList([
      for (final title in titles)
        JikanAnime(
          malId: _stableLocalMalId(title),
          title: _formatCachedTitle(title),
          imageUrl: '',
        ),
    ]);
  }

  Future<List<JikanAnime>> searchAnimeMetadata(
    String query, {
    int limit = 20,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    await AvailabilityService.initialize();

    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const [];

    final cacheKey = [
      'metadata',
      normalizedQuery.toLowerCase(),
      limit,
      availabilityMode.name,
    ].join('_');

    return _loadCachedList(cacheKey, () async {
      final metadataCacheResults = await _searchMetadataCache(
        normalizedQuery,
        limit: limit,
        availabilityMode: availabilityMode,
      );
      if (metadataCacheResults.isNotEmpty) {
        unawaited(
          _refreshMetadataCacheFromOnlineSearch(
            normalizedQuery,
            limit: limit,
            availabilityMode: availabilityMode,
          ),
        );
        return metadataCacheResults;
      }

      final response = await _getAnimeSearchPage(
        query: normalizedQuery,
        page: 1,
        limit: limit,
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to search anime metadata: ${response.statusCode}',
        );
      }

      final animes = _parseJikanAnimeResponse(response).data;
      final filtered = animes
          .where(_isSafeForCatalog)
          .where((anime) => _isCachedAvailable(anime, availabilityMode))
          .take(limit)
          .toList();
      unawaited(_saveMetadataCache(filtered));
      return filtered;
    }).catchError((Object e) {
      debugPrint('Error searching anime metadata: $e');
      return <JikanAnime>[];
    });
  }

  Future<List<JikanAnime>> _searchMetadataCache(
    String query, {
    required int limit,
    required AnimeAvailabilityMode availabilityMode,
  }) async {
    try {
      final entries = await _metadataCacheService.search(query, limit: limit);
      return entries
          .map((entry) => entry.toJikanAnime())
          .where(_isSafeForCatalog)
          .where((anime) => _isCachedAvailable(anime, availabilityMode))
          .take(limit)
          .toList();
    } catch (error) {
      debugPrint('[JikanService] Metadata cache search failed: $error');
      return const [];
    }
  }

  Future<void> _saveMetadataCache(List<JikanAnime> animes) async {
    await cacheMetadataFromSearchFallbacks(animes, source: 'jikan');
  }

  Future<void> cacheMetadataFromSearchFallbacks(
    List<JikanAnime> animes, {
    String source = 'source-fallback',
  }) async {
    if (animes.isEmpty) return;

    try {
      await _metadataCacheService.upsertEntries(
        animes
            .where(_isSafeForCatalog)
            .where((anime) => anime.imageUrl.trim().isNotEmpty)
            .map(
              (anime) =>
                  AnimeMetadataCacheEntry.fromJikanAnime(anime, source: source),
            )
            .toList(),
      );
    } catch (error) {
      debugPrint('[JikanService] Metadata cache save failed: $error');
    }
  }

  Future<void> _refreshMetadataCacheFromOnlineSearch(
    String query, {
    List<int>? genres,
    String? orderBy,
    String? sort,
    int limit = 20,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    try {
      final response = await _getAnimeSearchPage(
        query: query,
        genres: genres,
        orderBy: orderBy,
        sort: sort,
        page: 1,
        limit: limit,
      );
      if (response.statusCode != 200) return;
      final animes = _parseJikanAnimeResponse(response).data
          .where(_isSafeForCatalog)
          .where((anime) => _isCachedAvailable(anime, availabilityMode))
          .take(limit)
          .toList();
      await _saveMetadataCache(animes);
    } catch (error) {
      debugPrint('[JikanService] Metadata cache refresh failed: $error');
    }
  }

  Future<List<JikanAnime>> _parseSearchAnimeListWithAvailabilityCache(
    http.Response response, {
    required AnimeAvailabilityMode availabilityMode,
    required int limit,
  }) async {
    try {
      final animes = _parseJikanAnimeResponse(response).data;
      final results = <JikanAnime>[];

      for (final anime in animes) {
        if (!_isSafeForCatalog(anime)) continue;
        if (_isCachedAvailable(anime, availabilityMode)) {
          results.add(anime);
        }
        if (results.length >= limit) break;
      }

      return results;
    } catch (e) {
      debugPrint('[JikanService] Error parsing search anime list: $e');
      return [];
    }
  }

  bool _isCachedAvailable(
    JikanAnime anime,
    AnimeAvailabilityMode availabilityMode,
  ) {
    return AvailabilityService.isAvailable(
      anime.title,
      englishTitle: anime.titleEnglish,
      japaneseTitle: anime.titleJapanese,
      synonyms: anime.titleSynonyms,
      mode: availabilityMode,
    );
  }

  List<JikanAnime> _filterSeasonAnimeList(
    Iterable<JikanAnime> animes, {
    required SeasonCatalogFilter seasonFilter,
    String query = '',
    List<int>? genres,
    String? orderBy,
    String? sort,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) {
    final filtered = animes.where((anime) {
      if (!_isSafeForCatalog(anime)) return false;
      if (!_matchesSeasonFilter(anime, seasonFilter)) return false;
      if (!_matchesGenreFilter(anime, genres)) return false;
      if (!_matchesAnimeQuery(anime, query)) return false;
      return _isSeasonCatalogVisible(anime, seasonFilter, availabilityMode);
    }).toList();

    _sortSeasonResults(filtered, orderBy: orderBy, sort: sort);
    return deduplicateAnimeList(filtered);
  }

  bool _matchesSeasonFilter(
    JikanAnime anime,
    SeasonCatalogFilter seasonFilter,
  ) {
    if (anime.year != null && anime.year != seasonFilter.year) return false;
    final animeSeason = AnimeSeason.fromJikanValue(anime.season);
    if (animeSeason != null && animeSeason != seasonFilter.season) {
      return false;
    }
    return true;
  }

  bool _matchesGenreFilter(JikanAnime anime, List<int>? genres) {
    if (genres == null || genres.isEmpty) return true;
    final animeGenres = anime.genres.map((genre) => genre.malId).toSet();
    return genres.every(animeGenres.contains);
  }

  bool _matchesAnimeQuery(JikanAnime anime, String query) {
    final normalizedQuery = TitleNormalizer.normalize(query);
    if (normalizedQuery.isEmpty) return true;

    final compactQuery = normalizedQuery.replaceAll(' ', '');
    return animeTitleMatchKeys(anime).any((key) {
      return key.contains(normalizedQuery) ||
          key.replaceAll(' ', '').contains(compactQuery);
    });
  }

  bool _isSeasonCatalogVisible(
    JikanAnime anime,
    SeasonCatalogFilter seasonFilter,
    AnimeAvailabilityMode availabilityMode,
  ) {
    if (_isCachedAvailable(anime, availabilityMode)) return true;
    return _isSeasonalUpcomingVisible(anime, seasonFilter);
  }

  bool _isSeasonalUpcomingVisible(
    JikanAnime anime,
    SeasonCatalogFilter seasonFilter,
  ) {
    final now = _now().toUtc();
    final airedFrom = _airedFromUtc(anime);
    if (airedFrom != null) {
      return !now.isAfter(airedFrom.add(const Duration(days: 7)));
    }

    final status = anime.status?.toLowerCase() ?? '';
    if (!status.contains('not yet aired')) return false;

    final seasonGraceEnd = seasonFilter.approximateEndDate.add(
      const Duration(days: 7),
    );
    return !now.isAfter(seasonGraceEnd);
  }

  DateTime? _airedFromUtc(JikanAnime anime) {
    final airedFromIso = anime.airedFromIso;
    if (airedFromIso == null || airedFromIso.isEmpty) return null;
    return DateTime.tryParse(airedFromIso)?.toUtc();
  }

  void _sortSeasonResults(
    List<JikanAnime> animes, {
    String? orderBy,
    String? sort,
  }) {
    final direction = sort == 'asc' ? 1 : -1;
    int compareValues<T extends Comparable<Object>?>(T a, T b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return a.compareTo(b) * direction;
    }

    switch (orderBy) {
      case 'title':
        animes.sort(
          (a, b) => compareValues(a.title.toLowerCase(), b.title.toLowerCase()),
        );
      case 'score':
        animes.sort((a, b) => compareValues(a.score, b.score));
      case 'members':
        animes.sort((a, b) => compareValues(a.members, b.members));
      case 'start_date':
        animes.sort(
          (a, b) => compareValues(_airedFromUtc(a), _airedFromUtc(b)),
        );
    }
  }

  static DateTime _now() => _nowOverride ?? DateTime.now();

  static Set<String> _sourceTitleKeys(JikanAnime anime) {
    return animeTitleMatchKeys(anime);
  }

  static String _formatCachedTitle(String title) {
    return title
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) {
          if (part.length <= 3 && RegExp(r'^\d').hasMatch(part)) {
            return part;
          }
          return part[0].toUpperCase() + part.substring(1);
        })
        .join(' ');
  }

  static int _stableLocalMalId(String title) {
    var hash = 0;
    for (final unit in title.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return -hash;
  }

  Future<List<JikanAnime>> _searchCategoryAnimes({
    required List<int> genres,
    String? orderBy,
    String? sort,
    required int page,
    required int limit,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    return _searchBrowsableAnimes(
      genres: genres,
      orderBy: orderBy,
      sort: sort,
      page: page,
      limit: limit,
      availabilityMode: availabilityMode,
    );
  }

  Future<List<JikanAnime>> _searchBrowsableAnimes({
    List<int>? genres,
    List<int>? producers,
    String? orderBy,
    String? sort,
    required int page,
    required int limit,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    final startPage = ((page - 1) * _categorySearchPageSpan) + 1;
    final endPage = startPage + _categorySearchPageSpan - 1;
    final results = <JikanAnime>[];
    final seenAnimeKeys = <String>{};

    for (var sourcePage = startPage; sourcePage <= endPage; sourcePage++) {
      final response = await _getAnimeSearchPage(
        query: '',
        genres: genres,
        producers: producers,
        orderBy: orderBy,
        sort: sort,
        page: sourcePage,
        limit: limit,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to search animes: ${response.statusCode}');
      }

      final pageResults = _parseAnimeList(
        response,
        availabilityMode: availabilityMode,
      );
      for (final anime in pageResults) {
        if (seenAnimeKeys.add(canonicalAnimeKey(anime))) {
          results.add(anime);
          if (results.length >= limit) return results;
        }
      }

      if (!_responseHasNextPage(response)) return results;
    }

    return results;
  }

  Future<List<JikanAnime>> _loadFilteredAnimePages({
    required int page,
    required int limit,
    required Future<http.Response> Function(int sourcePage) requestPage,
    AnimeAvailabilityMode availabilityMode = AnimeAvailabilityMode.any,
  }) async {
    final startPage = ((page - 1) * _categorySearchPageSpan) + 1;
    final endPage = startPage + _categorySearchPageSpan - 1;
    final results = <JikanAnime>[];
    final seenAnimeKeys = <String>{};

    for (var sourcePage = startPage; sourcePage <= endPage; sourcePage++) {
      final response = await requestPage(sourcePage);
      if (response.statusCode != 200) {
        throw Exception('Failed to load anime page: ${response.statusCode}');
      }

      final pageResults = _parseAnimeList(
        response,
        availabilityMode: availabilityMode,
      );
      for (final anime in pageResults) {
        if (seenAnimeKeys.add(canonicalAnimeKey(anime))) {
          results.add(anime);
          if (results.length >= limit) return results;
        }
      }

      if (!_responseHasNextPage(response)) return results;
    }

    return results;
  }

  Future<NewReleaseScanSummary> scanNewAvailabilityAggressively({
    int limitPerEndpoint = 25,
  }) async {
    await AvailabilityService.initialize();

    final candidates = <JikanAnime>[];
    Future<void> addFrom(Uri uri) async {
      try {
        await _waitForRateLimit();
        final response = await _client.get(
          uri,
          headers: NetworkHeaders.identityEncoding,
        );
        if (response.statusCode != 200) return;
        candidates.addAll(_parseJikanAnimeResponse(response).data);
      } catch (error) {
        debugPrint('[JikanService] Discovery endpoint failed: $error');
      }
    }

    final today = _getCurrentDayOfWeek();
    await addFrom(
      Uri.parse('$baseUrl/seasons/now?page=1&limit=$limitPerEndpoint&sfw=true'),
    );
    await addFrom(
      Uri.parse(
        '$baseUrl/seasons/upcoming?page=1&limit=$limitPerEndpoint&sfw=true',
      ),
    );
    await addFrom(
      Uri.parse('$baseUrl/schedules/$today?sfw=true&limit=$limitPerEndpoint'),
    );
    await addFrom(
      Uri.parse(
        '$baseUrl/anime?status=airing&order_by=members&sort=desc&page=1&limit=$limitPerEndpoint&sfw=true',
      ),
    );

    final deduped = deduplicateAnimeList(candidates.where(_isSafeForCatalog));
    return NewReleaseScanner.scanNow(
      deduped,
      mode: NewReleaseScanMode.manualAggressive,
      force: true,
      delayBetweenCandidates: const Duration(milliseconds: 350),
    );
  }

  bool _responseHasNextPage(http.Response response) {
    try {
      final decoded = jsonMap(json.decode(response.body)) ?? const {};
      final pagination = jsonMap(decoded['pagination']);
      if (pagination == null) return true;
      return jsonBool(pagination['has_next_page']) ?? false;
    } catch (_) {
      return true;
    }
  }

  Future<http.Response> _getAnimeSearchPage({
    required String query,
    List<int>? genres,
    List<int>? producers,
    String? orderBy,
    String? sort,
    required int page,
    required int limit,
  }) async {
    await _waitForRateLimit();
    final queryParameters = <String, String>{
      'q': query,
      'sfw': 'true',
      'page': page.toString(),
      'limit': limit.toString(),
    };

    if (genres != null && genres.isNotEmpty) {
      queryParameters['genres'] = genres.join(',');
    }
    if (producers != null && producers.isNotEmpty) {
      queryParameters['producers'] = producers.join(',');
    }
    if (orderBy != null) queryParameters['order_by'] = orderBy;
    if (sort != null) queryParameters['sort'] = sort;

    final url = Uri.parse(baseUrl).replace(
      path: '${Uri.parse(baseUrl).path}/anime',
      queryParameters: queryParameters,
    );

    return _client.get(url, headers: NetworkHeaders.identityEncoding);
  }

  Future<http.Response> _getSeasonAnimePage({
    required SeasonCatalogFilter seasonFilter,
    required int page,
    required int limit,
  }) async {
    await _waitForRateLimit();
    final url = Uri.parse(baseUrl).replace(
      path:
          '${Uri.parse(baseUrl).path}/seasons/${seasonFilter.year}/${seasonFilter.jikanSeason}',
      queryParameters: <String, String>{
        'sfw': 'true',
        'page': page.toString(),
        'limit': limit.toString(),
      },
    );

    return _client.get(url, headers: NetworkHeaders.identityEncoding);
  }

  @visibleForTesting
  static void debugResetCache() {
    _homeDataCache = null;
    _homeDataLoadFuture = null;
    _cache.clear();
    _animeByIdCache.clear();
    _animeRelationsCache.clear();
    _inFlightListLoads.clear();
    _lastRequestTime = null;
    _rateLimitTail = Future.value();
    _metadataCacheService = AnimeMetadataCacheService();
    _nowOverride = null;
  }

  @visibleForTesting
  static void debugSetNowForTesting(DateTime? now) {
    _nowOverride = now;
  }

  @visibleForTesting
  static void debugSetAnimeMetadataCacheService(
    AnimeMetadataCacheService service,
  ) {
    _metadataCacheService = service;
  }

  String _getCurrentDayOfWeek() {
    switch (DateTime.now().weekday) {
      case DateTime.monday:
        return 'monday';
      case DateTime.tuesday:
        return 'tuesday';
      case DateTime.wednesday:
        return 'wednesday';
      case DateTime.thursday:
        return 'thursday';
      case DateTime.friday:
        return 'friday';
      case DateTime.saturday:
        return 'saturday';
      case DateTime.sunday:
        return 'sunday';
      default:
        return 'monday';
    }
  }
}

// IDs de gêneros mais populares
class JikanGenreIds {
  static const int action = 1;
  static const int adventure = 2;
  static const int comedy = 4;
  static const int drama = 8;
  static const int fantasy = 10;
  static const int horror = 14;
  static const int mystery = 7;
  static const int romance = 22;
  static const int sciFi = 24;
  static const int sliceOfLife = 36;
  static const int sports = 30;
  static const int supernatural = 37;
}
