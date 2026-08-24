part of 'home_screen.dart';

extension _HomeScreenData on _HomeScreenState {
  void _startBannerRotation() {
    _bannerRotationTimer?.cancel();

    if (_seasonAnimes.isEmpty) return;

    _bannerRotationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion ||
          !_bannerPageController.hasClients ||
          _seasonAnimes.isEmpty) {
        return;
      }

      final bannerCount = _seasonAnimes.length.clamp(1, 5);
      final nextIndex = (_currentBannerIndex + 1) % bannerCount;
      unawaited(
        _bannerPageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  /// Compatibility entry point for existing retry callbacks. The shared
  /// controller is the sole owner of catalog cache/fresh lifecycle now.
  Future<void> _loadAllData({bool forceRefresh = false}) {
    _dataLoaded = true;
    return forceRefresh
        ? _homeController.refresh()
        : _homeController.loadInitial();
  }

  void _afterHomeSnapshotApplied(HomeData homeData) {
    unawaited(_collapseCachedHomeSections());
    unawaited(_loadCachedHeroBannerArtwork());
    unawaited(_loadHeroBannerArtwork());
    _precacheBannerImages();
    _prewarmDesktopEpisodeCache(homeData);
    _startBannerRotation();
  }

  /// Audit fix: consumes the pending-availability flag recorded by
  /// `_onAvailabilityUpdated` while a load/refresh was running. Safe to call
  /// on every terminal path: it only collapses when an event was actually
  /// dropped, and the collapse itself is single-flight.
  void _consumeAvailabilityChangeDuringLoad() {
    if (!mounted || !_availabilityChangePendingCollapse) return;
    _availabilityChangePendingCollapse = false;
    if (!_hasUsableContent) return;
    unawaited(_collapseCachedHomeSections());
  }

  void _applyHomeData(HomeData homeData) {
    final bannerCount = homeData.seasonAnimes.length > 5
        ? 5
        : homeData.seasonAnimes.length;
    final nextBannerIndex = bannerCount == 0
        ? 0
        : _currentBannerIndex.clamp(0, bannerCount - 1).toInt();

    setState(() {
      _seasonAnimes = homeData.seasonAnimes;
      _todaysReleases = homeData.todaysReleases;
      _topAnimes = homeData.topAnimes;
      _actionAnimes = homeData.actionAnimes;
      _romanceAnimes = homeData.romanceAnimes;
      _comedyAnimes = homeData.comedyAnimes;
      _fantasyAnimes = homeData.fantasyAnimes;
      _seasonEntries = _singleEntries(homeData.seasonAnimes);
      _todaysEntries = _singleEntries(homeData.todaysReleases);
      _topEntries = _singleEntries(homeData.topAnimes);
      _actionEntries = _singleEntries(homeData.actionAnimes);
      _romanceEntries = _singleEntries(homeData.romanceAnimes);
      _comedyEntries = _singleEntries(homeData.comedyAnimes);
      _fantasyEntries = _singleEntries(homeData.fantasyAnimes);
      _currentBannerIndex = nextBannerIndex;
    });

    if (bannerCount == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_bannerPageController.hasClients) return;
      final currentBannerCount = _seasonAnimes.length > 5
          ? 5
          : _seasonAnimes.length;
      if (currentBannerCount == 0) return;
      final safeIndex = _currentBannerIndex
          .clamp(0, currentBannerCount - 1)
          .toInt();
      final page = _bannerPageController.page;
      if (page != null && page.round() == safeIndex) return;
      _bannerPageController.jumpToPage(safeIndex);
    });
  }

  List<CatalogDisplayEntry> _singleEntries(List<JikanAnime> animes) {
    return animes.map(CatalogDisplayEntry.single).toList();
  }

  /// PERF-N04: single-flight + rerun-once coalescing for availability-driven
  /// recollapses. A notification storm collapses sections once; if further
  /// events arrive while a collapse is running, exactly one extra run is
  /// queued so the final state still reflects every event.
  Future<void> _collapseCachedHomeSections() {
    final running = _homeCollapseInFlight;
    if (running != null) {
      _homeCollapseRerunRequested = true;
      return running;
    }
    final future = _runCollapseCachedHomeSections().whenComplete(() {
      _homeCollapseInFlight = null;
      if (_homeCollapseRerunRequested) {
        _homeCollapseRerunRequested = false;
        unawaited(_collapseCachedHomeSections());
      }
    });
    _homeCollapseInFlight = future;
    return future;
  }

  Future<void> _runCollapseCachedHomeSections() async {
    final generation = ++_homeCollapseGeneration;
    try {
      final sections = <List<JikanAnime>>[
        _seasonAnimes,
        _todaysReleases,
        _topAnimes,
        _actionAnimes,
        _romanceAnimes,
        _comedyAnimes,
        _fantasyAnimes,
      ];
      final indexedFranchises = await _catalogDisplayService
          .loadIndexedFranchisesFor(sections.expand((section) => section));
      final collapsed = await Future.wait<List<CatalogDisplayEntry>>([
        _catalogDisplayService.collapseCachedFranchises(
          _seasonAnimes,
          mode: CatalogFranchiseDisplayMode.source,
          indexedFranchises: indexedFranchises,
        ),
        _catalogDisplayService.collapseCachedFranchises(
          _todaysReleases,
          mode: CatalogFranchiseDisplayMode.source,
          indexedFranchises: indexedFranchises,
        ),
        _catalogDisplayService.collapseCachedFranchises(
          _topAnimes,
          indexedFranchises: indexedFranchises,
        ),
        _catalogDisplayService.collapseCachedFranchises(
          _actionAnimes,
          indexedFranchises: indexedFranchises,
        ),
        _catalogDisplayService.collapseCachedFranchises(
          _romanceAnimes,
          indexedFranchises: indexedFranchises,
        ),
        _catalogDisplayService.collapseCachedFranchises(
          _comedyAnimes,
          indexedFranchises: indexedFranchises,
        ),
        _catalogDisplayService.collapseCachedFranchises(
          _fantasyAnimes,
          indexedFranchises: indexedFranchises,
        ),
      ]);
      if (!mounted || generation != _homeCollapseGeneration) return;

      setState(() {
        _seasonEntries = collapsed[0];
        _todaysEntries = collapsed[1];
        _topEntries = collapsed[2];
        _actionEntries = collapsed[3];
        _romanceEntries = collapsed[4];
        _comedyEntries = collapsed[5];
        _fantasyEntries = collapsed[6];
      });
    } catch (error) {
      debugPrint('[Home] Franchise collapse failed: $error');
    }
  }

  /// PERF-N05: single-flight wrapper. When a load is already running, later
  /// callers await the same in-flight future instead of re-reading storage;
  /// a finished (or failed) load clears the guard so explicit refreshes still
  /// run fresh work.
  ///
  /// Audit fix: [forceRefresh] callers (returning from the player, where the
  /// user may just have changed history) never join a read that started
  /// earlier — they queue exactly one trailing re-read, mirroring the
  /// PERF-N04 collapse coalescing.
  Future<void> _loadContinueWatching({bool forceRefresh = false}) {
    final inFlight = _continueWatchingLoadInFlight;
    if (inFlight != null) {
      if (forceRefresh) _continueWatchingRerunRequested = true;
      return inFlight;
    }
    final future = _drainContinueWatchingLoads();
    _continueWatchingLoadInFlight = future;
    unawaited(
      future.whenComplete(() {
        if (identical(_continueWatchingLoadInFlight, future)) {
          _continueWatchingLoadInFlight = null;
        }
      }),
    );
    return future;
  }

  Future<void> _drainContinueWatchingLoads() async {
    do {
      _continueWatchingRerunRequested = false;
      await _readContinueWatching();
    } while (_continueWatchingRerunRequested);
  }

  Future<void> _readContinueWatching() async {
    try {
      final history = await _historyService.getContinueWatching(limit: 10);
      if (!mounted) return;
      setState(() => _continueWatching = history);
      _prewarmContinueWatchingEpisodes(history);
    } catch (error) {
      debugPrint('[Home] Continue watching load failed: $error');
    }
  }

  /// Preloads banner images for smoother transitions.
  void _precacheBannerImages() {
    final bannerAnimes = _seasonAnimes.take(5);
    for (final anime in bannerAnimes) {
      final imageUrl = _heroBannerImageUrl(anime);
      if (imageUrl.isEmpty) continue;
      _precacheNetworkImageQuietly(imageUrl);
    }
    _prefetchVisibleCardImages();
  }

  void _prefetchVisibleCardImages() {
    final candidates = <JikanAnime>[
      ..._seasonAnimes.take(4),
      ..._topAnimes.take(4),
      ..._actionAnimes.take(4),
    ];
    final isDesktop = Responsive.isDesktopExperience(context);
    final useModernLayout = AppColors.isModern && !isDesktop;
    final cardWidth = useModernLayout
        ? Responsive.value(context, phone: 176.0, tablet: 196.0, quest: 232.0)
        : Responsive.getHorizontalListItemWidth(context);
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (cardWidth * devicePixelRatio).ceil();
    final cacheHeight = (cardWidth * 1.5 * devicePixelRatio).ceil();

    for (final imageUrl in AnimeImagePrefetchPolicy.visibleImageUrls(
      candidates,
    )) {
      if (!_prefetchedCardImages.add(imageUrl)) continue;
      _precacheNetworkImageQuietly(
        imageUrl,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
      );
    }
  }

  Future<void> _loadHeroBannerArtwork() async {
    final bannerAnimes = _seasonAnimes
        .take(5)
        .where(
          (anime) =>
              anime.bannerImageUrl == null &&
              anime.malId > 0 &&
              !_bannerArtworkRequests.contains(anime.malId),
        );

    for (final anime in bannerAnimes) {
      _bannerArtworkRequests.add(anime.malId);
      unawaited(
        AniListService.fetchAnimeByMalId(anime.malId)
            .timeout(const Duration(seconds: 8))
            .then((response) {
              if (!mounted) return;
              if (response == null) {
                _bannerArtworkRequests.remove(anime.malId);
                return;
              }

              final bannerImage = response.data.media.bannerImage;
              if (bannerImage == null || bannerImage.isEmpty) return;

              setState(() {
                _seasonAnimes = _seasonAnimes
                    .map(
                      (item) => item.malId == anime.malId
                          ? item.copyWith(bannerImageUrl: bannerImage)
                          : item,
                    )
                    .toList();
              });
              _precacheNetworkImageQuietly(bannerImage);
            })
            .catchError((Object error) {
              _bannerArtworkRequests.remove(anime.malId);
              debugPrint('[Home] Banner artwork load failed: $error');
              return null;
            }),
      );
    }
  }

  Future<void> _loadCachedHeroBannerArtwork() async {
    final bannerAnimes = _seasonAnimes
        .take(5)
        .where((anime) => anime.bannerImageUrl == null && anime.malId > 0)
        .toList();
    if (bannerAnimes.isEmpty) return;

    final imageService = AnimeImageCacheService.instance;
    final resolved = <int, String>{};
    for (final anime in bannerAnimes) {
      final bannerImage = await imageService.bestBannerUrlForAnime(
        malId: anime.malId,
        fallbackImageUrl: anime.bannerImageUrl,
        allowPosterFallback: false,
      );
      if (bannerImage != null && bannerImage.isNotEmpty) {
        resolved[anime.malId] = bannerImage;
      }
    }
    if (!mounted || resolved.isEmpty) return;

    setState(() {
      _seasonAnimes = _seasonAnimes
          .map(
            (anime) => resolved.containsKey(anime.malId)
                ? anime.copyWith(bannerImageUrl: resolved[anime.malId])
                : anime,
          )
          .toList();
    });

    for (final bannerImage in resolved.values) {
      _precacheNetworkImageQuietly(bannerImage);
    }
  }

  void _precacheNetworkImageQuietly(
    String imageUrl, {
    int? cacheWidth,
    int? cacheHeight,
  }) {
    if (!mounted || imageUrl.isEmpty) return;
    final provider = CachedNetworkImageProvider(imageUrl);
    final ImageProvider<Object> imageProvider =
        cacheWidth == null && cacheHeight == null
        ? provider
        : ResizeImage(provider, width: cacheWidth, height: cacheHeight);
    unawaited(
      precacheImage(imageProvider, context).catchError((Object error) {
        debugPrint('[Home] Image precache failed: $error');
      }),
    );
  }

  String _heroBannerImageUrl(JikanAnime anime) {
    return anime.bannerImageUrl ?? anime.largImageUrl ?? anime.imageUrl;
  }

  void _prewarmDesktopEpisodeCache(HomeData homeData) {
    if (!Responsive.isDesktopExperience(context) ||
        !UnifiedSourceService.shouldPrewarmEpisodeCache) {
      return;
    }

    final candidates = <JikanAnime>[
      ..._continueWatching.map(_historyToJikanAnime),
      ...homeData.seasonAnimes.take(3),
      ...homeData.topAnimes.take(3),
      ...homeData.actionAnimes.take(2),
    ];
    unawaited(
      UnifiedSourceService.prewarmEpisodeCache(
        candidates,
        limit: UnifiedSourceService.prewarmLimitForPlatform,
        concurrency: UnifiedSourceService.prewarmConcurrencyForPlatform,
      ),
    );
  }

  void _prewarmContinueWatchingEpisodes(List<HistoryAnime> history) {
    if (!Responsive.isDesktopExperience(context) ||
        !UnifiedSourceService.shouldPrewarmEpisodeCache ||
        history.isEmpty) {
      return;
    }

    unawaited(
      UnifiedSourceService.prewarmEpisodeCache(
        history.map(_historyToJikanAnime),
        limit: 4,
        concurrency: UnifiedSourceService.prewarmConcurrencyForPlatform,
      ),
    );
  }

  void _prewarmAnimeIntent(JikanAnime anime) {
    _intentPrewarmTimer?.cancel();
    final delay = Responsive.isDesktopExperience(context)
        ? const Duration(milliseconds: 300)
        : Duration.zero;
    _intentPrewarmTimer = Timer(delay, () {
      if (!mounted) return;
      unawaited(
        UnifiedSourceService.prewarmEpisodeCache(
          [anime],
          limit: 1,
          concurrency: 1,
        ),
      );
    });
  }

  JikanAnime _historyToJikanAnime(HistoryAnime history) {
    return JikanAnime(
      malId: int.tryParse(history.animeId) ?? 0,
      title: history.title,
      imageUrl: history.coverImage,
    );
  }

  Future<void> _openAnimeDetail(
    JikanAnime anime, {
    CatalogDisplayEntry? entry,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => UnifiedEpisodeListScreen(
          anime: anime,
          initialFranchise: entry?.franchise,
          initialSelectedMalId: entry?.selectedMalId,
        ),
      ),
    );
    // Audit fix: returning from the episode list may have changed history.
    if (mounted) await _loadContinueWatching(forceRefresh: true);
  }

  Future<void> _onContinueWatchingTap(HistoryAnime history) async {
    final anime = _historyToJikanAnime(history);

    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (context) => UnifiedEpisodeListScreen(
          anime: anime,
          initialSelectedMalId: anime.malId > 0 ? anime.malId : null,
          forceInitialSelectedMalId: anime.malId > 0,
          initialEpisodeNumber: history.episodeNumber,
          initialDubMode: history.isDubMode,
          autoOpenInitialEpisode: history.episodeNumber != null,
        ),
      ),
    );
    // Audit fix: returning from the player may have changed history; this is
    // an explicit refresh, not a bootstrap read to be shared.
    if (mounted) await _loadContinueWatching(forceRefresh: true);
  }

  bool get _hasUsableContent =>
      _seasonAnimes.isNotEmpty ||
      _todaysReleases.isNotEmpty ||
      _topAnimes.isNotEmpty ||
      _actionAnimes.isNotEmpty ||
      _romanceAnimes.isNotEmpty ||
      _comedyAnimes.isNotEmpty ||
      _fantasyAnimes.isNotEmpty ||
      _continueWatching.isNotEmpty;

  String _failureDescription(AppLocalizations l10n, UiLoadFailureKind failure) {
    return switch (failure) {
      UiLoadFailureKind.network => l10n.networkFailureDescription,
      UiLoadFailureKind.timeout => l10n.timeoutFailureDescription,
      UiLoadFailureKind.unknown => l10n.genericFailureDescription,
    };
  }

  Widget _buildHomeLoadFailure(AppLocalizations l10n) {
    final failure = _loadFailure ?? UiLoadFailureKind.unknown;
    return LoadFailurePanel(
      title: l10n.homeLoadFailedTitle,
      message: _failureDescription(l10n, failure),
      retryLabel: l10n.retry,
      onRetry: () => _loadAllData(forceRefresh: true),
    );
  }

  Widget _buildHomeRefreshWarning(AppLocalizations l10n) {
    return LoadFailurePanel(
      compact: true,
      title: l10n.homeRefreshFailed,
      message: l10n.showingSavedContent,
      retryLabel: l10n.retry,
      onRetry: () => _loadAllData(forceRefresh: true),
    );
  }

  void _openSearch() {
    final callback = widget.onSearchPressed;
    if (callback != null) {
      callback();
      return;
    }
    unawaited(
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SearchScreen()),
      ),
    );
  }
}
