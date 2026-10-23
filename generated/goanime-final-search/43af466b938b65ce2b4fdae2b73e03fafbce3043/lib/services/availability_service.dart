import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:goanime_core/goanime_core.dart';
import 'package:http/http.dart' as http;

import '../models/jikan_models.dart';
import 'dynamic_availability_cache.dart';
import 'mal_availability_service.dart';
import 'mal_provider_availability_service.dart';
import 'title_availability_database_service.dart';

enum AnimeAvailabilityMode { any, sub, dub }

enum ProviderAvailabilityDecision { available, unavailable, unknown }

class AnimeModeAvailability {
  final bool hasSub;
  final bool hasDub;

  const AnimeModeAvailability({required this.hasSub, required this.hasDub});

  factory AnimeModeAvailability.fromJson(Object? json) {
    if (json is Map<String, dynamic>) {
      return AnimeModeAvailability(
        hasSub: json['sub'] == true,
        hasDub: json['dub'] == true,
      );
    }
    if (json is Map) {
      return AnimeModeAvailability(
        hasSub: json['sub'] == true,
        hasDub: json['dub'] == true,
      );
    }
    return const AnimeModeAvailability(hasSub: false, hasDub: false);
  }

  bool matches(AnimeAvailabilityMode mode) {
    return switch (mode) {
      AnimeAvailabilityMode.any => hasSub || hasDub,
      AnimeAvailabilityMode.sub => hasSub,
      AnimeAvailabilityMode.dub => hasDub,
    };
  }

  AnimeModeAvailability merge(AnimeModeAvailability other) {
    return AnimeModeAvailability(
      hasSub: hasSub || other.hasSub,
      hasDub: hasDub || other.hasDub,
    );
  }
}

class AvailabilityService {
  /// Stable IDs shared by the generated provider provenance asset and the
  /// production runtime source registry. AllAnime is an aggregate source and
  /// intentionally has no provider-specific availability entry.
  static const Map<AnimeSource, String> providerAvailabilityIds = {
    AnimeSource.animeFire: 'animefire',
    AnimeSource.animesOnline: 'animesonline',
    AnimeSource.goyabu: 'goyabu',
    AnimeSource.anitube: 'anitube',
  };

  static String? providerAvailabilityIdForSource(AnimeSource source) {
    return providerAvailabilityIds[source];
  }

  static final Set<String> _availableTitles = {};
  static final Set<String> _availableKeys = {};
  static final Map<String, AnimeModeAvailability> _modeKeys = {};
  static final Map<String, Set<String>> _titleKeysByTitle = {};
  static final Map<String, DateTime> _discoveryKeyExpirations = {};
  static final ValueNotifier<int> updateNotifier = ValueNotifier(0);
  static bool _isInitialized = false;
  static Future<void>? _initializeFuture;
  static Future<void>? _latestCacheFuture;
  static Future<void>? _reloadFuture;
  static int _cacheGeneration = 0;

  static const Duration _airingDiscoveryWindow = Duration(days: 120);
  static const Duration _recentDiscoveryWindow = Duration(days: 45);
  static const Duration _upcomingDiscoveryWindow = Duration(days: 14);
  static const Duration _discoveryVisibilityTtl = Duration(days: 14);

  /// Loads the availability cache from the bundled asset or runtime database.
  static Future<void> initialize() async {
    if (_isInitialized) return;
    final runningInitialize = _initializeFuture;
    if (runningInitialize != null) return runningInitialize;

    final initializeFuture = _loadInitialCache();
    _initializeFuture = initializeFuture;

    try {
      await initializeFuture;
    } finally {
      if (identical(_initializeFuture, initializeFuture)) {
        _initializeFuture = null;
      }
    }
  }

  /// Reopens the active runtime database and rebuilds all in-memory indexes.
  static Future<void> reload() {
    final runningReload = _reloadFuture;
    if (runningReload != null) return runningReload;

    final reloadFuture = _reload();
    _reloadFuture = reloadFuture;
    return reloadFuture.whenComplete(() {
      if (identical(_reloadFuture, reloadFuture)) {
        _reloadFuture = null;
      }
    });
  }

  static Future<void> _reload() async {
    final runningInitialize = _initializeFuture;
    if (runningInitialize != null) await runningInitialize;

    _cacheGeneration++;
    _availableTitles.clear();
    _availableKeys.clear();
    _modeKeys.clear();
    _titleKeysByTitle.clear();
    _isInitialized = false;
    _initializeFuture = null;
    _latestCacheFuture = null;

    await TitleAvailabilityDatabaseService.resetForRuntimeDatabaseUpdate();
    await initialize();
    updateNotifier.value++;
  }

