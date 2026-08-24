// ignore_for_file: discarded_futures, inference_failure_on_function_invocation, inference_failure_on_instance_creation, unawaited_futures
// Existing callbacks/fixtures still rely on implicit async or dynamic JSON shapes; keep new strict rules enabled elsewhere.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ionicons/ionicons.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'dart:async';
import '../controllers/media/home_snapshot_controller.dart';
import '../models/catalog_display_entry.dart';
import '../models/jikan_models.dart';
import '../models/history_anime.dart';
import '../services/anilist_service.dart';
import '../services/anime_image_cache_service.dart';
import '../services/anime_image_prefetch_policy.dart';
import '../services/availability_service.dart';
import '../services/catalog_franchise_display_service.dart';
import '../services/jikan_service.dart';
import '../services/media/anime_home_snapshot_adapter.dart';
import '../services/unified_source_service.dart';
import '../services/watch_history_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../utils/performance_config.dart';
import '../utils/responsive.dart';
import '../utils/ui_load_failure.dart';
import '../widgets/app_logo_mark.dart';
import '../widgets/modern_theme.dart';
import '../widgets/load_failure_panel.dart';
import '../widgets/anime/goanime_anime_card.dart';
import '../widgets/anime/goanime_anime_card_skeleton.dart';
import '../widgets/anime/goanime_catalog_section.dart';
import '../widgets/anime/goanime_hero_banner.dart';
import '../widgets/home/goanime_catalog_row.dart';
import '../widgets/home/goanime_continue_watching_card.dart';
import '../widgets/home/goanime_hero_carousel.dart';
import 'history_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'genre_animes_screen.dart';
import 'unified_episode_list_screen.dart';

