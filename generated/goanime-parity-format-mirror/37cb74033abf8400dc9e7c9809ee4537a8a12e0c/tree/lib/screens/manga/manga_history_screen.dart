import 'dart:async';

import 'package:flutter/material.dart';
import 'package:goanime_core/goanime_core.dart';
import 'package:provider/provider.dart';

import '../../controllers/media/history_snapshot_controller.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/ui_manga_localizations.dart';
import '../../services/manga/manga_history_data_source.dart';
import '../../services/manga/manga_platform_runtime_service.dart';
import '../../services/manga/storage/manga_catalog_repository.dart';
import '../../services/manga/storage/manga_preferences_repository.dart';
import '../../services/manga/storage/manga_progress_repository.dart';
import '../../services/media/manga_history_snapshot_adapter.dart';
import '../../theme/app_colors.dart';
import 'manga_reader_screen.dart';

class MangaHistoryScreen extends StatefulWidget {
  const MangaHistoryScreen({super.key, this.dataSource, this.onOpen});

  final MangaHistoryDataSource? dataSource;
  final ValueChanged<MangaReadingHistoryItem>? onOpen;

  @override
  State<MangaHistoryScreen> createState() => _MangaHistoryScreenState();
}

class _MangaHistoryScreenState extends State<MangaHistoryScreen> {
  late MangaHistoryDataSource _dataSource;
  late HistorySnapshotController<MangaReadingHistoryItem> _historyController;
  final Object _readerOwnerToken = Object();
  MangaPlatformRuntimeService? _runtime;
  String? _openingChapterId;

  @override
  void initState() {
    super.initState();
    _dataSource = widget.dataSource ?? MangaRepositoryHistoryDataSource();
    _historyController = _createHistoryController(_dataSource)
      ..addListener(_onHistoryChanged);
    unawaited(_historyController.loadInitial());
  }

  HistorySnapshotController<MangaReadingHistoryItem> _createHistoryController(
    MangaHistoryDataSource dataSource,
  ) {
    return HistorySnapshotController<MangaReadingHistoryItem>(
      dataSource: MangaHistorySnapshotAdapter(dataSource),
    );
  }

