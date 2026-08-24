import 'package:goanime_core/goanime_core.dart';
// ignore_for_file: unawaited_futures
// Existing callbacks/fixtures still rely on implicit async or dynamic JSON shapes; keep new strict rules enabled elsewhere.
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/jikan_models.dart';
import '../models/unified_anime_model.dart';
import 'app_work_coordinator.dart';
import 'availability_service.dart';
import 'episode_tree_cache_service.dart';
import 'media/provider_request_scheduler.dart';
import 'media/request_single_flight.dart';
import 'providers/default_anime_source_providers.dart';
import 'providers/provider_health_ranker.dart';
import 'source/episode_aggregator.dart';
import 'source/episode_cache_repository.dart';
import 'source/provider_matcher.dart';

class UnifiedSourceService {
  static final SingleFlight<String, List<UnifiedEpisode>> _episodeLoads =
      SingleFlight<String, List<UnifiedEpisode>>();
  static final Set<String> _persistentFallbackLoads = {};

  /// PERF-N11: replaces the unbounded attempted-keys set. Bounded map of
  /// prewarm attempt timestamps with cooldown: a failed attempt may be
  /// retried after [_prewarmRetryCooldown], and the oldest entries are
  /// evicted once the cap is reached.
  static final Map<String, DateTime> _prewarmAttemptAt = {};
  static const int _prewarmAttemptCap = 256;
  static const Duration _prewarmRetryCooldown = Duration(minutes: 10);
  static Future<List<UnifiedEpisode>> Function(JikanAnime)?
  _loadAggregatedEpisodesOverride;
  static List<AnimeSourceProvider> _sourceProviders =
      defaultAnimeSourceProviders;
  static bool? _isDesktopOverride;
  static bool get _isDesktop =>
      _isDesktopOverride ?? (Platform.isWindows || Platform.isLinux);
  static int get _maxEpisodeCacheSize => _isDesktop ? 80 : 20;
  static Duration get _episodeCacheTtl =>
      _isDesktop ? const Duration(minutes: 90) : const Duration(minutes: 20);
  static bool get shouldPrewarmEpisodeCache => _isDesktop;
  static int get prewarmLimitForPlatform => _isDesktop ? 6 : 0;
  static int get prewarmConcurrencyForPlatform => _isDesktop ? 2 : 0;
  static const Duration _providerSearchTimeout = Duration(seconds: 12);
  static const Duration _episodeSourceTimeout = Duration(seconds: 14);
  static const ProviderHealthRanker _healthRanker = ProviderHealthRanker();
  static EpisodeCacheRepository _cacheRepository = EpisodeCacheRepository(
    policy: () =>
        CachePolicy(ttl: _episodeCacheTtl, maxEntries: _maxEpisodeCacheSize),
  );
  static final ProviderMatcher _providerMatcher = ProviderMatcher(
    providerSearchTimeout: _providerSearchTimeout,
    providerAvailabilityLookup: (source, anime) =>
        AvailabilityService.providerAvailabilityDecisionForSource(
          anime,
          source: source,
        ),
  );

  static String extractEpisodeNumber(String episodeText) {
    return EpisodeAggregator.extractEpisodeNumber(episodeText);
  }

  static Future<List<UnifiedEpisode>> getAggregatedEpisodes(
    JikanAnime jikanAnime, {
    void Function(List<UnifiedEpisode> snapshot)? onPartialResult,
  }) async {
    final cacheKey = EpisodeCacheRepository.cacheKeyFor(jikanAnime);
    final cached = _cacheRepository.getFreshMemory(cacheKey);
    if (cached != null) return cached;

    final persistentEpisodes = await _readValidPersistentCache(cacheKey);
    if (persistentEpisodes != null) {
      _saveEpisodesToCache(cacheKey, persistentEpisodes);
      return _cloneEpisodes(persistentEpisodes);
    }

    final episodes = await _episodeLoads.run(cacheKey, () async {
      try {
        final loaded = await _loadAggregatedEpisodesWithPersistentFallback(
          cacheKey,
          jikanAnime,
          onPartialResult: onPartialResult,
        );
        final fromPersistentFallback = _persistentFallbackLoads.remove(
          cacheKey,
        );
        _saveEpisodesToCache(cacheKey, loaded);
        if (!fromPersistentFallback) {
          await _savePersistentCache(cacheKey, jikanAnime, loaded);
        }
        return loaded;
      } finally {
        _persistentFallbackLoads.remove(cacheKey);
      }
    });
    return _cloneEpisodes(episodes);
  }

