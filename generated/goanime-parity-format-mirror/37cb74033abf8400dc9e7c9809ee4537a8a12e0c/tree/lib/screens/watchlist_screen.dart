// ignore_for_file: discarded_futures, inference_failure_on_function_invocation, inference_failure_on_instance_creation, unawaited_futures
// Existing callbacks/fixtures still rely on implicit async or dynamic JSON shapes; keep new strict rules enabled elsewhere.
import 'dart:async';

import '../controllers/media/library_snapshot_controller.dart';
import '../models/jikan_models.dart';
import 'package:flutter/material.dart';
import '../models/anime_franchise_models.dart';
import '../models/watchlist_anime.dart';
import '../services/anime_franchise_cache_service.dart';
import '../services/franchise_availability_cache_service.dart';
import '../services/media/anime_watchlist_snapshot_adapter.dart';
import '../services/watchlist_service.dart';
import '../services/watchlist_notifier.dart';
import '../theme/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../l10n/ui_action_localizations.dart';
import '../utils/responsive.dart';
import '../widgets/modern_theme.dart';
import '../widgets/load_failure_panel.dart';
import '../widgets/anime/goanime_anime_card.dart';
import '../widgets/anime/goanime_anime_card_skeleton.dart';
import '../widgets/foundation/goanime_responsive_content.dart';
import '../widgets/foundation/goanime_surface.dart';
import 'unified_episode_list_screen.dart';

class WatchlistScreen extends StatefulWidget {
  final WatchlistService? watchlistService;

  const WatchlistScreen({super.key, this.watchlistService});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen>
    with AutomaticKeepAliveClientMixin {
  late final WatchlistService _watchlistService;
  late final LibrarySnapshotController<WatchlistAnime> _libraryController;
  final WatchlistNotifier _watchlistNotifier = WatchlistNotifier();
  final AnimeFranchiseCacheService _franchiseCacheService =
      AnimeFranchiseCacheService();

  List<WatchlistAnime> get _watchlist =>
      _libraryController.state.data ?? const <WatchlistAnime>[];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _watchlistService = widget.watchlistService ?? WatchlistService();
    _libraryController = LibrarySnapshotController<WatchlistAnime>(
      dataSource: AnimeWatchlistSnapshotAdapter(_watchlistService),
    );
    _libraryController.addListener(_onLibraryControllerChanged);
    _watchlistNotifier.addListener(_onWatchlistChanged);
    unawaited(_libraryController.loadInitial());
  }

  @override
  void dispose() {
    _watchlistNotifier.removeListener(_onWatchlistChanged);
    _libraryController.removeListener(_onLibraryControllerChanged);
    _libraryController.dispose();
    super.dispose();
  }

  void _onLibraryControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onWatchlistChanged() {
    unawaited(_libraryController.refresh());
  }

  Future<void> _removeFromWatchlist(WatchlistAnime anime) async {
    final success = await _watchlistService.removeFromWatchlist(anime.animeId);
    if (!mounted) return;

    final l10n = AppLocalizations.of(context);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.removedFromWatchlist(anime.title)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _libraryController.refresh();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.genericFailureDescription),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final isDesktop = Responsive.isDesktopExperience(context);
    final columns = isDesktop ? Responsive.getGridColumns(context) : 2;
    final spacing = Responsive.getCardSpacing(context);
    final state = _libraryController.state;
    final watchlist = _watchlist;

