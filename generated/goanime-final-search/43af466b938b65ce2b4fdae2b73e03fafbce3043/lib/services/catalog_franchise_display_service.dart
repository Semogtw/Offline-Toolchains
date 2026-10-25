import '../models/anime_franchise_models.dart';
import '../models/catalog_display_entry.dart';
import '../models/jikan_models.dart';
import '../utils/anime_deduplication.dart';
import 'anime_franchise_cache_service.dart';
import 'franchise_availability_cache_service.dart';

enum CatalogFranchiseDisplayMode { canonical, latest, source }

class CatalogFranchiseDisplayService {
  final AnimeFranchiseCacheService _cacheService;

  CatalogFranchiseDisplayService({AnimeFranchiseCacheService? cacheService})
    : _cacheService = cacheService ?? AnimeFranchiseCacheService();

  Future<Map<int, AnimeFranchise>> loadIndexedFranchisesFor(
    Iterable<JikanAnime> animes,
  ) {
    return FranchiseAvailabilityCacheService.franchisesForMalIdsAsync(
      animes.map((anime) => anime.malId),
    );
  }

  Future<List<CatalogDisplayEntry>> collapseCachedFranchises(
    List<JikanAnime> animes, {
    CatalogFranchiseDisplayMode mode = CatalogFranchiseDisplayMode.canonical,
    bool suppressIndexedHiddenEntries = false,
    Map<int, AnimeFranchise>? indexedFranchises,
  }) {
    return collapseFranchises(
      animes,
      mode: mode,
      suppressIndexedHiddenEntries: suppressIndexedHiddenEntries,
      indexedFranchises: indexedFranchises,
    );
  }

  Future<List<CatalogDisplayEntry>> collapseFranchises(
    List<JikanAnime> animes, {
    CatalogFranchiseDisplayMode mode = CatalogFranchiseDisplayMode.canonical,
    bool suppressIndexedHiddenEntries = false,
    Map<int, AnimeFranchise>? indexedFranchises,
  }) async {
    if (animes.isEmpty) return const <CatalogDisplayEntry>[];

    final indexedFranchiseByMalId =
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
    final emittedFranchiseIds = <String>{};
    final emittedAnimeIds = <int>{};
    final suppressedLocalTitleKeys = <String>{};
    final suppressedLocalTitlePrefixes = <String>{};

    for (final anime in animes) {
      if (suppressIndexedHiddenEntries &&
          _isSuppressedLocalPlaceholder(
            anime,
            suppressedLocalTitleKeys,
            suppressedLocalTitlePrefixes,
          )) {
        continue;
      }

      final indexedFranchise = anime.malId > 0
          ? indexedFranchiseByMalId[anime.malId]
          : null;
      final cachedFranchise = indexedFranchise == null && anime.malId > 0
          ? cachedFranchiseByMalId[anime.malId]
          : null;
      final franchise = indexedFranchise ?? cachedFranchise;
      final visibleEntries = franchise == null
          ? const <AnimeFranchiseEntry>[]
          : franchise.runtimeVisibleEntries;
      final sourceEntry = visibleEntries
          .where((entry) => entry.malId == anime.malId)
          .firstOrNull;
      if (franchise == null || visibleEntries.length <= 1) {
        if (anime.malId > 0 && !emittedAnimeIds.add(anime.malId)) continue;
        result.add(CatalogDisplayEntry.single(anime));
        continue;
      }

      if (sourceEntry == null) {
        if (suppressIndexedHiddenEntries) continue;
        if (anime.malId > 0 && !emittedAnimeIds.add(anime.malId)) continue;
        result.add(CatalogDisplayEntry.single(anime));
        continue;
      }

      if (!emittedFranchiseIds.add(franchise.franchiseId)) continue;
      emittedAnimeIds.addAll(visibleEntries.map((entry) => entry.malId));
      if (suppressIndexedHiddenEntries) {
        _rememberSuppressedLocalTitles(
          franchise,
          suppressedLocalTitleKeys,
          suppressedLocalTitlePrefixes,
        );
      }
      result.add(
        CatalogDisplayEntry.franchise(
          franchise: franchise,
          anime: _displayAnimeFor(
            franchise,
            anime,
            mode: mode,
            sourceEntry: sourceEntry,
          ),
          selectedMalId: _selectedMalIdFor(
            franchise,
            anime,
            mode,
            sourceEntry: sourceEntry,
          ),
        ),
      );
    }

    if (!suppressIndexedHiddenEntries || suppressedLocalTitleKeys.isEmpty) {
      return result;
    }

    return result
        .where(
          (entry) =>
              entry.type != CatalogDisplayEntryType.singleAnime ||
              !_isSuppressedLocalPlaceholder(
                entry.anime,
                suppressedLocalTitleKeys,
                suppressedLocalTitlePrefixes,
              ),
        )
        .toList();
  }