  static Stream<List<UnifiedEpisode>> watchAggregatedEpisodes(
    JikanAnime jikanAnime,
  ) async* {
    final cacheKey = EpisodeCacheRepository.cacheKeyFor(jikanAnime);
    final cached = _cacheRepository.getFreshMemory(cacheKey);
    if (cached != null) {
      yield cached;
      return;
    }

    final persistentEpisodes = await _readValidPersistentCache(cacheKey);
    if (persistentEpisodes != null) {
      _saveEpisodesToCache(cacheKey, persistentEpisodes);
      yield _cloneEpisodes(persistentEpisodes);
      return;
    }

    final staleEpisodes = await _readStalePersistentCache(cacheKey);
    if (staleEpisodes != null) {
      yield _cloneEpisodes(staleEpisodes);
      try {
        final refreshedEpisodes = await _getOrStartFreshLoad(
          cacheKey,
          jikanAnime,
        );
        if (refreshedEpisodes.isNotEmpty &&
            _hasAnyProvider(refreshedEpisodes)) {
          yield _cloneEpisodes(refreshedEpisodes);
        }
      } catch (error) {
        debugPrint('[UnifiedSource] Episode tree refresh failed: $error');
      }
      return;
    }

    final instantPreliminary = EpisodeAggregator.buildPreliminaryEpisodes(
      jikanAnime,
    );
    if (instantPreliminary.isNotEmpty) {
      yield _cloneEpisodes(instantPreliminary);
    }

    final controller = StreamController<List<UnifiedEpisode>>();
    List<UnifiedEpisode>? lastEmitted;
    final loadFuture = getAggregatedEpisodes(
      jikanAnime,
      onPartialResult: (snapshot) {
        lastEmitted = snapshot;
        if (!controller.isClosed) {
          controller.add(_cloneEpisodes(snapshot));
        }
      },
    );
    loadFuture
        .then((_) async {
          if (!controller.isClosed) await controller.close();
        })
        .catchError((Object error, StackTrace stack) async {
          if (!controller.isClosed) controller.addError(error, stack);
          if (!controller.isClosed) await controller.close();
        });

    await for (final partial in controller.stream) {
      yield partial;
    }

    final finalEpisodes = await loadFuture;

    if (finalEpisodes.isNotEmpty) {
      if (lastEmitted == null ||
          !_snapshotsEqual(lastEmitted!, finalEpisodes)) {
        yield _cloneEpisodes(finalEpisodes);
      }
    } else if (instantPreliminary.isNotEmpty) {
      final currentPreliminary =
          EpisodeAggregator.buildCurrentPreliminaryEpisodes(jikanAnime);
      yield currentPreliminary
          .map((episode) => episode.copyWith(isResolving: false))
          .toList();
    }
  }

  static Future<List<UnifiedEpisode>> _getOrStartFreshLoad(
    String cacheKey,
    JikanAnime jikanAnime,
  ) async {
    final episodes = await _episodeLoads.run(cacheKey, () async {
      try {
        final loaded =
            await (_loadAggregatedEpisodesOverride?.call(jikanAnime) ??
                _loadAggregatedEpisodes(jikanAnime));
        _saveEpisodesToCache(cacheKey, loaded);
        await _savePersistentCache(cacheKey, jikanAnime, loaded);
        return loaded;
      } catch (error) {
        await _recordPersistentCacheError(cacheKey, error);
        rethrow;
      }
    });
    return _cloneEpisodes(episodes);
  }

