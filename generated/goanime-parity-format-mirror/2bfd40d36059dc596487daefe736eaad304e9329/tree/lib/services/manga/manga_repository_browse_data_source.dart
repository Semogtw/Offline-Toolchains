import 'manga_availability_models.dart';
import 'manga_availability_service.dart';
import 'manga_browse_data_source.dart';
import 'manga_browse_local_state_loader.dart';
import 'metadata/manga_relevance_service.dart';
import 'storage/manga_database.dart';
import 'storage/manga_library_repository.dart';
import 'storage/manga_progress_repository.dart';

final class MangaRepositoryBrowseDataSource implements MangaBrowseDataSource {
  MangaRepositoryBrowseDataSource({
    required MangaAvailabilityCatalogSource availability,
    MangaBrowseMetadataResolver? metadataResolver,
    MangaRelevanceService? relevanceService,
    MangaDatabase? database,
    MangaBrowseLocalStateLoader? localStateLoader,
  }) : _availability = availability,
       _metadataResolver = metadataResolver,
       _relevanceService = relevanceService,
       _database = database ?? MangaDatabase.instance,
       _localStateLoader =
           localStateLoader ?? const MangaBrowseLocalStateLoader();

  final MangaAvailabilityCatalogSource _availability;
  final MangaBrowseMetadataResolver? _metadataResolver;
  final MangaRelevanceService? _relevanceService;
  final MangaDatabase _database;
  final MangaBrowseLocalStateLoader _localStateLoader;

  @override
  Future<MangaHomeSnapshot> loadHome() async {
    final state = await _loadState();
    final library = state.items
        .where((item) => item.libraryStatus != null)
        .toList(growable: false);
    final continueReading =
        library
            .where(
              (item) =>
                  item.latestProgress != null &&
                  (!item.latestProgress!.completed || item.unread),
            )
            .toList(growable: false)
          ..sort(_compareLatestProgressDesc);
    final newChapters =
        library.where((item) => item.unread).toList(growable: false)
          ..sort(_compareTitle);
    final availableCatalog =
        state.items
            .where((item) => item.availability.sourceLinks.isNotEmpty)
            .toList(growable: false)
          ..sort(_compareTitle);
    final relevance = await _safeRelevance();

    return MangaHomeSnapshot(
      continueReading: continueReading,
      newChapters: newChapters,
      library: library..sort(_compareTitle),
      availableCatalog: availableCatalog,
      featured: relevance == null
          ? const []
          : MangaRelevanceRanker.rankFeatured(
              availableCatalog,
              relevance.trending,
            ),
      popular: relevance == null
          ? const []
          : MangaRelevanceRanker.rankAvailable(
              availableCatalog,
              relevance.popular,
            ),
      topRated: relevance == null
          ? const []
          : MangaRelevanceRanker.rankAvailable(
              availableCatalog,
              relevance.topRated,
            ),
      trendingManga: relevance == null
          ? const []
          : MangaRelevanceRanker.rankAvailable(
              availableCatalog,
              relevance.trendingManga,
            ),
      trendingManhwa: relevance == null
          ? const []
          : MangaRelevanceRanker.rankAvailable(
              availableCatalog,
              relevance.trendingManhwa,
            ),
      trendingManhua: relevance == null
          ? const []
          : MangaRelevanceRanker.rankAvailable(
              availableCatalog,
              relevance.trendingManhua,
            ),
    );
  }

  @override
  Future<List<MangaBrowseItem>> loadCategories() async {
    final records = _availability.catalogReady
        ? await _safeAllReadable()
        : const <MangaAvailabilityRecord>[];
    final database = await _database.database;
    final localState = await _localStateLoader.load(database);
    final items = <MangaBrowseItem>[];
    for (final record in records) {
      items.add(
        await _itemForRecord(
          record,
          libraryStatus: null,
          localState: localState,
        ),
      );
    }
    items.sort(_compareTitle);
    return items;
  }

  @override
  Future<List<MangaBrowseItem>> loadLibrary() async {
    final state = await _loadState();
    final items =
        state.items
            .where((item) => item.libraryStatus != null)
            .toList(growable: false)
          ..sort(_compareTitle);
    return items;
  }

