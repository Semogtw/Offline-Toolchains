import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/media/library_snapshot_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/ui_manga_localizations.dart';
import '../../services/manga/manga_availability_models.dart';
import '../../services/manga/manga_browse_data_source.dart';
import '../../services/manga/manga_platform_runtime_service.dart';
import '../../services/manga/storage/manga_library_repository.dart';
import '../../services/media/manga_library_snapshot_adapter.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive.dart';
import '../../widgets/foundation/goanime_responsive_content.dart';
import '../../widgets/manga/manga_browse_library_view.dart';
import '../../widgets/manga/manga_load_error_view.dart';
import 'manga_details_screen.dart';
import 'manga_shell_surface.dart';

class MangaLibraryScreen extends StatefulWidget {
  const MangaLibraryScreen({super.key, this.dataSource, this.onOpenWork});

  final MangaBrowseDataSource? dataSource;
  final ValueChanged<MangaAvailabilityRecord>? onOpenWork;

  @override
  State<MangaLibraryScreen> createState() => _MangaLibraryScreenState();
}

class _MangaLibraryScreenState extends State<MangaLibraryScreen> {
  final MangaLibraryRepository _libraryRepository = MangaLibraryRepository();
  final Set<String> _removingWorkIds = <String>{};
  MangaBrowseDataSource? _activeSource;
  MangaPlatformRuntimeService? _runtime;
  LibrarySnapshotController<MangaBrowseItem>? _libraryController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSource();
  }

  @override
  void didUpdateWidget(covariant MangaLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSource();
  }

  void _syncSource() {
    final runtime = Provider.of<MangaPlatformRuntimeService?>(context);
    _runtime = runtime;
    final next = widget.dataSource ?? runtime?.browse;
    if (identical(next, _activeSource)) return;

    _libraryController?.removeListener(_onLibraryControllerChanged);
    _libraryController?.dispose();
    _activeSource = next;

    if (next == null) {
      _libraryController = null;
      return;
    }

    final controller = LibrarySnapshotController<MangaBrowseItem>(
      dataSource: MangaLibrarySnapshotAdapter(next),
    );
    _libraryController = controller;
    controller.addListener(_onLibraryControllerChanged);
    unawaited(controller.loadInitial());
  }

  void _onLibraryControllerChanged() {
    if (mounted) setState(() {});
  }

  void _openWork(MangaAvailabilityRecord record) {
    final external = widget.onOpenWork;
    if (external != null) {
      external(record);
      return;
    }
    unawaited(_openWorkAndRefresh(record));
  }

  Future<void> _openWorkAndRefresh(MangaAvailabilityRecord record) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MangaDetailsScreen(
          availability: record,
          dataSource: _runtime?.detailsDataSource,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadLibrary();
  }

  Future<void> _removeWork(MangaAvailabilityRecord record) async {
    if (widget.dataSource != null) return;
    final workId = record.work.workId;
    if (_removingWorkIds.contains(workId)) return;
    setState(() => _removingWorkIds.add(workId));
    final l10n = AppLocalizations.of(context).manga;
    try {
      await _libraryRepository.remove(workId);
      if (!mounted) return;
      unawaited(_reloadLibrary());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.libraryUpdated)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.libraryUpdateFailed)));
    } finally {
      if (mounted) setState(() => _removingWorkIds.remove(workId));
    }
  }

  Future<void> _reloadLibrary() {
    final controller = _libraryController;
    if (controller == null || !mounted) return Future<void>.value();
    return controller.refresh();
  }

  @override
  void dispose() {
    _libraryController?.removeListener(_onLibraryControllerChanged);
    _libraryController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context).manga;
    final controller = _libraryController;
    if (_activeSource == null || controller == null) {
      return MangaShellSurface(
        title: l10n.libraryTitle,
        message: l10n.unavailableMessage,
        icon: Icons.bookmark_outline,
      );
    }

    final state = controller.state;
    final items = state.data ?? const <MangaBrowseItem>[];

    return Scaffold(
      backgroundColor: AppColors.isModern
          ? Colors.transparent
          : AppColors.background,
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        backgroundColor: AppColors.isModern
            ? Colors.transparent
            : AppColors.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: (state.isIdle || state.isLoading) && items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.isError && items.isEmpty
            ? MangaLoadErrorView(onRetry: () => unawaited(controller.retry()))
            : RefreshIndicator(
                onRefresh: controller.refresh,
                child: Column(
                  children: [
                    if (state.isError)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: MangaLoadErrorView(
                          compact: true,
                          onRetry: () => unawaited(controller.retry()),
                        ),
                      ),
                    Expanded(
                      child: GoAnimeResponsiveContent(
                        maxWidth: Responsive.getDesktopContentMaxWidth(context),
                        child: MangaBrowseLibraryView(
                          items: items,
                          labels: MangaBrowseLibraryLabels(
                            empty: l10n.noAvailableWorks,
                            unread: l10n.unread,
                            offline: l10n.offline,
                            statusLabel: l10n.libraryStatusLabel,
                            removeTooltip: l10n.removeFromLibrary,
                          ),
                          onOpenWork: _openWork,
                          onRemoveWork: widget.dataSource == null
                              ? (record) => unawaited(_removeWork(record))
                              : null,
                          removingWorkIds: _removingWorkIds,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