  static Future<UnifiedEpisode?> findEpisodeByNumber(
    JikanAnime jikanAnime,
    int episodeNumber, {
    bool? isDubMode,
  }) async {
    final episodes = await getAggregatedEpisodes(jikanAnime);
    for (final episode in episodes) {
      if (episode.episodeNumber != episodeNumber) continue;
      if (isDubMode == null ||
          episode.getProviders(isSub: !isDubMode).isNotEmpty) {
        return episode;
      }
      return null;
    }
    if (isDubMode != null) return null;
    return episodes.isEmpty ? null : episodes.first;
  }

  static Future<void> prewarmEpisodeCache(
    Iterable<JikanAnime> animes, {
    int? limit,
    int? concurrency,
  }) async {
    if (!shouldPrewarmEpisodeCache) return;
    if (!AppWorkCoordinator.instance.canRunPrewarm) return;

    final resolvedLimit = limit ?? prewarmLimitForPlatform;
    final resolvedConcurrency = concurrency ?? prewarmConcurrencyForPlatform;
    if (resolvedLimit <= 0 || resolvedConcurrency <= 0) return;

    final candidates = <JikanAnime>[];
    final seenKeys = <String>{};
    for (final anime in animes) {
      final cacheKey = EpisodeCacheRepository.cacheKeyFor(anime);
      if (!seenKeys.add(cacheKey)) continue;
      if (_prewarmRecentlyAttempted(cacheKey)) continue;
      final cached = _cacheRepository.getFreshMemory(cacheKey);
      if (cached != null) continue;
      final persistentEpisodes = await _readValidPersistentCache(cacheKey);
      if (persistentEpisodes != null) continue;
      if (_episodeLoads.isRunning(cacheKey)) continue;
      candidates.add(anime);
      if (candidates.length >= resolvedLimit) break;
    }

    for (
      var index = 0;
      index < candidates.length;
      index += resolvedConcurrency
    ) {
      if (!AppWorkCoordinator.instance.canRunPrewarm) return;
      final batch = candidates.skip(index).take(resolvedConcurrency);
      await Future.wait(
        batch.map((anime) {
          _recordPrewarmAttempt(EpisodeCacheRepository.cacheKeyFor(anime));
          return getAggregatedEpisodes(
            anime,
          ).timeout(const Duration(seconds: 24)).catchError((Object e) {
            debugPrint(
              '[UnifiedSource] Desktop prewarm failed for ${anime.title}: $e',
            );
            return <UnifiedEpisode>[];
          });
        }),
      );
    }
  }