    return Scaffold(
      backgroundColor: AppColors.isModern
          ? Colors.transparent
          : AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.isModern
            ? Colors.transparent
            : AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.bookmark, color: AppColors.primary, size: 24),
            const SizedBox(width: 10),
            Text(l10n.watchlist),
          ],
        ),
        actions: [
          if (watchlist.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: l10n.clearWatchlist,
              onPressed: _showClearDialog,
            ),
        ],
      ),
      body: ModernBackground(
        child: GoAnimeResponsiveContent(
          maxWidth: Responsive.getDesktopContentMaxWidth(context),
          child: (state.isIdle || state.isLoading) && watchlist.isEmpty
              ? GridView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 0.45,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                  ),
                  itemCount: columns * 3,
                  itemBuilder: (context, index) =>
                      const GoAnimeAnimeCardSkeleton(),
                )
              : state.isError && watchlist.isEmpty
              ? LoadFailurePanel(
                  title: l10n.watchlist,
                  message: l10n.genericFailureDescription,
                  retryLabel: l10n.retry,
                  onRetry: () => unawaited(_libraryController.retry()),
                )
              : watchlist.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: GoAnimeSurface(
                        key: const Key('goanime-watchlist-empty'),
                        role: GoAnimeSurfaceRole.raised,
                        accent: GoAnimeSurfaceAccent.leading,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bookmark_border_rounded,
                              size: 38,
                              color: AppColors.primary,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              l10n.watchlistEmpty,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 7),
                            Text(
                              l10n.addAnimesToWatchLater,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                            if (Navigator.canPop(context)) ...[
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () => Navigator.maybePop(context),
                                icon: const Icon(Icons.explore_outlined),
                                label: Text(l10n.discoverAnime),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _libraryController.refresh,
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  child: Column(
                    children: [
                      if (state.isError)
                        LoadFailurePanel(
                          compact: true,
                          title: l10n.watchlist,
                          message: l10n.genericFailureDescription,
                          retryLabel: l10n.retry,
                          onRetry: () => unawaited(_libraryController.retry()),
                        ),
                      Expanded(
                        child: GridView.builder(
                          padding: EdgeInsets.symmetric(
                            vertical: isDesktop ? 28 : 16,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                childAspectRatio: 0.45,
                                crossAxisSpacing: spacing,
                                mainAxisSpacing: spacing,
                              ),
                          itemCount: watchlist.length,
                          itemBuilder: (context, index) {
                            final anime = watchlist[index];
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: GoAnimeAnimeCard(
                                    imageUrl: anime.coverImage,
                                    title: anime.title,
                                    badge: anime.isFranchise
                                        ? (Localizations.localeOf(
                                                    context,
                                                  ).languageCode ==
                                                  'pt'
                                              ? 'Franquia'
                                              : 'Franchise')
                                        : null,
                                    semanticLabel: anime.title,
                                    onPressed: () => _openWatchlistItem(anime),
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: IconButton.filledTonal(
                                    tooltip: l10n.removeFromWatchlist,
                                    onPressed: () =>
                                        _removeFromWatchlist(anime),
                                    icon: const Icon(
                                      Icons.bookmark_remove_rounded,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _openWatchlistItem(WatchlistAnime item) async {
    if (item.isFranchise) {
      await _openFranchiseWatchlistItem(item);
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            UnifiedEpisodeListScreen(anime: _jikanAnimeFromWatchlist(item)),
      ),
    );
  }

  Future<void> _openFranchiseWatchlistItem(WatchlistAnime item) async {
    final franchise = await _loadCachedFranchise(item);
    final selected = _selectedFranchiseAnime(item, franchise);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UnifiedEpisodeListScreen(
          anime: selected,
          initialFranchise: franchise,
          initialSelectedMalId: selected.malId,
          forceInitialSelectedMalId: item.selectedSeasonMalId != null,
        ),
      ),
    );
  }

  Future<AnimeFranchise?> _loadCachedFranchise(WatchlistAnime item) async {
    try {
      final franchiseId = item.franchiseId;
      if (franchiseId == null || franchiseId.isEmpty) return null;
      await FranchiseAvailabilityCacheService.initialize();
      final indexed = item.selectedSeasonMalId == null
          ? null
          : await FranchiseAvailabilityCacheService.franchiseForMalIdAsync(
              item.selectedSeasonMalId!,
            );
      if (indexed != null) return indexed;
      return _franchiseCacheService.getByFranchiseId(
        franchiseId,
        allowExpired: true,
      );
    } catch (error) {
      debugPrint('[Watchlist] Failed to load cached franchise: $error');
      return null;
    }
  }

  JikanAnime _selectedFranchiseAnime(
    WatchlistAnime item,
    AnimeFranchise? franchise,
  ) {
    final selectedMalId = item.selectedSeasonMalId;
    if (franchise != null && franchise.entries.isNotEmpty) {
      final entries = [...franchise.mainlineEntries, ...franchise.extraEntries];
      if (entries.isEmpty) return _jikanAnimeFromWatchlist(item);
      return entries
          .firstWhere(
            (entry) => entry.malId == selectedMalId,
            orElse: () => entries.first,
          )
          .anime;
    }
    return _jikanAnimeFromWatchlist(item);
  }

  JikanAnime _jikanAnimeFromWatchlist(WatchlistAnime item) {
    final malId = item.isFranchise
        ? item.selectedSeasonMalId ?? 0
        : int.tryParse(item.animeId) ?? 0;
    return JikanAnime(
      malId: malId,
      title: item.title,
      imageUrl: item.coverImage,
    );
  }

  void _showClearDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearWatchlistQuestion),
        content: Text(l10n.clearWatchlistConfirmation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              navigator.pop();
              final success = await _watchlistService.clearWatchlist();
              if (!mounted) return;

              if (success) {
                await _libraryController.refresh();
                if (!mounted) return;
              }

              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? l10n.watchlistCleared
                        : l10n.genericFailureDescription,
                  ),
                  backgroundColor: success
                      ? AppColors.primary
                      : AppColors.error,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(l10n.clear),
          ),
        ],
      ),
    );
  }
}