  static Future<void> _loadInitialCache() async {
    if (await _loadBundledTitleDatabase()) {
      await _injectDynamicCache();
      _isInitialized = true;
      debugPrint(
        '[AvailabilityService] Loaded ${_availableKeys.length} anime keys from title SQLite asset.',
      );
      return;
    }

    try {
      final jsonString = await rootBundle.loadString(
        'assets/data/available_animes.json',
      );
      final jsonList = jsonDecode(jsonString) as List<dynamic>;
      _replaceCache(jsonList.cast<String>());
      await _loadBundledModeCache();
      await _injectDynamicCache();
      _isInitialized = true;
      debugPrint(
        '[AvailabilityService] Loaded ${_availableKeys.length} anime keys from bundled asset.',
      );
      _startLatestCacheRefresh();
    } catch (e) {
      debugPrint('[AvailabilityService] Error loading bundled asset: $e');
    }
  }

  static void _startLatestCacheRefresh() {
    if (_latestCacheFuture != null) return;
    late final Future<void> refreshFuture;
    refreshFuture = _fetchLatestCache().whenComplete(() {
      if (identical(_latestCacheFuture, refreshFuture)) {
        _latestCacheFuture = null;
      }
    });
    _latestCacheFuture = refreshFuture;
  }

  static Future<bool> _loadBundledTitleDatabase() async {
    try {
      await TitleAvailabilityDatabaseService.initialize();
      if (!TitleAvailabilityDatabaseService.isAvailable) return false;
      final entries = await TitleAvailabilityDatabaseService.loadAllEntries();
      if (entries.isEmpty) return false;
      _replaceCacheFromDatabase(entries);
      return true;
    } catch (error) {
      debugPrint('[AvailabilityService] Title SQLite unavailable: $error');
      return false;
    }
  }