part 'home_screen_data.dart';
part 'home_screen_presentation.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onMenuPressed;
  final VoidCallback? onSearchPressed;
  final JikanService? jikanService;

  const HomeScreen({
    super.key,
    this.onMenuPressed,
    this.onSearchPressed,
    this.jikanService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  bool _catalogAppliedDuringCurrentLoad = false;

  bool get _hasCatalogContent =>
      _seasonAnimes.isNotEmpty ||
      _todaysReleases.isNotEmpty ||
      _topAnimes.isNotEmpty ||
      _actionAnimes.isNotEmpty ||
      _romanceAnimes.isNotEmpty ||
      _comedyAnimes.isNotEmpty ||
      _fantasyAnimes.isNotEmpty;

  /// Library-local presentation extensions update this State through this override.
  @override
  void setState(VoidCallback callback) {
    super.setState(() {
      final wasLoading = _isLoading;
      final hadCatalogContent = _hasCatalogContent;
      callback();

      if (!wasLoading && _isLoading) {
        _catalogAppliedDuringCurrentLoad = false;
      } else if (wasLoading &&
          !_isLoading &&
          _loadFailure == null &&
          _hasCatalogContent &&
          (!hadCatalogContent || _dataLoaded)) {
        _catalogAppliedDuringCurrentLoad = true;
      }

      if (_catalogAppliedDuringCurrentLoad &&
          !_isLoading &&
          _loadFailure != null) {
        debugPrint(
          '[Home] Ignoring secondary load failure after catalog was applied.',
        );
        _loadFailure = null;
        _catalogAppliedDuringCurrentLoad = false;
      }
    });
  }

  late final JikanService _jikanService;
  late final AnimeHomeSnapshotAdapter _homeSnapshotAdapter;
  late final HomeSnapshotController<HomeData> _homeController;
  HomeData? _lastAppliedHomeSnapshot;
  final CatalogFranchiseDisplayService _catalogDisplayService =
      CatalogFranchiseDisplayService();
  final WatchHistoryService _historyService = WatchHistoryService();
  final ScrollController _scrollController = ScrollController();

  late AnimationController _fabAnimationController;

  // ValueNotifiers avoid rebuilding the full tree on scroll.
  final ValueNotifier<bool> _showFabNotifier = ValueNotifier(false);
  final ValueNotifier<bool> _showHeaderNotifier = ValueNotifier(true);

  double _lastScrollOffset = 0.0;
  bool _dataLoaded = false;
  bool _isLoading = true;

  /// PERF-N05: Continue Watching storage reads remain single-flight.
  /// Catalog snapshot cache/fresh coordination is owned by
  /// [HomeSnapshotController] through [AnimeHomeSnapshotAdapter].
  Future<void>? _continueWatchingLoadInFlight;

  /// Audit fix: a forced Continue Watching refresh (returning from the
  /// player) that lands while a bootstrap read is still in flight queues
  /// exactly one trailing re-read instead of joining the stale one.
  bool _continueWatchingRerunRequested = false;

  /// PERF-N04: single-flight state for availability-driven recollapses.
  Future<void>? _homeCollapseInFlight;
  bool _homeCollapseRerunRequested = false;

  /// Audit fix: availability events arriving while a catalog load/refresh is
  /// running are dropped by `_onAvailabilityUpdated`; this flag records them
  /// so every terminal path of the load (success or failure) still collapses
  /// with the newly available titles.
  bool _availabilityChangePendingCollapse = false;

  UiLoadFailureKind? _loadFailure;

  // Listas de animes
  List<JikanAnime> _seasonAnimes = [];
  List<JikanAnime> _todaysReleases = [];
  List<JikanAnime> _topAnimes = [];
  List<JikanAnime> _actionAnimes = [];
  List<JikanAnime> _romanceAnimes = [];
  List<JikanAnime> _comedyAnimes = [];
  List<JikanAnime> _fantasyAnimes = [];
  List<CatalogDisplayEntry> _seasonEntries = [];
  List<CatalogDisplayEntry> _todaysEntries = [];
  List<CatalogDisplayEntry> _topEntries = [];
  List<CatalogDisplayEntry> _actionEntries = [];
  List<CatalogDisplayEntry> _romanceEntries = [];
  List<CatalogDisplayEntry> _comedyEntries = [];
  List<CatalogDisplayEntry> _fantasyEntries = [];
  List<HistoryAnime> _continueWatching = [];
  final Set<int> _bannerArtworkRequests = {};
  final Set<String> _prefetchedCardImages = {};
  Timer? _intentPrewarmTimer;

  // Índice do banner atual
  int _currentBannerIndex = 0;
  int _homeCollapseGeneration = 0;
  late PageController _bannerPageController;
  Timer? _bannerRotationTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _jikanService = widget.jikanService ?? JikanService(propagateErrors: true);
    _homeSnapshotAdapter = AnimeHomeSnapshotAdapter(
      jikanService: _jikanService,
    );
    _homeController = HomeSnapshotController<HomeData>(
      loadCached: _homeSnapshotAdapter.loadCached,
      loadFresh: _homeSnapshotAdapter.loadFresh,
    );
    _homeController.addListener(_onHomeControllerChanged);
    _fabAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );
    _bannerPageController = PageController();

    _scrollController.addListener(_onScroll);
    AvailabilityService.updateNotifier.addListener(_onAvailabilityUpdated);
    unawaited(_loadContinueWatching());
    _dataLoaded = true;
    unawaited(_homeController.loadInitial());
    _startBannerRotation();
  }

  void _onHomeControllerChanged() {
    if (!mounted) return;

    final state = _homeController.state;
    final data = state.data;
    if (data != null && !identical(data, _lastAppliedHomeSnapshot)) {
      _lastAppliedHomeSnapshot = data;
      _applyHomeData(data);
      _afterHomeSnapshotApplied(data);
    }

    final rawError = _homeController.lastError;
    final nextFailure = state.isError
        ? (rawError == null
              ? UiLoadFailureKind.unknown
              : classifyUiLoadFailure(rawError))
        : null;
    final nextLoading = state.isLoading || state.isRefreshing;
    if (_isLoading != nextLoading || _loadFailure != nextFailure) {
      setState(() {
        _isLoading = nextLoading;
        _loadFailure = nextFailure;
      });
    }

    if (!nextLoading) {
      if (state.isError) {
        unawaited(_collapseCachedHomeSections());
      } else if (state.isSuccess) {
        // History is secondary content. Its storage failure must never turn a
        // successfully loaded catalog into a Home failure.
        unawaited(_loadContinueWatching());
      }
      _consumeAvailabilityChangeDuringLoad();
    }
  }

  void _onAvailabilityUpdated() {
    if (!mounted) return;
    if (!_isLoading && _dataLoaded) {
      // Re-collapse when availability changes so new animes pop up
      unawaited(_collapseCachedHomeSections());
      return;
    }
    // Audit fix: a discovery notification arriving during an in-flight
    // catalog load would previously be dropped; record it so the load's
    // terminal path still collapses with the new titles.
    _availabilityChangePendingCollapse = true;
  }

  @override
  void dispose() {
    AvailabilityService.updateNotifier.removeListener(_onAvailabilityUpdated);
    _homeController.removeListener(_onHomeControllerChanged);
    _homeController.dispose();
    _fabAnimationController.dispose();
    _scrollController.dispose();
    _bannerRotationTimer?.cancel();
    _intentPrewarmTimer?.cancel();
    _bannerPageController.dispose();
    _showFabNotifier.dispose();
    _showHeaderNotifier.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;

    final shouldShowFab = offset > 300;
    if (shouldShowFab != _showFabNotifier.value) {
      _showFabNotifier.value = shouldShowFab;
      if (shouldShowFab) {
        _fabAnimationController.forward();
      } else {
        _fabAnimationController.reverse();
      }
    }

    final shouldShowHeader =
        offset <= 20 ||
        (delta < -8) ||
        (_showHeaderNotifier.value && delta <= 8);
    _lastScrollOffset = offset;

    if (shouldShowHeader != _showHeaderNotifier.value) {
      _showHeaderNotifier.value = shouldShowHeader;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Requerido por AutomaticKeepAliveClientMixin
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.isModern
          ? Colors.transparent
          : AppColors.background,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _homeController.refresh,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          scrollCacheExtent: ScrollCacheExtent.pixels(
            PerformanceConfig.scrollCacheExtent,
          ),
          slivers: [
            if (_loadFailure != null && !_hasUsableContent && !_isLoading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildHomeLoadFailure(l10n),
              )
            else ...[
              // Banner Hero com Parallax
              if (_seasonAnimes.isNotEmpty)
                SliverToBoxAdapter(child: _buildHeroBannerCarousel()),

              // Conteúdo principal. Keep vertical sections in a sliver so
              // distant rows are not laid out/mounted during the first frame.
              SliverList(
                delegate: SliverChildListDelegate([
                  SizedBox(height: AppColors.isModern ? 30 : 24),

                  if (_loadFailure != null && _hasUsableContent)
                    _buildHomeRefreshWarning(l10n),

                  if (_continueWatching.isNotEmpty)
                    _buildContinueWatchingSection(),

                  // Seção: Estreias Recentes
                  _buildModernSection(
                    title: l10n.seasonHighlights,
                    icon: Ionicons.trending_up_outline,
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                    entries: _seasonEntries,
                    isLoading: _isLoading && _seasonAnimes.isEmpty,
                    sectionId: 'season',
                    genreId: null,
                    source: GenreAnimesSource.currentSeason,
                  ),

                  // Seção: Lançamentos de Hoje
                  _buildModernSection(
                    title: l10n.todaysReleases,
                    icon: Ionicons.calendar_outline,
                    gradient: LinearGradient(
                      colors: [Color(0xFF00C9FF), Color(0xFF92FE9D)],
                    ),
                    entries: _todaysEntries,
                    isLoading: _isLoading && _todaysReleases.isEmpty,
                    sectionId: 'today',
                    genreId: null,
                    source: GenreAnimesSource
                        .currentSeason, // Reusa a tela de temporada para 'ver todos'
                  ),

                  // Seção: Top Animes
                  _buildModernSection(
                    title: l10n.topAnime,
                    icon: LucideIcons.trophy,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFD93D), Color(0xFFFFA500)],
                    ),
                    entries: _topEntries,
                    isLoading: _isLoading && _topAnimes.isEmpty,
                    sectionId: 'top',
                    genreId: null,
                    source: GenreAnimesSource.top,
                  ),

                  // Seção: Ação
                  _buildModernSection(
                    title: l10n.action,
                    icon: LucideIcons.swords,
                    gradient: LinearGradient(
                      colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                    ),
                    entries: _actionEntries,
                    isLoading: _isLoading && _actionAnimes.isEmpty,
                    sectionId: 'action',
                    genreId: JikanGenreIds.action,
                  ),

                  // Seção: Romance
                  _buildModernSection(
                    title: l10n.romance,
                    icon: LucideIcons.heart,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFF6B9D), Color(0xFFC44569)],
                    ),
                    entries: _romanceEntries,
                    isLoading: _isLoading && _romanceAnimes.isEmpty,
                    sectionId: 'romance',
                    genreId: JikanGenreIds.romance,
                  ),

                  // Seção: Comédia
                  _buildModernSection(
                    title: l10n.comedy,
                    icon: LucideIcons.laugh,
                    gradient: LinearGradient(
                      colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5)],
                    ),
                    entries: _comedyEntries,
                    isLoading: _isLoading && _comedyAnimes.isEmpty,
                    sectionId: 'comedy',
                    genreId: JikanGenreIds.comedy,
                  ),

                  // Seção: Fantasia
                  _buildModernSection(
                    title: l10n.fantasy,
                    icon: LucideIcons.wand2,
                    gradient: LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    entries: _fantasyEntries,
                    isLoading: _isLoading && _fantasyAnimes.isEmpty,
                    sectionId: 'fantasy',
                    genreId: JikanGenreIds.fantasy,
                  ),

                  SizedBox(height: 48),
                ]),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _showFabNotifier,
        builder: (context, showFab, _) {
          if (!showFab) return const SizedBox.shrink();
          return ScaleTransition(
            scale: _fabAnimationController,
            child: FloatingActionButton(
              onPressed: () {
                _scrollController.animateTo(
                  0,
                  duration: Duration(milliseconds: 500),
                  curve: Curves.easeInOut,
                );
              },
              backgroundColor: AppColors.primary,
              child: Icon(Icons.arrow_upward, color: Colors.white),
            ),
          );
        },
      ),
    );
  }
}
