import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:goanime_core/goanime_core.dart';

import '../../models/jikan_models.dart';
import '../../models/unified_anime_model.dart';
import '../media/provider_request_scheduler.dart';
import '../providers/default_anime_source_providers.dart';
import '../providers/provider_health_classifier.dart';
import '../providers/provider_health_ranker.dart';
import '../providers/provider_health_service.dart';
import 'provider_matcher.dart';

class EpisodeAggregator {
  EpisodeAggregator({
    this.episodeSourceTimeout = const Duration(seconds: 14),
    this.onHealthSample,
    this.maxConcurrentEpisodeLoads = defaultMaxConcurrentEpisodeLoads,
  });

  final Duration episodeSourceTimeout;
  final ProviderHealthSampleReporter? onHealthSample;

  /// PERF-N01: upper bound on simultaneous provider episode loads during
  /// aggregation. Replaces the previous unbounded Future.wait over every
  /// candidate (confirmed matches plus direct guesses) which could fire
  /// dozens of parallel HTML fetches for a single anime open.
  static const int defaultMaxConcurrentEpisodeLoads = 4;

  /// Tunable at construction for tests or platform-specific policies.
  final int maxConcurrentEpisodeLoads;

  static const ProviderHealthRanker _healthRanker = ProviderHealthRanker();

  static final List<RegExp> _episodePatterns = [
    RegExp(r'Episódio\s*(\d+)', caseSensitive: false),
    RegExp(r'Episode\s*(\d+)', caseSensitive: false),
    RegExp(r'Ep\.?\s*(\d+)', caseSensitive: false),
    RegExp(r'-\s*(\d+)$'),
    RegExp(r'\b(\d+)\b'),
    RegExp(r'\d+'),
  ];

  static String extractEpisodeNumber(String episodeText) {
    if (episodeText.isEmpty) return '';
    final patterns = _episodePatterns;

    for (final pattern in patterns) {
      final match = pattern.firstMatch(episodeText);
      if (match != null) {
        return match.group(1) ?? match.group(0) ?? '';
      }
    }
    return episodeText;
  }

  static bool isDubEpisode(Anime anime, Episode episode) {
    final explicitMode = episode.isDub;
    if (explicitMode != null) return explicitMode;

    return _containsDubMarker(anime.name) ||
        _containsDubMarker(anime.url) ||
        _containsDubMarker(episode.url) ||
        _containsDubMarker(episode.title ?? '') ||
        _containsDubMarker(episode.number);
  }

  static bool _containsDubMarker(String value) {
    return value.toLowerCase().contains('dublado');
  }

  static List<UnifiedEpisode> buildPreliminaryEpisodes(JikanAnime anime) {
    return buildPreliminaryEpisodesForCount(anime, anime.episodes);
  }

  static List<UnifiedEpisode> buildCurrentPreliminaryEpisodes(
    JikanAnime anime,
  ) {
    return buildPreliminaryEpisodesForCount(anime, releasedEpisodeCount(anime));
  }

  static int? releasedEpisodeCount(JikanAnime anime) {
    final total = anime.episodes;
    final nextEpisode = anime.nextAiringEpisode;
    if (nextEpisode != null) {
      final released = nextEpisode - 1;
      if (released <= 0) return 0;
      if (total != null && total > 0 && released > total) return total;
      return released;
    }

    final status = anime.status?.toLowerCase() ?? '';
    if (status.contains('not yet') ||
        status.contains('not_yet') ||
        status.contains('upcoming')) {
      return 0;
    }
    if (status.contains('finished') || status.contains('complete')) {
      return total;
    }
    if (status.contains('airing') || status.contains('releasing')) {
      return null;
    }
    return total;
  }