  static Future<void> _fetchLatestCache() async {
    final generation = _cacheGeneration;
    try {
      const url =
          'https://raw.githubusercontent.com/Semogtw/goAnime-mobile/main/assets/data/available_animes.json';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || generation != _cacheGeneration) return;

      final jsonList = jsonDecode(response.body) as List<dynamic>;
      final latestModes = await _fetchLatestModeCache();
      if (generation != _cacheGeneration) return;

      await DynamicAvailabilityCache.initialize();
      if (generation != _cacheGeneration) return;

      _replaceCache(jsonList.cast<String>());
      if (latestModes != null) _replaceModeCache(latestModes);
      _injectInitializedDynamicCache();
      updateNotifier.value++;
      debugPrint(
        '[AvailabilityService] Updated to ${_availableKeys.length} anime keys from GitHub.',
      );
    } catch (e) {
      debugPrint('[AvailabilityService] Failed to update from GitHub: $e');
    }
  }

  static Future<void> _injectDynamicCache() async {
    await DynamicAvailabilityCache.initialize();
    _injectInitializedDynamicCache();
  }

  static void _injectInitializedDynamicCache() {
    _availableKeys.addAll(DynamicAvailabilityCache.freshKeys);
    for (final entry in DynamicAvailabilityCache.entries) {
      final title = TitleNormalizer.normalize(entry.normalizedTitle);
      if (title.isNotEmpty) {
        _availableTitles.add(title);
        _titleKeysByTitle
            .putIfAbsent(title, () => <String>{})
            .addAll(entry.keys);
      }
      final modes = AnimeModeAvailability(
        hasSub: entry.hasSub,
        hasDub: entry.hasDub,
      );
      for (final key in entry.keys) {
        _availableKeys.add(key);
        _modeKeys[key] = _modeKeys[key]?.merge(modes) ?? modes;
      }
    }
  }

  static Future<void> markAsDynamicallyAvailable(
    String title, {
    int? malId,
    String? providerId,
    String? providerName,
    String? providerTitle,
    bool hasSub = true,
    bool hasDub = false,
  }) async {
    final keys = TitleNormalizer.keysForTitle(title);
    if (keys.isEmpty) return;
    final normalizedTitle = TitleNormalizer.normalize(title);
    await DynamicAvailabilityCache.addEntry(
      DynamicAvailabilityEntry.create(
        title: title,
        keys: keys,
        hasSub: hasSub,
        hasDub: hasDub,
        malId: malId,
        providerId: providerId,
        providerName: providerName,
        providerTitle: providerTitle,
      ),
    );
    _availableTitles.add(normalizedTitle);
    _titleKeysByTitle.update(
      normalizedTitle,
      (existing) => <String>{...existing, ...keys},
      ifAbsent: () => keys.toSet(),
    );
    _availableKeys.addAll(keys);
    final modes = AnimeModeAvailability(hasSub: hasSub, hasDub: hasDub);
    for (final key in keys) {
      _modeKeys[key] = _modeKeys[key]?.merge(modes) ?? modes;
      _discoveryKeyExpirations.remove(key);
    }
    updateNotifier.value++;
  }

  static bool registerDiscoveryCandidate(JikanAnime anime, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    if (!_isRecentDiscoveryCandidate(anime, current)) return false;

    final expiresAt = current.add(_discoveryVisibilityTtl);
    var changed = false;
    for (final title in <String?>[
      anime.title,
      anime.titleEnglish,
      anime.titleJapanese,
      ...anime.titleSynonyms,
    ]) {
      if (title == null || title.trim().isEmpty) continue;
      for (final key in TitleNormalizer.keysForTitle(title)) {
        final existing = _discoveryKeyExpirations[key];
        if (existing == null || !existing.isAfter(current)) {
          _discoveryKeyExpirations[key] = expiresAt;
          changed = true;
        }
      }
    }

    if (changed) updateNotifier.value++;
    return changed;
  }

  static bool _isRecentDiscoveryCandidate(JikanAnime anime, DateTime now) {
    final status = anime.status?.trim().toLowerCase() ?? '';
    if (status.contains('finished')) return false;

    final airedFrom = DateTime.tryParse(anime.airedFromIso ?? '')?.toUtc();
    if (status.contains('not yet') || status.contains('upcoming')) {
      if (airedFrom == null) return false;
      return !airedFrom.isBefore(now.subtract(const Duration(days: 7))) &&
          !airedFrom.isAfter(now.add(_upcomingDiscoveryWindow));
    }

    if (status.contains('currently airing') ||
        status == 'airing' ||
        status.contains('releasing')) {
      return airedFrom == null ||
          !airedFrom.isBefore(now.subtract(_airingDiscoveryWindow));
    }

    if (airedFrom == null ||
        airedFrom.isAfter(now.add(const Duration(days: 1)))) {
      return false;
    }
    return !airedFrom.isBefore(now.subtract(_recentDiscoveryWindow));
  }

  static bool isConfirmedAvailable(
    String title, {
    String? englishTitle,
    String? japaneseTitle,
    String? romajiTitle,
    Iterable<String> synonyms = const [],
    AnimeAvailabilityMode mode = AnimeAvailabilityMode.any,
  }) {
    if (!_isInitialized || _availableKeys.isEmpty) return false;

    if (_matchesConfirmed(title, mode: mode)) return true;
    if (englishTitle != null && _matchesConfirmed(englishTitle, mode: mode)) {
      return true;
    }
    if (japaneseTitle != null && _matchesConfirmed(japaneseTitle, mode: mode)) {
      return true;
    }
    if (romajiTitle != null && _matchesConfirmed(romajiTitle, mode: mode)) {
      return true;
    }
    for (final synonym in synonyms) {
      if (_matchesConfirmed(synonym, mode: mode)) return true;
    }
    return false;
  }

  static bool isAvailable(
    String title, {
    String? englishTitle,
    String? japaneseTitle,
    String? romajiTitle,
    Iterable<String> synonyms = const [],
    AnimeAvailabilityMode mode = AnimeAvailabilityMode.any,
  }) {
    // An unavailable or empty index is an infrastructure failure, not proof
    // that every title is unavailable. Keep catalog/discovery surfaces usable
    // while preserving strict dubbed filtering, which cannot be inferred.
    if (!_isInitialized || _availableKeys.isEmpty) {
      return mode != AnimeAvailabilityMode.dub;
    }

    if (isConfirmedAvailable(
      title,
      englishTitle: englishTitle,
      japaneseTitle: japaneseTitle,
      romajiTitle: romajiTitle,
      synonyms: synonyms,
      mode: mode,
    )) {
      return true;
    }

    if (mode == AnimeAvailabilityMode.dub) return false;
    _pruneDiscoveryCandidates();
    if (_matchesDiscovery(title)) return true;
    if (englishTitle != null && _matchesDiscovery(englishTitle)) return true;
    if (japaneseTitle != null && _matchesDiscovery(japaneseTitle)) return true;
    if (romajiTitle != null && _matchesDiscovery(romajiTitle)) return true;
    return synonyms.any(_matchesDiscovery);
  }

  static Future<bool> isAnimeAvailable(
    JikanAnime anime, {
    AnimeAvailabilityMode mode = AnimeAvailabilityMode.any,
  }) async {
    await initialize();
    await MalAvailabilityService.initialize();

    if (anime.malId > 0 &&
        MalAvailabilityService.entryForMalId(anime.malId) != null) {
      return MalAvailabilityService.isMalIdAvailable(anime.malId, mode: mode);
    }

    return isAvailable(
      anime.title,
      englishTitle: anime.titleEnglish,
      japaneseTitle: anime.titleJapanese,
      synonyms: anime.titleSynonyms,
      mode: mode,
    );
  }

  static Future<bool> isAnimeAvailableStrictByMalId(
    JikanAnime anime, {
    AnimeAvailabilityMode mode = AnimeAvailabilityMode.any,
  }) async {
    if (anime.malId <= 0) return false;
    await MalAvailabilityService.initialize();
    return MalAvailabilityService.isMalIdAvailable(anime.malId, mode: mode);
  }

  /// Checks availability for one provider without treating the global MAL
  /// cache as proof that this provider owns the title.
  static Future<bool> isAnimeAvailableFromProvider(
    JikanAnime anime, {
    required String providerId,
    AnimeAvailabilityMode mode = AnimeAvailabilityMode.any,
  }) async {
    await DynamicAvailabilityCache.initialize();
    await MalProviderAvailabilityService.initialize();
    final titles = <String>[
      anime.title,
      ?anime.titleEnglish,
      ?anime.titleJapanese,
      ...anime.titleSynonyms,
    ];
    final dynamicMode = switch (mode) {
      AnimeAvailabilityMode.any => DynamicAvailabilityMode.any,
      AnimeAvailabilityMode.sub => DynamicAvailabilityMode.sub,
      AnimeAvailabilityMode.dub => DynamicAvailabilityMode.dub,
    };
    if (DynamicAvailabilityCache.isTitleAvailable(
      titles,
      providerId: providerId,
      mode: dynamicMode,
    )) {
      return true;
    }
    if (MalProviderAvailabilityService.isTitleAvailable(
      titles,
      providerId: providerId,
      mode: mode,
    )) {
      return true;
    }
    if (anime.malId <= 0) return false;
    return MalProviderAvailabilityService.isMalIdAvailable(
      anime.malId,
      providerId: providerId,
      mode: mode,
    );
  }

  /// Returns a tri-state result for runtime routing. An incomplete or missing
  /// provider snapshot is intentionally `unknown`, so it cannot hide a live
  /// provider from episode discovery.
  static Future<ProviderAvailabilityDecision>
  providerAvailabilityDecisionForSource(
    JikanAnime anime, {
    required AnimeSource source,
    AnimeAvailabilityMode mode = AnimeAvailabilityMode.any,
  }) async {
    final providerId = providerAvailabilityIdForSource(source);
    if (providerId == null) return ProviderAvailabilityDecision.unknown;

    await DynamicAvailabilityCache.initialize();
    await MalProviderAvailabilityService.initialize();
    final titles = <String>[
      anime.title,
      ?anime.titleEnglish,
      ?anime.titleJapanese,
      ...anime.titleSynonyms,
    ];
    final dynamicMode = switch (mode) {
      AnimeAvailabilityMode.any => DynamicAvailabilityMode.any,
      AnimeAvailabilityMode.sub => DynamicAvailabilityMode.sub,
      AnimeAvailabilityMode.dub => DynamicAvailabilityMode.dub,
    };
    if (DynamicAvailabilityCache.isTitleAvailable(
      titles,
      providerId: providerId,
      mode: dynamicMode,
    )) {
      return ProviderAvailabilityDecision.available;
    }
    if (anime.malId > 0 &&
        MalProviderAvailabilityService.isMalIdAvailable(
          anime.malId,
          providerId: providerId,
          mode: mode,
        )) {
      return ProviderAvailabilityDecision.available;
    }

    final coverage = MalProviderAvailabilityService.catalogCoverageForProvider(
      providerId,
    );
    if (coverage == null || !coverage.isComplete) {
      return ProviderAvailabilityDecision.unknown;
    }

    if (MalProviderAvailabilityService.isTitleAvailable(
      titles,
      providerId: providerId,
      mode: mode,
    )) {
      return ProviderAvailabilityDecision.available;
    }

    // A complete catalog is a positive evidence source, but its absence must
    // not suppress runtime candidates: direct source routes can legitimately
    // exist outside a stale/renamed catalog snapshot. The strict facade above
    // remains available for callers that need a hard false.
    return ProviderAvailabilityDecision.unknown;
  }

  /// Checks provider-specific provenance without exposing generated string IDs
  /// to callers. An aggregate source such as AllAnime returns false because
  /// it does not own an independent catalog snapshot.
  static Future<bool> isAnimeAvailableFromSource(
    JikanAnime anime, {
    required AnimeSource source,
    AnimeAvailabilityMode mode = AnimeAvailabilityMode.any,
  }) async {
    final providerId = providerAvailabilityIdForSource(source);
    if (providerId == null) return false;
    return isAnimeAvailableFromProvider(
      anime,
      providerId: providerId,
      mode: mode,
    );
  }

  static AnimeModeAvailability? modeForTitle(
    String title, {
    String? englishTitle,
    String? japaneseTitle,
    String? romajiTitle,
    Iterable<String> synonyms = const [],
  }) {
    for (final candidate in <String>[
      title,
      ?englishTitle,
      ?japaneseTitle,
      ?romajiTitle,
      ...synonyms,
    ]) {
      final modes = _modeForTitle(candidate);
      if (modes != null) return modes;
    }
    return null;
  }

  static Future<List<String>> searchLocalTitles(
    String query, {
    AnimeAvailabilityMode mode = AnimeAvailabilityMode.any,
    int limit = 20,
  }) async {
    await initialize();

    final normalizedQuery = TitleNormalizer.normalize(query);
    if (normalizedQuery.isEmpty || _availableTitles.isEmpty) {
      return const [];
    }

    final queryTokens = normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toList();
    final matches = <_LocalTitleMatch>[];

    for (final title in _availableTitles) {
      final keys =
          _titleKeysByTitle[title] ?? TitleNormalizer.keysForTitle(title);
      if (!_matchesConfirmedKeys(keys, mode: mode)) continue;
      final score = _scoreLocalTitleMatch(title, normalizedQuery, queryTokens);
      if (score == null) continue;
      matches.add(_LocalTitleMatch(title: title, score: score));
    }

    matches.sort((a, b) {
      final scoreComparison = a.score.compareTo(b.score);
      if (scoreComparison != 0) return scoreComparison;
      final lengthComparison = a.title.length.compareTo(b.title.length);
      if (lengthComparison != 0) return lengthComparison;
      return a.title.compareTo(b.title);
    });

    return matches.take(limit).map((match) => match.title).toList();
  }

  static bool _matchesConfirmed(
    String title, {
    required AnimeAvailabilityMode mode,
  }) {
    return _matchesConfirmedKeys(
      TitleNormalizer.keysForTitle(title),
      mode: mode,
    );
  }

  static bool _matchesConfirmedKeys(
    Iterable<String> keys, {
    required AnimeAvailabilityMode mode,
  }) {
    if (mode == AnimeAvailabilityMode.any) {
      return keys.any(_availableKeys.contains) ||
          keys.any((key) => _availableKeys.contains('$key classico')) ||
          keys.any((key) => _availableKeys.contains('$key classic'));
    }

    final hasModeMatch = keys.any(
      (key) => _modeKeys[key]?.matches(mode) ?? false,
    );
    if (hasModeMatch) return true;

    final hasModeMetadata = keys.any(_modeKeys.containsKey);
    if (mode == AnimeAvailabilityMode.sub && !hasModeMetadata) {
      return keys.any(_availableKeys.contains);
    }
    return false;
  }

  static bool _matchesDiscovery(String title) {
    return TitleNormalizer.keysForTitle(
      title,
    ).any(_discoveryKeyExpirations.containsKey);
  }

  static void _pruneDiscoveryCandidates() {
    final now = DateTime.now().toUtc();
    _discoveryKeyExpirations.removeWhere(
      (_, expiresAt) => !expiresAt.isAfter(now),
    );
  }

  static AnimeModeAvailability? _modeForTitle(String title) {
    for (final key in TitleNormalizer.keysForTitle(title)) {
      final modes = _modeKeys[key];
      if (modes != null) return modes;
    }
    return null;
  }

  static void _replaceCache(Iterable<String> titles) {
    _availableTitles.clear();
    _availableKeys.clear();
    _titleKeysByTitle.clear();
    for (final rawTitle in titles) {
      final title = TitleNormalizer.normalize(rawTitle);
      if (title.isEmpty || !_availableTitles.add(title)) continue;
      final keys = TitleNormalizer.keysForTitle(title);
      _titleKeysByTitle[title] = keys;
      _availableKeys.addAll(keys);
    }
  }

  static int? _scoreLocalTitleMatch(
    String title,
    String normalizedQuery,
    List<String> queryTokens,
  ) {
    final compactTitle = title.replaceAll(' ', '');
    final compactQuery = normalizedQuery.replaceAll(' ', '');

    if (title == normalizedQuery || compactTitle == compactQuery) return 0;
    if (title.startsWith(normalizedQuery) ||
        compactTitle.startsWith(compactQuery)) {
      return 1;
    }
    if (title.contains(normalizedQuery) ||
        compactTitle.contains(compactQuery)) {
      return 2;
    }
    if (queryTokens.every(title.contains)) return 3;
    return null;
  }

  static Future<void> _loadBundledModeCache() async {
    try {
      final jsonString = await rootBundle.loadString(
        'assets/data/available_anime_modes.json',
      );
      _replaceModeCache(jsonDecode(jsonString));
    } catch (e) {
      debugPrint('[AvailabilityService] Error loading bundled mode cache: $e');
    }
  }

  static Future<Object?> _fetchLatestModeCache() async {
    try {
      const url =
          'https://raw.githubusercontent.com/Semogtw/goAnime-mobile/main/assets/data/available_anime_modes.json';
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      debugPrint('[AvailabilityService] Failed to update mode cache: $e');
    }
    return null;
  }

  static void _replaceModeCache(Object? decoded) {
    _modeKeys.clear();
    if (decoded is! Map) return;

    for (final entry in decoded.entries) {
      final title = entry.key;
      if (title is! String) continue;
      final modes = AnimeModeAvailability.fromJson(entry.value);
      for (final key in TitleNormalizer.keysForTitle(title)) {
        _modeKeys[key] = _modeKeys[key]?.merge(modes) ?? modes;
      }
    }
  }

  static void _replaceCacheFromDatabase(
    Iterable<TitleAvailabilityDbEntry> entries,
  ) {
    _availableTitles.clear();
    _availableKeys.clear();
    _modeKeys.clear();
    _titleKeysByTitle.clear();
    for (final entry in entries) {
      final title = TitleNormalizer.normalize(entry.normalizedTitle);
      if (title.isEmpty) continue;
      _availableTitles.add(title);
      final keys = TitleNormalizer.keysForTitle(title);
      _titleKeysByTitle[title] = keys;
      for (final key in keys) {
        _availableKeys.add(key);
        _modeKeys[key] = _modeKeys[key]?.merge(entry.modes) ?? entry.modes;
      }
    }
  }

  @visibleForTesting
  static void debugSetAvailableTitles(
    Iterable<String> titles, {
    Map<String, AnimeModeAvailability> modes = const {},
  }) {
    _cacheGeneration++;
    _replaceCache(titles);
    _replaceModeCache(
      modes.map(
        (title, mode) =>
            MapEntry(title, {'sub': mode.hasSub, 'dub': mode.hasDub}),
      ),
    );
    _discoveryKeyExpirations.clear();
    _isInitialized = true;
    _initializeFuture = null;
    _latestCacheFuture = null;
    _reloadFuture = null;
  }

  @visibleForTesting
  static Future<void> debugLoadTitleDatabaseForTesting(String path) async {
    _cacheGeneration++;
    await TitleAvailabilityDatabaseService.debugSetDatabasePathForTesting(path);
    final entries = await TitleAvailabilityDatabaseService.loadAllEntries();
    _replaceCacheFromDatabase(entries);
    _discoveryKeyExpirations.clear();
    _isInitialized = true;
    _initializeFuture = null;
    _latestCacheFuture = null;
    _reloadFuture = null;
  }

  @visibleForTesting
  static void debugReset() {
    _cacheGeneration++;
    _availableTitles.clear();
    _availableKeys.clear();
    _modeKeys.clear();
    _titleKeysByTitle.clear();
    _discoveryKeyExpirations.clear();
    _isInitialized = false;
    _initializeFuture = null;
    _latestCacheFuture = null;
    _reloadFuture = null;
  }
}

class _LocalTitleMatch {
  final String title;
  final int score;

  const _LocalTitleMatch({required this.title, required this.score});
}
