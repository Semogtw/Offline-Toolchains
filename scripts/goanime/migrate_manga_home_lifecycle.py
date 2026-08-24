from pathlib import Path

path = Path('lib/screens/manga/manga_home_screen.dart')
text = path.read_text(encoding='utf-8')


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly 1 match, found {count}')
    text = text.replace(old, new, 1)


replace_once(
    "import 'package:provider/provider.dart';\n\nimport '../../l10n/app_localizations.dart';",
    "import 'package:provider/provider.dart';\n\nimport '../../controllers/media/home_snapshot_controller.dart';\nimport '../../l10n/app_localizations.dart';",
    'shared Home controller import',
)

replace_once(
    '  Future<MangaHomeSnapshot>? _loadFuture;\n',
    '  HomeSnapshotController<MangaHomeSnapshot>? _homeController;\n',
    'Home future field',
)

replace_once(
    "    _fabAnimationController.dispose();\n    _runtime?.cancelLiveOwner(_discoveryOwnerToken);",
    "    _fabAnimationController.dispose();\n    _homeController?.dispose();\n    _runtime?.cancelLiveOwner(_discoveryOwnerToken);",
    'controller disposal',
)

replace_once(
    """  void _syncSource(MangaPlatformRuntimeService? runtime) {
    final next = widget.dataSource ?? runtime?.browse;
    if (identical(next, _activeSource)) return;
    _activeSource = next;
    _loadFuture = next?.loadHome();
  }

  void _retryLoad() {
    final source = _activeSource;
    if (source == null || !mounted) return;
    setState(() => _loadFuture = source.loadHome());
  }
""",
    """  void _syncSource(MangaPlatformRuntimeService? runtime) {
    final next = widget.dataSource ?? runtime?.browse;
    if (identical(next, _activeSource)) return;

    _homeController?.dispose();
    _activeSource = next;
    if (next == null) {
      _homeController = null;
      return;
    }

    final controller = HomeSnapshotController<MangaHomeSnapshot>(
      loadFresh: ({required bool forceRefresh}) => next.loadHome(),
    );
    _homeController = controller;
    unawaited(controller.loadInitial());
  }

  void _retryLoad() {
    final controller = _homeController;
    if (controller == null || controller.isDisposed) return;
    if (controller.lastFailedOperation != null) {
      unawaited(controller.retry());
      return;
    }
    unawaited(controller.refresh());
  }

  Future<void> _refreshHome() async {
    final controller = _homeController;
    if (controller == null || controller.isDisposed) return;

    await controller.refresh();
    if (!mounted || _runtime?.hasLiveSources != true) return;
    await _refreshDiscovery(userInitiated: true);
  }
""",
    'source lifecycle block',
)

replace_once(
    """  Future<void> _refreshDiscovery({bool userInitiated = false}) async {
    if (_refreshing) return;
    final runtime = _runtime;
    final source = _activeSource;
    if (runtime == null || source == null || !runtime.hasLiveSources) {
      if (userInitiated) _retryLoad();
      return;
    }

    setState(() => _refreshing = true);
    try {
      final stream = runtime.discoverHome(_discoveryOwnerToken);
      await for (final _ in stream) {
        if (!mounted) break;
        final snapshot = await source.loadHome();
        if (!mounted) break;
        setState(() => _loadFuture = Future.value(snapshot));
      }
    } catch (e) {
      debugPrint('[MangaHome] Live discovery error: $e');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
""",
    """  Future<void> _refreshDiscovery({bool userInitiated = false}) async {
    if (_refreshing) return;
    final runtime = _runtime;
    final controller = _homeController;
    if (runtime == null || controller == null || !runtime.hasLiveSources) {
      if (userInitiated && controller != null && !controller.isDisposed) {
        await controller.refresh();
      }
      return;
    }

    setState(() {
      _refreshing = true;
    });
    try {
      final stream = runtime.discoverHome(_discoveryOwnerToken);
      await for (final _ in stream) {
        if (!mounted || controller.isDisposed) break;
        await controller.refresh();
        if (!mounted || controller.lastError != null) break;
      }
    } catch (e) {
      debugPrint('[MangaHome] Live discovery error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }
""",
    'live discovery lifecycle block',
)

replace_once(
    """      body: RefreshIndicator(
        onRefresh: () async {
          _retryLoad();
          if (_runtime?.hasLiveSources == true) {
            unawaited(_refreshDiscovery(userInitiated: true));
          }
        },
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: FutureBuilder<MangaHomeSnapshot>(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done &&
                !snapshot.hasData) {
              return _buildSkeleton(context);
            }
            if (snapshot.hasError && !snapshot.hasData) {
              return MangaLoadErrorView(
                onRetry: () {
                  _retryLoad();
                  if (_runtime?.hasLiveSources == true) {
                    unawaited(_refreshDiscovery(userInitiated: true));
                  }
                },
              );
            }

            final data = snapshot.data ?? const MangaHomeSnapshot();
            return _buildContent(context, data, rootL10n, l10n);
          },
        ),
      ),
""",
    """      body: RefreshIndicator(
        onRefresh: _refreshHome,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: AnimatedBuilder(
          animation: _homeController!,
          builder: (context, _) {
            final controller = _homeController!;
            final state = controller.state;
            final data = state.data;

            if ((state.isIdle || state.isLoading) && data == null) {
              return _buildSkeleton(context);
            }
            if (state.isError && data == null) {
              return MangaLoadErrorView(onRetry: _retryLoad);
            }

            final content = _buildContent(
              context,
              data ?? const MangaHomeSnapshot(),
              rootL10n,
              l10n,
            );
            if (!state.isError || data == null) return content;

            return Stack(
              children: [
                content,
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: SafeArea(
                    top: false,
                    child: MangaLoadErrorView(
                      compact: true,
                      onRetry: _retryLoad,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
""",
    'Home body lifecycle block',
)

path.write_text(text, encoding='utf-8')