  void _onHistoryChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _runtime = Provider.of<MangaPlatformRuntimeService?>(context);
  }

  @override
  void didUpdateWidget(covariant MangaHistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.dataSource, widget.dataSource)) return;

    _historyController
      ..removeListener(_onHistoryChanged)
      ..dispose();
    _dataSource = widget.dataSource ?? MangaRepositoryHistoryDataSource();
    _historyController = _createHistoryController(_dataSource)
      ..addListener(_onHistoryChanged);
    unawaited(_historyController.loadInitial());
  }

  @override
  void dispose() {
    _historyController
      ..removeListener(_onHistoryChanged)
      ..dispose();
    _runtime?.cancelLiveOwner(_readerOwnerToken);
    super.dispose();
  }

  Future<void> _refreshHistory() => _historyController.refresh();

  void _open(MangaReadingHistoryItem item) {
    final external = widget.onOpen;
    if (external != null) {
      external(item);
      return;
    }
    unawaited(_resumeChapter(item));
  }

  Future<void> _resumeChapter(MangaReadingHistoryItem item) async {
    if (_openingChapterId != null) return;
    final runtime = _runtime;
    if (runtime == null || !runtime.hasReadingRuntime) {
      _showReaderFailure();
      return;
    }

    setState(() => _openingChapterId = item.canonicalChapterId);
    try {
      final catalog = MangaCatalogRepository();
      final chapters = await catalog.chaptersForWork(item.workId);
      final chapter = _chapterForId(chapters, item.canonicalChapterId);
      if (chapter == null) throw StateError('Chapter is unavailable.');

      final variants = await catalog.variantsForChapter(
        item.canonicalChapterId,
      );
      final preference =
          await MangaPreferencesRepository().sourcePreferenceForWork(
            item.workId,
          ) ??
          const MangaSourcePreference(mode: MangaSourceMode.automatic);
      final progress = await MangaProgressRepository().progressForChapter(
        item.workId,
        item.canonicalChapterId,
      );

      final resolved = await runtime.resolveChapterContent(
        workId: item.workId,
        canonicalChapterId: item.canonicalChapterId,
        variants: variants,
        preference: preference,
        ownerToken: _readerOwnerToken,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => MangaReaderScreen(
            chapter: chapter,
            manifest: resolved.manifest,
            initialProgress: progress,
            localContentLoader: runtime.resolveLocalReaderContent,
            remoteTransport: runtime.readerRemoteTransport,
          ),
        ),
      );
      if (mounted) await _refreshHistory();
    } catch (_) {
      if (mounted) _showReaderFailure();
    } finally {
      if (mounted) setState(() => _openingChapterId = null);
    }
  }

  static CanonicalChapter? _chapterForId(
    Iterable<CanonicalChapter> chapters,
    String canonicalChapterId,
  ) {
    for (final chapter in chapters) {
      if (chapter.canonicalChapterId == canonicalChapterId) return chapter;
    }
    return null;
  }

  void _showReaderFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).manga.readerUnavailable),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context).manga;
    final state = _historyController.state;
    final items = state.data;
    final isInitialLoading = items == null && (state.isIdle || state.isLoading);
    final isBusy = state.isLoading || state.isRefreshing;

    return Scaffold(
      backgroundColor: AppColors.isModern
          ? Colors.transparent
          : AppColors.background,
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        backgroundColor: AppColors.isModern
            ? Colors.transparent
            : AppColors.surface,
        actions: [
          IconButton(
            tooltip: l10n.downloadsRefresh,
            onPressed: isBusy ? null : () => unawaited(_refreshHistory()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: isInitialLoading
            ? const Center(child: CircularProgressIndicator())
            : state.isError && items == null
            ? _HistoryMessage(
                icon: Icons.error_outline_rounded,
                message: _pt(context)
                    ? 'Não foi possível carregar o histórico de leitura.'
                    : 'Reading history could not be loaded.',
                actionLabel: _pt(context) ? 'Tentar novamente' : 'Try again',
                onAction: () => unawaited(_historyController.retry()),
              )
            : items == null || items.isEmpty
            ? _HistoryMessage(
                icon: Icons.history_toggle_off_rounded,
                message: _pt(context)
                    ? 'Seu histórico de leitura de mangá ainda está vazio.'
                    : 'Your manga reading history is still empty.',
              )
            : RefreshIndicator(
                onRefresh: _refreshHistory,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _HistoryCard(
                      item: item,
                      onOpen: _open,
                      opening: _openingChapterId == item.canonicalChapterId,
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.onOpen,
    required this.opening,
  });

  final MangaReadingHistoryItem item;
  final ValueChanged<MangaReadingHistoryItem> onOpen;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapterLabel = _chapterLabel(context, item);
    final pageLabel = _pageLabel(context, item);
    final timestamp = _timestamp(item.lastReadAt);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        enabled: !opening,
        onTap: opening ? null : () => onOpen(item),
        leading: CircleAvatar(
          backgroundImage: item.coverUrl == null
              ? null
              : NetworkImage(item.coverUrl!),
          child: item.coverUrl == null
              ? Icon(
                  item.completed
                      ? Icons.check_rounded
                      : Icons.menu_book_rounded,
                )
              : null,
        ),
        title: Text(
          item.workTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(chapterLabel),
            if (pageLabel != null) Text(pageLabel),
            Text(
              timestamp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        trailing: opening
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  static String _chapterLabel(
    BuildContext context,
    MangaReadingHistoryItem item,
  ) {
    final title = item.chapterTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
    final number = item.chapterNumber;
    if (number != null) {
      final formatted = number == number.truncateToDouble()
          ? number.toInt().toString()
          : number.toString();
      return _pt(context) ? 'Capítulo $formatted' : 'Chapter $formatted';
    }
    return _pt(context) ? 'Capítulo' : 'Chapter';
  }

  static String? _pageLabel(
    BuildContext context,
    MangaReadingHistoryItem item,
  ) {
    final index = item.pageIndex;
    final count = item.pageCount;
    if (index == null || count == null || count <= 0) return null;
    final current = index.clamp(0, count - 1).toInt() + 1;
    return AppLocalizations.of(context).manga.pageProgressLabel(current, count);
  }

  static String _timestamp(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} • $hour:$minute';
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

bool _pt(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'pt';