  Future<List<UnifiedEpisode>> aggregate({
    required List<ProviderAnimeMatches> providerMatches,
    required List<UnifiedEpisode> preliminary,
    void Function(List<UnifiedEpisode> snapshot)? onPartialResult,
  }) async {
    final aggregated = <int, UnifiedEpisode>{};
    Map<int, Set<String>> lastEmittedFingerprint = {};

    String providerKey(EpisodeProvider provider) =>
        '${provider.source.name}|${provider.isSub}|${provider.url.trim()}';

    Map<int, Set<String>> currentFingerprint() {
      final map = <int, Set<String>>{};
      for (final entry in aggregated.entries) {
        map[entry.key] = entry.value.providers.map(providerKey).toSet();
      }
      return map;
    }

    bool hasUsefulChange(
      Map<int, Set<String>> previous,
      Map<int, Set<String>> current,
    ) {
      if (current.isEmpty) return false;
      if (previous.isEmpty) return true;
      if (current.length != previous.length) {
        for (final key in current.keys) {
          if (!previous.containsKey(key)) return true;
        }
      }
      for (final entry in current.entries) {
        final previousSet = previous[entry.key];
        if (previousSet == null) return true;
        if (entry.value.length != previousSet.length) {
          for (final provider in entry.value) {
            if (!previousSet.contains(provider)) return true;
          }
        } else {
          for (final provider in entry.value) {
            if (!previousSet.contains(provider)) return true;
          }
        }
      }
      return false;
    }

    List<UnifiedEpisode> buildSnapshot() {
      final unifiedList = aggregated.values.toList()
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      for (final unifiedEp in unifiedList) {
        unifiedEp.providers.sort(_providerSort);
      }
      final merged = mergePreliminaryWithResolved(preliminary, unifiedList);
      return merged
          .map(
            (episode) => UnifiedEpisode(
              episodeNumber: episode.episodeNumber,
              title: episode.title,
              thumbnail: episode.thumbnail,
              isResolving: episode.isResolving,
              loadError: episode.loadError,
              providers: episode.providers
                  .map(
                    (provider) => EpisodeProvider(
                      source: provider.source,
                      url: provider.url,
                      isSub: provider.isSub,
                    ),
                  )
                  .toList(),
            ),
          )
          .toList();
    }

    void tryEmitPartial() {
      if (onPartialResult == null) return;
      final current = currentFingerprint();
      if (!hasUsefulChange(lastEmittedFingerprint, current)) return;
      final snapshot = buildSnapshot();
      lastEmittedFingerprint = current;
      try {
        onPartialResult(snapshot);
      } catch (_) {
        // Diagnostics/caller errors must never break aggregation.
      }
    }

    bool sameProviderIdentity(EpisodeProvider a, EpisodeProvider b) {
      return a.source == b.source &&
          a.isSub == b.isSub &&
          a.url.trim() == b.url.trim();
    }

    void addEpisode(Episode ep, AnimeSource source, bool isSub) {
      final epNumStr = extractEpisodeNumber(ep.number);
      final epNum = int.tryParse(epNumStr);
      if (epNum == null) return;

      final episodeTitle = ep.title?.trim() ?? '';
      final episodeThumbnail = ep.thumbnail?.trim();

      final provider = EpisodeProvider(
        source: source,
        url: ep.url,
        isSub: isSub,
      );

      final current = aggregated[epNum];
      if (current == null) {
        aggregated[epNum] = UnifiedEpisode(
          episodeNumber: epNum,
          title: episodeTitle.isEmpty ? epNum.toString() : episodeTitle,
          thumbnail: episodeThumbnail,
          providers: [provider],
        );
        return;
      }

      current.title = _bestEpisodeTitle(current.title, episodeTitle);
      if (episodeThumbnail != null && episodeThumbnail.isNotEmpty) {
        current.thumbnail = _bestMetadataValue(
          current.thumbnail,
          episodeThumbnail,
        );
      }

      final duplicate = current.providers.any(
        (existing) => sameProviderIdentity(existing, provider),
      );
      if (!duplicate) current.providers.add(provider);
    }

    Future<void> loadProviderEpisodes(
      ProviderAnimeMatches match,
      Anime anime,
    ) async {
      final stopwatch = Stopwatch()..start();
      try {
        final episodes = await match.provider
            .getEpisodes(anime)
            .timeout(episodeSourceTimeout);
        stopwatch.stop();

        for (final episode in episodes) {
          final isDub = isDubEpisode(anime, episode);
          addEpisode(episode, match.provider.source, !isDub);
        }
        final isDub = episodes.any((episode) => isDubEpisode(anime, episode));
        debugPrint(
          '[UnifiedSource] ${match.provider.name} (${isDub ? "Dub" : "Sub"}) yielded ${episodes.length} eps',
        );

        if (episodes.isEmpty) {
          _reportNoResult(match.provider.source, stopwatch.elapsed);
        } else {
          _reportSuccess(match.provider.source, stopwatch.elapsed);
        }
      } catch (error) {
        stopwatch.stop();
        _reportError(match.provider.source, error, stopwatch.elapsed);
        debugPrint(
          '[UnifiedSource] ${match.provider.name} episodes error: $error',
        );
      }
    }

    final confirmedJobs = <({ProviderAnimeMatches match, Anime anime})>[];
    final directJobs = <({ProviderAnimeMatches match, Anime anime})>[];

    for (final match in providerMatches) {
      for (var index = 0; index < match.animes.length; index++) {
        final job = (match: match, anime: match.animes[index]);
        if (match.isDirectCandidate(index)) {
          directJobs.add(job);
        } else {
          confirmedJobs.add(job);
        }
      }
    }

    final concurrency = maxConcurrentEpisodeLoads < 1
        ? 1
        : maxConcurrentEpisodeLoads;
    final scheduler = ProviderRequestScheduler(
      globalLimit: concurrency,
      policies: {
        for (final match in providerMatches)
          match.provider.providerKey: ProviderPolicy(
            providerKey: match.provider.providerKey,
            maxConcurrent: concurrency,
            requestTimeout: episodeSourceTimeout + const Duration(seconds: 1),
          ),
      },
    );

    Future<void> runJobs(
      List<({ProviderAnimeMatches match, Anime anime})> jobs, {
      required RequestPriority priority,
    }) async {
      await Future.wait([
        for (final job in jobs)
          scheduler.schedule<void>(
            providerKey: job.match.provider.providerKey,
            priority: priority,
            operation: () async {
              await loadProviderEpisodes(job.match, job.anime);
              tryEmitPartial();
            },
          ),
      ]);
    }

    await runJobs(confirmedJobs, priority: RequestPriority.userInitiated);

    ({bool hasSub, bool hasDub}) providerModeCoverage(
      ProviderAnimeMatches match,
    ) {
      var hasSub = false;
      var hasDub = false;
      for (final episode in aggregated.values) {
        for (final provider in episode.providers) {
          if (provider.source != match.provider.source ||
              provider.url.trim().isEmpty) {
            continue;
          }
          if (provider.isSub) {
            hasSub = true;
          } else {
            hasDub = true;
          }
          if (hasSub && hasDub) return (hasSub: true, hasDub: true);
        }
      }
      return (hasSub: hasSub, hasDub: hasDub);
    }

    bool hasExplicitDubDirectCandidate(ProviderAnimeMatches match) {
      for (final index in match.directCandidateIndexes) {
        if (index < 0 || index >= match.animes.length) continue;
        final anime = match.animes[index];
        if (_containsDubMarker(anime.name) || _containsDubMarker(anime.url)) {
          return true;
        }
      }
      return false;
    }

    bool directCandidateFillsGap(
      ({ProviderAnimeMatches match, Anime anime}) job,
    ) {
      final coverage = providerModeCoverage(job.match);
      if (!coverage.hasSub && !coverage.hasDub) return true;

      final candidateIsExplicitDub =
          _containsDubMarker(job.anime.name) ||
          _containsDubMarker(job.anime.url);
      if (candidateIsExplicitDub) return !coverage.hasDub;
      if (!coverage.hasSub) return true;

      // Some providers expose a single generic direct page that can contain
      // both modes. When no explicit dub direct candidate exists, keep that
      // generic fallback eligible while dub coverage is still missing.
      return !coverage.hasDub && !hasExplicitDubDirectCandidate(job.match);
    }

    // Direct guesses are still fallbacks, but the gap is mode-aware. The old
    // any-episode predicate skipped a DUB guess as soon as the same source had
    // one SUB episode (and vice versa), silently reducing source completeness.
    final gapJobs = directJobs.where(directCandidateFillsGap).toList();
    try {
      await runJobs(gapJobs, priority: RequestPriority.prefetch);
    } finally {
      scheduler.dispose();
    }

    final unifiedList = aggregated.values.toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));

    for (final unifiedEp in unifiedList) {
      unifiedEp.providers.sort(_providerSort);
    }
    return mergePreliminaryWithResolved(preliminary, unifiedList);
  }

  Future<List<UnifiedEpisode>> aggregateIncremental({
    required List<ProviderAnimeMatches> providerMatches,
    required List<UnifiedEpisode> preliminary,
    required void Function(List<UnifiedEpisode> snapshot) onPartialResult,
  }) {
    return aggregate(
      providerMatches: providerMatches,
      preliminary: preliminary,
      onPartialResult: onPartialResult,
    );
  }

  Stream<List<UnifiedEpisode>> aggregateIncrementalStream({
    required List<ProviderAnimeMatches> providerMatches,
    required List<UnifiedEpisode> preliminary,
  }) async* {
    final controller = StreamController<List<UnifiedEpisode>>();
    List<UnifiedEpisode>? lastForwarded;
    final aggregation = aggregate(
      providerMatches: providerMatches,
      preliminary: preliminary,
      onPartialResult: (snapshot) {
        lastForwarded = snapshot;
        if (!controller.isClosed) controller.add(snapshot);
      },
    );
    unawaited(
      aggregation
          .then((finalSnapshot) {
            if (controller.isClosed) return;
            if (lastForwarded == null ||
                !_snapshotsEqual(lastForwarded!, finalSnapshot)) {
              controller.add(finalSnapshot);
            }
          })
          .catchError((Object error, StackTrace stack) {
            if (!controller.isClosed) controller.addError(error, stack);
          })
          .whenComplete(() {
            if (!controller.isClosed) unawaited(controller.close());
          }),
    );

    await for (final snapshot in controller.stream) {
      yield snapshot;
    }

    await aggregation;
  }

  bool _snapshotsEqual(List<UnifiedEpisode> a, List<UnifiedEpisode> b) {
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

  void _reportSuccess(AnimeSource source, Duration elapsed) {
    _report(
      ProviderHealthClassifier.success(
        source: source,
        operation: ProviderHealthOperation.episodes,
        elapsed: elapsed,
      ),
    );
  }

  void _reportNoResult(AnimeSource source, Duration elapsed) {
    _report(
      ProviderHealthSample(
        source: source,
        operation: ProviderHealthOperation.episodes,
        outcome: ProviderHealthOutcome.noResult,
        elapsed: elapsed,
      ),
    );
  }

  void _reportError(AnimeSource source, Object error, Duration elapsed) {
    _report(
      ProviderHealthClassifier.sampleForError(
        source: source,
        operation: ProviderHealthOperation.episodes,
        error: error,
        elapsed: elapsed,
      ),
    );
  }

  void _report(ProviderHealthSample sample) {
    final reporter = onHealthSample ?? ProviderHealthService.instance.record;
    try {
      reporter(sample);
    } catch (_) {
      // Diagnostics must never change episode fallback behavior.
    }
  }

  static List<UnifiedEpisode> buildPreliminaryEpisodesForCount(
    JikanAnime anime,
    int? count,
  ) {
    if (count == null || count <= 0 || count > 2000) return const [];

    return List.generate(count, (index) {
      final episodeNumber = index + 1;
      return UnifiedEpisode(
        episodeNumber: episodeNumber,
        title: 'Episódio $episodeNumber',
        thumbnail: anime.imageUrl.isNotEmpty ? anime.imageUrl : null,
        isResolving: true,
        providers: const [],
      );
    });
  }

  static List<UnifiedEpisode> mergePreliminaryWithResolved(
    List<UnifiedEpisode> preliminary,
    List<UnifiedEpisode> resolved,
  ) {
    if (preliminary.isEmpty) {
      return resolved
          .map((episode) => episode.copyWith(isResolving: false))
          .toList();
    }

    final byNumber = <int, UnifiedEpisode>{
      for (final episode in preliminary) episode.episodeNumber: episode,
    };

    for (final episode in resolved) {
      final existing = byNumber[episode.episodeNumber];
      byNumber[episode.episodeNumber] = UnifiedEpisode(
        episodeNumber: episode.episodeNumber,
        title: _bestEpisodeTitle(existing?.title, episode.title),
        thumbnail: episode.thumbnail ?? existing?.thumbnail,
        isResolving: false,
        providers: episode.providers,
      );
    }

    return byNumber.values.toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
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
}