  JikanAnime _displayAnimeFor(
    AnimeFranchise franchise,
    JikanAnime fallback, {
    required CatalogFranchiseDisplayMode mode,
    AnimeFranchiseEntry? sourceEntry,
  }) {
    final entry = _displayEntryFor(franchise, mode, sourceEntry: sourceEntry);
    final anime = entry?.anime ?? fallback;
    return JikanAnime(
      malId: anime.malId,
      title: franchise.displayTitle.isNotEmpty
          ? franchise.displayTitle
          : anime.title,
      titleEnglish: anime.titleEnglish,
      titleJapanese: anime.titleJapanese,
      titleSynonyms: anime.titleSynonyms,
      imageUrl: franchise.coverImage.isNotEmpty
          ? franchise.coverImage
          : anime.imageUrl.isNotEmpty
          ? anime.imageUrl
          : fallback.imageUrl,
      largImageUrl: anime.largImageUrl ?? fallback.largImageUrl,
      bannerImageUrl: franchise.bannerImage ?? anime.bannerImageUrl,
      synopsis: anime.synopsis ?? fallback.synopsis,
      score: anime.score ?? fallback.score,
      episodes: anime.episodes ?? fallback.episodes,
      nextAiringEpisode: anime.nextAiringEpisode ?? fallback.nextAiringEpisode,
      nextAiringAt: anime.nextAiringAt ?? fallback.nextAiringAt,
      members: anime.members ?? fallback.members,
      status: anime.status ?? fallback.status,
      rating: anime.rating ?? fallback.rating,
      genres: anime.genres.isNotEmpty ? anime.genres : fallback.genres,
      year: anime.year ?? fallback.year,
      season: anime.season ?? fallback.season,
      mediaType: anime.mediaType ?? fallback.mediaType,
      airedFromIso: anime.airedFromIso ?? fallback.airedFromIso,
      airedToIso: anime.airedToIso ?? fallback.airedToIso,
    );
  }

  int _selectedMalIdFor(
    AnimeFranchise franchise,
    JikanAnime fallback,
    CatalogFranchiseDisplayMode mode, {
    AnimeFranchiseEntry? sourceEntry,
  }) {
    return _displayEntryFor(franchise, mode, sourceEntry: sourceEntry)?.malId ??
        fallback.malId;
  }

  AnimeFranchiseEntry? _displayEntryFor(
    AnimeFranchise franchise,
    CatalogFranchiseDisplayMode mode, {
    AnimeFranchiseEntry? sourceEntry,
  }) {
    return switch (mode) {
      CatalogFranchiseDisplayMode.source => sourceEntry,
      CatalogFranchiseDisplayMode.latest =>
        FranchiseAvailabilityCacheService.latestMainlineEntry(franchise),
      CatalogFranchiseDisplayMode.canonical =>
        FranchiseAvailabilityCacheService.canonicalEntry(franchise),
    };
  }

  bool _isSuppressedLocalPlaceholder(
    JikanAnime anime,
    Set<String> suppressedKeys,
    Set<String> suppressedPrefixes,
  ) {
    if (!isWeakLocalAnimePlaceholder(anime)) return false;
    final keys = canonicalTitleMatchKeys(anime.title);
    if (keys.any(suppressedKeys.contains)) return true;
    return keys.any(
      (key) => suppressedPrefixes.any((prefix) => key.startsWith(prefix)),
    );
  }

  void _rememberSuppressedLocalTitles(
    AnimeFranchise franchise,
    Set<String> suppressedKeys,
    Set<String> suppressedPrefixes,
  ) {
    void addTitle(String? title, {bool asPrefix = false}) {
      if (title == null || title.trim().isEmpty) return;
      final keys = canonicalTitleMatchKeys(title);
      suppressedKeys.addAll(keys);
      if (asPrefix) {
        suppressedPrefixes.addAll(keys.map((key) => '$key '));
      }
    }

    addTitle(franchise.displayTitle, asPrefix: true);
    for (final entry in franchise.entries) {
      addTitle(entry.anime.title);
      addTitle(entry.anime.titleEnglish);
      addTitle(entry.anime.titleJapanese);
      for (final synonym in entry.anime.titleSynonyms) {
        addTitle(synonym);
      }
    }
  }
}
