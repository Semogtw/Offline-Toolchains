from pathlib import Path

home_path = Path('lib/screens/home_screen.dart')
data_path = Path('lib/screens/home_screen_data.dart')
home = home_path.read_text(encoding='utf-8')
data = data_path.read_text(encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    return text.replace(old, new, 1)


home = replace_once(
    home,
    "import 'dart:async';\nimport '../models/catalog_display_entry.dart';",
    "import 'dart:async';\nimport '../controllers/media/home_snapshot_controller.dart';\nimport '../models/catalog_display_entry.dart';",
    'controller import',
)
home = replace_once(
    home,
    "import '../services/jikan_service.dart';\nimport '../services/unified_source_service.dart';",
    "import '../services/jikan_service.dart';\nimport '../services/media/anime_home_snapshot_adapter.dart';\nimport '../services/unified_source_service.dart';",
    'adapter import',
)
home = replace_once(
    home,
    "  late final JikanService _jikanService;\n  final CatalogFranchiseDisplayService _catalogDisplayService =",
    "  late final JikanService _jikanService;\n  late final AnimeHomeSnapshotAdapter _homeSnapshotAdapter;\n  late final HomeSnapshotController<HomeData> _homeController;\n  HomeData? _lastAppliedHomeSnapshot;\n  final CatalogFranchiseDisplayService _catalogDisplayService =",
    'controller fields',
)
home = replace_once(
    home,
    "  /// PERF-N05: in-flight guards so concurrent bootstrap callers\n  /// (initState + post-catalog refresh) share one storage read instead of\n  /// duplicating SharedPreferences/JSON/SQLite work on the cold-start path.\n  Future<void>? _continueWatchingLoadInFlight;\n  Future<void>? _cachedSnapshotLoadInFlight;\n",
    "  /// PERF-N05: Continue Watching storage reads remain single-flight.\n  /// Catalog snapshot cache/fresh coordination is owned by\n  /// [HomeSnapshotController] through [AnimeHomeSnapshotAdapter].\n  Future<void>? _continueWatchingLoadInFlight;\n",
    'bootstrap in-flight fields',
)
home = replace_once(
    home,
    """    _jikanService = widget.jikanService ?? JikanService(propagateErrors: true);
    _fabAnimationController = AnimationController(
""",
    """    _jikanService = widget.jikanService ?? JikanService(propagateErrors: true);
    _homeSnapshotAdapter = AnimeHomeSnapshotAdapter(jikanService: _jikanService);
    _homeController = HomeSnapshotController<HomeData>(
      loadCached: _homeSnapshotAdapter.loadCached,
      loadFresh: _homeSnapshotAdapter.loadFresh,
    );
    _homeController.addListener(_onHomeControllerChanged);
    _fabAnimationController = AnimationController(
""",
    'controller initialization',
)
home = replace_once(
    home,
    """    unawaited(_loadContinueWatching());
    unawaited(_loadCachedHomeData());
    if (!_dataLoaded) {
      unawaited(_loadAllData());
    }
    _startBannerRotation();
""",
    """    unawaited(_loadContinueWatching());
    _dataLoaded = true;
    unawaited(_homeController.loadInitial());
    _startBannerRotation();
""",
    'bootstrap lifecycle',
)
home = replace_once(
    home,
    """  void _onAvailabilityUpdated() {
""",
    """  void _onHomeControllerChanged() {
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
""",
    'controller listener',
)
home = replace_once(
    home,
    """  void dispose() {
    AvailabilityService.updateNotifier.removeListener(_onAvailabilityUpdated);
    _fabAnimationController.dispose();
""",
    """  void dispose() {
    AvailabilityService.updateNotifier.removeListener(_onAvailabilityUpdated);
    _homeController.removeListener(_onHomeControllerChanged);
    _homeController.dispose();
    _fabAnimationController.dispose();
""",
    'controller disposal',
)
home = replace_once(
    home,
    "        onRefresh: () => _loadAllData(forceRefresh: true),",
    "        onRefresh: _homeController.refresh,",
    'pull refresh',
)

start = data.index('  /// Loads the catalog with a hard upper bound')
end = data.index('  /// Audit fix: consumes the pending-availability flag', start)
data = (
    data[:start]
    + """  /// Compatibility entry point for existing retry callbacks. The shared
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

"""
    + data[end:]
)

cache_start = data.index('  /// PERF-N05: single-flight wrapper for the persisted snapshot read.')
cache_end = data.index('  void _applyHomeData(HomeData homeData) {', cache_start)
data = data[:cache_start] + data[cache_end:]

data = replace_once(
    data,
    """      _fantasyEntries = _singleEntries(homeData.fantasyAnimes);
      _currentBannerIndex = nextBannerIndex;
      _isLoading = false;
      _loadFailure = null;
""",
    """      _fantasyEntries = _singleEntries(homeData.fantasyAnimes);
      _currentBannerIndex = nextBannerIndex;
""",
    'apply lifecycle ownership',
)

home_path.write_text(home, encoding='utf-8')
data_path.write_text(data, encoding='utf-8')