  Future<_BrowseState> _loadState() async {
    final readable = _availability.catalogReady
        ? await _safeAllReadable()
        : const <MangaAvailabilityRecord>[];
    final byWorkId = <String, MangaAvailabilityRecord>{
      for (final record in readable) record.work.workId: record,
    };

    final database = await _database.database;
    final localState = await _localStateLoader.load(database);

    for (final workId in localState.libraryStatusByWorkId.keys) {
      if (byWorkId.containsKey(workId)) continue;
      final work = localState.worksById[workId];
      if (work == null) continue;
      byWorkId[workId] = MangaAvailabilityRecord(
        work: work,
        sourceLinks: const [],
        evidence: const [],
      );
    }

    final items = <MangaBrowseItem>[];
    for (final record in byWorkId.values) {
      items.add(
        await _itemForRecord(
          record,
          libraryStatus: localState.libraryStatusByWorkId[record.work.workId],
          localState: localState,
        ),
      );
    }
    return _BrowseState(items);
  }

  Future<List<MangaAvailabilityRecord>> _safeAllReadable() async {
    try {
      return await _availability.allReadable();
    } catch (_) {
      return const [];
    }
  }

  Future<MangaRelevanceSnapshot?> _safeRelevance() async {
    final service = _relevanceService;
    if (service == null) return null;
    try {
      return await service.load();
    } catch (_) {
      return null;
    }
  }

  Future<MangaBrowseItem> _itemForRecord(
    MangaAvailabilityRecord record, {
    required MangaLibraryStatus? libraryStatus,
    required MangaBrowseLocalState localState,
  }) async {
    final workId = record.work.workId;
    final chapters =
        localState.chaptersByWorkId[workId] ??
        const <MangaBrowseChapterPosition>[];
    final latestProgress = localState.latestProgressByWorkId[workId];
    final unread = _hasUnreadChapter(
      chapters: chapters,
      latestProgress: latestProgress,
      libraryStatus: libraryStatus,
    );
    final storedMetadata =
        localState.metadataByWorkId[workId] ?? const MangaWorkMetadata();
    final metadata = await _resolveMetadata(
      workId,
      record.metadata.merge(storedMetadata),
    );

    return MangaBrowseItem(
      availability: record,
      metadata: metadata,
      libraryStatus: libraryStatus,
      latestProgress: latestProgress,
      unread: unread,
      // Offline ownership belongs to the later offline/archive child plan.
      offline: false,
    );
  }

  Future<MangaWorkMetadata> _resolveMetadata(
    String workId,
    MangaWorkMetadata metadata,
  ) async {
    final resolver = _metadataResolver;
    if (resolver == null) return metadata;
    try {
      return metadata.merge(await resolver.metadataForWork(workId));
    } catch (_) {
      return metadata;
    }
  }

  static bool _hasUnreadChapter({
    required List<MangaBrowseChapterPosition> chapters,
    required MangaChapterProgress? latestProgress,
    required MangaLibraryStatus? libraryStatus,
  }) {
    if (chapters.isEmpty || libraryStatus == null) return false;
    if (latestProgress == null) return true;

    var progressIndex = -1;
    for (var index = 0; index < chapters.length; index++) {
      if (chapters[index].canonicalChapterId ==
          latestProgress.canonicalChapterId) {
        progressIndex = index;
        break;
      }
    }
    if (progressIndex < 0) return true;
    return progressIndex < chapters.length - 1;
  }

  static int _compareTitle(MangaBrowseItem left, MangaBrowseItem right) {
    final titleOrder = left.availability.work.canonicalTitle
        .toLowerCase()
        .compareTo(right.availability.work.canonicalTitle.toLowerCase());
    if (titleOrder != 0) return titleOrder;
    return left.availability.work.workId.compareTo(
      right.availability.work.workId,
    );
  }

  static int _compareLatestProgressDesc(
    MangaBrowseItem left,
    MangaBrowseItem right,
  ) {
    final leftAt = left.latestProgress?.lastReadAt;
    final rightAt = right.latestProgress?.lastReadAt;
    if (leftAt != null && rightAt != null) {
      final timeOrder = rightAt.compareTo(leftAt);
      if (timeOrder != 0) return timeOrder;
    } else if (leftAt != null) {
      return -1;
    } else if (rightAt != null) {
      return 1;
    }
    return _compareTitle(left, right);
  }
}

final class _BrowseState {
  const _BrowseState(this.items);

  final List<MangaBrowseItem> items;
}