  static Future<List<UnifiedEpisode>> _loadAggregatedEpisodes(
    JikanAnime jikanAnime, {
    void Function(List<UnifiedEpisode> snapshot)? onPartialResult,
  }) async {
    final preliminary = EpisodeAggregator.buildCurrentPreliminaryEpisodes(
      jikanAnime,
    );

    debugPrint('[UnifiedSource] Starting aggregation for ${jikanAnime.title}');

    final resolvedByProvider = List<List<UnifiedEpisode>?>.filled(
      _sourceProviders.length,
      null,
    );
    List<UnifiedEpisode>? lastPartial;
    final episodePhaseConcurrency =
        EpisodeAggregator.defaultMaxConcurrentEpisodeLoads;
    final episodePhaseScheduler = ProviderRequestScheduler(
      globalLimit: episodePhaseConcurrency,
      policies: {
        for (final provider in _sourceProviders)
          provider.providerKey: ProviderPolicy(
            providerKey: provider.providerKey,
            maxConcurrent: 1,
            requestTimeout: _episodeSourceTimeout + const Duration(seconds: 2),
          ),
      },
    );

    void publishProviderSnapshot(int index, List<UnifiedEpisode> snapshot) {
      resolvedByProvider[index] = snapshot;
      if (onPartialResult == null) return;

      final resolved = _combineResolvedSnapshots(
        resolvedByProvider.whereType<List<UnifiedEpisode>>(),
      );
      if (resolved.isEmpty) return;
      final merged = EpisodeAggregator.mergePreliminaryWithResolved(
        preliminary,
        resolved,
      );
      if (lastPartial != null && _snapshotsEqual(lastPartial!, merged)) return;
      lastPartial = _cloneEpisodes(merged);
      try {
        onPartialResult(merged);
      } catch (_) {
        // UI/diagnostic callbacks must not break source aggregation.
      }
    }

    Future<void> loadProvider(int index, AnimeSourceProvider provider) async {
      final match = await _providerMatcher.findProviderMatchesForAnime(
        provider,
        jikanAnime,
      );
      final resolved = await episodePhaseScheduler
          .schedule<List<UnifiedEpisode>>(
            providerKey: provider.providerKey,
            priority: RequestPriority.userInitiated,
            operation: () {
              final providerAggregator = EpisodeAggregator(
                episodeSourceTimeout: _episodeSourceTimeout,
                maxConcurrentEpisodeLoads: 1,
              );
              return providerAggregator.aggregate(
                providerMatches: [match],
                preliminary: const [],
                onPartialResult: (snapshot) {
                  publishProviderSnapshot(index, snapshot);
                },
              );
            },
          );
      publishProviderSnapshot(index, resolved);
    }

    // Every matcher starts now; each provider enters its episode phase as soon
    // as its own matcher finishes instead of waiting for the slowest matcher.
    try {
      await Future.wait([
        for (var index = 0; index < _sourceProviders.length; index++)
          loadProvider(index, _sourceProviders[index]),
      ]);
    } finally {
      episodePhaseScheduler.dispose();
    }

    final resolved = _combineResolvedSnapshots(
      resolvedByProvider.whereType<List<UnifiedEpisode>>(),
    );
    return EpisodeAggregator.mergePreliminaryWithResolved(
      preliminary,
      resolved,
    );
  }

  static List<UnifiedEpisode> _combineResolvedSnapshots(
    Iterable<List<UnifiedEpisode>> snapshots,
  ) {
    final byNumber = <int, UnifiedEpisode>{};

    for (final snapshot in snapshots) {
      for (final incoming in snapshot) {
        final current = byNumber[incoming.episodeNumber];
        if (current == null) {
          byNumber[incoming.episodeNumber] = UnifiedEpisode(
            episodeNumber: incoming.episodeNumber,
            title: incoming.title,
            thumbnail: incoming.thumbnail,
            isResolving: false,
            providers: incoming.providers
                .map(
                  (provider) => EpisodeProvider(
                    source: provider.source,
                    url: provider.url,
                    isSub: provider.isSub,
                  ),
                )
                .toList(),
          );
          continue;
        }

        current.title = _bestEpisodeTitle(current.title, incoming.title);
        final incomingThumbnail = incoming.thumbnail?.trim();
        if (incomingThumbnail != null && incomingThumbnail.isNotEmpty) {
          current.thumbnail = _bestMetadataValue(
            current.thumbnail,
            incomingThumbnail,
          );
        }
        for (final provider in incoming.providers) {
          final duplicate = current.providers.any(
            (existing) =>
                existing.source == provider.source &&
                existing.isSub == provider.isSub &&
                existing.url.trim() == provider.url.trim(),
          );
          if (!duplicate) {
            current.providers.add(
              EpisodeProvider(
                source: provider.source,
                url: provider.url,
                isSub: provider.isSub,
              ),
            );
          }
        }
      }
    }

    final combined = byNumber.values.toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    for (final episode in combined) {
      episode.providers.sort(_providerSort);
    }
    return combined;
  }

  static int _providerSort(EpisodeProvider a, EpisodeProvider b) {
    final healthCompare = _healthRanker.compare(
      a.source,
      b.source,
      ProviderHealthOperation.episodes,
    );
    if (healthCompare != 0) return healthCompare;

    final aPriority = defaultAnimeSourcePriority(a.source);
    final bPriority = defaultAnimeSourcePriority(b.source);
    if (aPriority != bPriority) return aPriority.compareTo(bPriority);

    if (a.isSub && !b.isSub) return -1;
    if (!a.isSub && b.isSub) return 1;
    return a.url.compareTo(b.url);
  }

  static String _bestEpisodeTitle(String? current, String resolved) {
    final trimmed = resolved.trim();
    if (trimmed.isEmpty) return current ?? resolved;
    final existing = current?.trim() ?? '';
    if (existing.isEmpty) return trimmed;

    final existingRank = _episodeTitleRank(existing);
    final resolvedRank = _episodeTitleRank(trimmed);
    if (existingRank != resolvedRank) {
      return existingRank > resolvedRank ? existing : trimmed;
    }
    return existing.toLowerCase().compareTo(trimmed.toLowerCase()) <= 0
        ? existing
        : trimmed;
  }

  static int _episodeTitleRank(String value) {
    if (int.tryParse(value) != null) return 0;
    if (RegExp(
      r'^(?:episode|epis[oó]dio|ep\.?)\s*\d+$',
      caseSensitive: false,
    ).hasMatch(value)) {
      return 1;
    }
    return 2;
  }

  static String _bestMetadataValue(String? current, String incoming) {
    final existing = current?.trim() ?? '';
    if (existing.isEmpty) return incoming;
    return existing.toLowerCase().compareTo(incoming.toLowerCase()) <= 0
        ? existing
        : incoming;
  }

  static Future<List<UnifiedEpisode>>
  _loadAggregatedEpisodesWithPersistentFallback(
    String cacheKey,
    JikanAnime jikanAnime, {
    void Function(List<UnifiedEpisode> snapshot)? onPartialResult,
  }) async {
    try {
      final episodes =
          await (_loadAggregatedEpisodesOverride?.call(jikanAnime) ??
              _loadAggregatedEpisodes(
                jikanAnime,
                onPartialResult: onPartialResult,
              ));
      if (episodes.isEmpty) {
        final staleEpisodes = await _readStalePersistentCache(cacheKey);
        if (staleEpisodes != null) {
          _persistentFallbackLoads.add(cacheKey);
          return staleEpisodes;
        }
        return episodes;
      }
      return episodes;
    } catch (error) {
      await _recordPersistentCacheError(cacheKey, error);
      final staleEpisodes = await _readStalePersistentCache(cacheKey);
      if (staleEpisodes != null) {
        _persistentFallbackLoads.add(cacheKey);
        return staleEpisodes;
      }
      rethrow;
    }
  }

  static Future<List<UnifiedEpisode>?> _readValidPersistentCache(
    String cacheKey,
  ) async {
    return _cacheRepository.readValidPersistent(cacheKey);
  }

  static Future<List<UnifiedEpisode>?> _readStalePersistentCache(
    String cacheKey,
  ) async {
    return _cacheRepository.readStalePersistent(cacheKey);
  }

  static Future<void> _savePersistentCache(
    String cacheKey,
    JikanAnime anime,
    List<UnifiedEpisode> episodes,
  ) async {
    await _cacheRepository.savePersistent(cacheKey, anime, episodes);
  }

  static Future<void> _recordPersistentCacheError(
    String cacheKey,
    Object error,
  ) async {
    await _cacheRepository.recordPersistentError(cacheKey, error);
  }

  static void _saveEpisodesToCache(
    String cacheKey,
    List<UnifiedEpisode> episodes,
  ) {
    _cacheRepository.saveMemory(cacheKey, episodes);
  }

  static List<UnifiedEpisode> _cloneEpisodes(List<UnifiedEpisode> episodes) {
    return EpisodeCacheRepository.cloneEpisodes(episodes);
  }

  static bool _hasAnyProvider(List<UnifiedEpisode> episodes) {
    return EpisodeCacheRepository.hasAnyProvider(episodes);
  }

  static bool _snapshotsEqual(List<UnifiedEpisode> a, List<UnifiedEpisode> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ea = a[i];
      final eb = b[i];
      if (ea.episodeNumber != eb.episodeNumber) return false;
      if (ea.title != eb.title) return false;
      if (ea.thumbnail != eb.thumbnail) return false;
      if (ea.providers.length != eb.providers.length) return false;
      for (var j = 0; j < ea.providers.length; j++) {
        final pa = ea.providers[j];
        final pb = eb.providers[j];
        if (pa.source != pb.source ||
            pa.isSub != pb.isSub ||
            pa.url != pb.url) {
          return false;
        }
      }
    }
    return true;
  }

  @visibleForTesting
  static List<UnifiedEpisode> debugBuildPreliminaryEpisodes(JikanAnime anime) {
    return EpisodeAggregator.buildPreliminaryEpisodes(anime);
  }

  @visibleForTesting
  static List<UnifiedEpisode> debugBuildCurrentPreliminaryEpisodes(
    JikanAnime anime,
  ) {
    return EpisodeAggregator.buildCurrentPreliminaryEpisodes(anime);
  }

  @visibleForTesting
  static List<UnifiedEpisode> debugMergePreliminaryWithResolved(
    List<UnifiedEpisode> preliminary,
    List<UnifiedEpisode> resolved,
  ) {
    return EpisodeAggregator.mergePreliminaryWithResolved(
      preliminary,
      resolved,
    );
  }

  @visibleForTesting
  static Anime? debugBestSourceMatch(String title, List<Anime> results) {
    return ProviderMatcher.bestSourceMatch(title, results);
  }

  @visibleForTesting
  static bool debugIsDubEpisode(Anime anime, Episode episode) {
    return EpisodeAggregator.isDubEpisode(anime, episode);
  }

  @visibleForTesting
  static void debugResetCache() {
    _cacheRepository.clear();
    _episodeLoads.clear();
    _persistentFallbackLoads.clear();
    _prewarmAttemptAt.clear();
    _cacheRepository = EpisodeCacheRepository(
      policy: () =>
          CachePolicy(ttl: _episodeCacheTtl, maxEntries: _maxEpisodeCacheSize),
    );
    _loadAggregatedEpisodesOverride = null;
    _sourceProviders = defaultAnimeSourceProviders;
    _isDesktopOverride = null;
  }

  @visibleForTesting
  static String debugCacheKeyFor(JikanAnime anime) {
    return EpisodeCacheRepository.cacheKeyFor(anime);
  }

  @visibleForTesting
  static void debugSetEpisodeTreeCacheService(EpisodeTreeCacheService service) {
    _cacheRepository.setEpisodeTreeCacheService(service);
  }

  @visibleForTesting
  static void debugSetLoadAggregatedEpisodesOverride(
    Future<List<UnifiedEpisode>> Function(JikanAnime)? load,
  ) {
    _loadAggregatedEpisodesOverride = load;
  }

  @visibleForTesting
  static void debugSetSourceProviders(List<AnimeSourceProvider> providers) {
    _sourceProviders = providers;
  }

  @visibleForTesting
  static void debugSetIsDesktopOverride(bool? isDesktop) {
    _isDesktopOverride = isDesktop;
  }

  static bool _prewarmRecentlyAttempted(String cacheKey) {
    final attemptAt = _prewarmAttemptAt[cacheKey];
    if (attemptAt == null) return false;
    return DateTime.now().difference(attemptAt) < _prewarmRetryCooldown;
  }

  static void _recordPrewarmAttempt(String cacheKey) {
    final existed = _prewarmAttemptAt.containsKey(cacheKey);
    if (!existed) {
      while (_prewarmAttemptAt.length >= _prewarmAttemptCap) {
        final oldestKey = _prewarmAttemptAt.keys.first;
        _prewarmAttemptAt.remove(oldestKey);
      }
    }
    _prewarmAttemptAt.remove(cacheKey);
    _prewarmAttemptAt[cacheKey] = DateTime.now();
  }
}
