import 'dart:convert';

import 'package:goanime_core/goanime_core.dart';
import 'package:sqflite/sqflite.dart';

import 'manga_availability_models.dart';
import 'storage/manga_library_repository.dart';
import 'storage/manga_progress_repository.dart';

final class MangaBrowseChapterPosition {
  const MangaBrowseChapterPosition({
    required this.canonicalChapterId,
    required this.number,
  });

  final String canonicalChapterId;
  final double? number;
}

final class MangaBrowseLocalState {
  MangaBrowseLocalState({
    required Map<String, MangaLibraryStatus> libraryStatusByWorkId,
    required Map<String, MangaChapterProgress> latestProgressByWorkId,
    required Map<String, List<MangaBrowseChapterPosition>> chaptersByWorkId,
    required Map<String, MangaWorkMetadata> metadataByWorkId,
    required Map<String, MangaWork> worksById,
  }) : libraryStatusByWorkId = Map.unmodifiable(libraryStatusByWorkId),
       latestProgressByWorkId = Map.unmodifiable(latestProgressByWorkId),
       chaptersByWorkId = Map.unmodifiable({
         for (final entry in chaptersByWorkId.entries)
           entry.key: List.unmodifiable(entry.value),
       }),
       metadataByWorkId = Map.unmodifiable(metadataByWorkId),
       worksById = Map.unmodifiable(worksById);

  final Map<String, MangaLibraryStatus> libraryStatusByWorkId;
  final Map<String, MangaChapterProgress> latestProgressByWorkId;
  final Map<String, List<MangaBrowseChapterPosition>> chaptersByWorkId;
  final Map<String, MangaWorkMetadata> metadataByWorkId;
  final Map<String, MangaWork> worksById;
}

final class MangaBrowseLocalStateLoader {
  const MangaBrowseLocalStateLoader();

  Future<MangaBrowseLocalState> load(DatabaseExecutor database) async {
    final libraryRows = await database.query(
      'manga_library',
      orderBy: 'updatedAt DESC, workId ASC',
    );
    final progressRows = await database.query(
      'manga_progress',
      orderBy: 'lastReadAt DESC, workId ASC, canonicalChapterId ASC',
    );
    final chapterRows = await database.query(
      'manga_canonical_chapters',
      columns: ['canonicalChapterId', 'workId', 'number'],
      orderBy:
          'workId ASC, number IS NULL ASC, number ASC, canonicalChapterId ASC',
    );
    final workRows = await database.query('manga_works', orderBy: 'workId ASC');
    final externalRows = await database.query(
      'manga_external_ids',
      orderBy: 'workId ASC, namespace ASC, externalId ASC',
    );

    final libraryStatusByWorkId = <String, MangaLibraryStatus>{};
    for (final row in libraryRows) {
      final workId = row['workId'] as String?;
      final status = _libraryStatus(row['status']);
      if (workId != null && workId.isNotEmpty && status != null) {
        libraryStatusByWorkId.putIfAbsent(workId, () => status);
      }
    }

    final latestProgressByWorkId = <String, MangaChapterProgress>{};
    for (final row in progressRows) {
      final workId = row['workId'] as String?;
      if (workId == null ||
          workId.isEmpty ||
          latestProgressByWorkId.containsKey(workId)) {
        continue;
      }
      final progress = _progressFromRow(row);
      if (progress != null) latestProgressByWorkId[workId] = progress;
    }

    final chaptersByWorkId = <String, List<MangaBrowseChapterPosition>>{};
    for (final row in chapterRows) {
      final workId = row['workId'] as String?;
      final chapterId = row['canonicalChapterId'] as String?;
      if (workId == null ||
          workId.isEmpty ||
          chapterId == null ||
          chapterId.isEmpty) {
        continue;
      }
      final number = switch (row['number']) {
        final num value => value.toDouble(),
        _ => null,
      };
      chaptersByWorkId
          .putIfAbsent(workId, () => <MangaBrowseChapterPosition>[])
          .add(
            MangaBrowseChapterPosition(
              canonicalChapterId: chapterId,
              number: number,
            ),
          );
    }

    final externalIdsByWorkId = <String, List<MangaExternalId>>{};
    for (final row in externalRows) {
      final workId = row['workId'] as String?;
      final namespace = row['namespace'] as String?;
      final externalId = row['externalId'] as String?;
      if (workId == null ||
          workId.isEmpty ||
          namespace == null ||
          namespace.isEmpty ||
          externalId == null ||
          externalId.isEmpty) {
        continue;
      }
      externalIdsByWorkId
          .putIfAbsent(workId, () => <MangaExternalId>[])
          .add(MangaExternalId(namespace: namespace, value: externalId));
    }

    final metadataByWorkId = <String, MangaWorkMetadata>{};
    final worksById = <String, MangaWork>{};
    for (final row in workRows) {
      final workId = row['workId'] as String?;
      final canonicalTitle = row['canonicalTitle'] as String?;
      if (workId == null ||
          workId.isEmpty ||
          canonicalTitle == null ||
          canonicalTitle.isEmpty) {
        continue;
      }
      worksById[workId] = MangaWork(
        workId: workId,
        canonicalTitle: canonicalTitle,
        alternativeTitles: _decodeStringList(row['alternativeTitlesJson']),
        coverUrl: row['coverUrl'] as String?,
        authors: _decodeStringList(row['authorsJson']),
        externalIds: List.unmodifiable(
          externalIdsByWorkId[workId] ?? const <MangaExternalId>[],
        ),
      );
      metadataByWorkId[workId] = MangaWorkMetadata(
        artists: _decodeStringList(row['artistsJson']),
        genres: _decodeStringList(row['genresJson']),
        synopsis: row['synopsis'] as String?,
        format: _format(row['format']),
        status: _publicationStatus(row['status']),
        score: switch (row['score']) {
          final num value => value.toDouble(),
          _ => null,
        },
        countryOfOrigin: row['countryOfOrigin'] as String?,
      );
    }

    return MangaBrowseLocalState(
      libraryStatusByWorkId: libraryStatusByWorkId,
      latestProgressByWorkId: latestProgressByWorkId,
      chaptersByWorkId: chaptersByWorkId,
      metadataByWorkId: metadataByWorkId,
      worksById: worksById,
    );
  }

  static MangaChapterProgress? _progressFromRow(Map<String, Object?> row) {
    final workId = row['workId'] as String?;
    final canonicalChapterId = row['canonicalChapterId'] as String?;
    final completed = row['completed'] as int?;
    final lastReadAtValue = row['lastReadAt'] as String?;
    final lastReadAt = lastReadAtValue == null
        ? null
        : DateTime.tryParse(lastReadAtValue);
    if (workId == null ||
        workId.isEmpty ||
        canonicalChapterId == null ||
        canonicalChapterId.isEmpty ||
        completed == null ||
        lastReadAt == null) {
      return null;
    }

    final pageIndex = row['pageIndex'] as int?;
    final sourceId = row['sourceId'] as String?;
    final mangaId = row['mangaId'] as String?;
    final chapterId = row['chapterId'] as String?;
    final hasBookmark =
        sourceId != null &&
        sourceId.isNotEmpty &&
        mangaId != null &&
        mangaId.isNotEmpty &&
        chapterId != null &&
        chapterId.isNotEmpty &&
        pageIndex != null;

    return MangaChapterProgress(
      workId: workId,
      canonicalChapterId: canonicalChapterId,
      completed: completed == 1,
      lastReadAt: lastReadAt,
      bookmark: hasBookmark
          ? MangaVariantBookmark(
              sourceId: sourceId,
              mangaId: mangaId,
              chapterId: chapterId,
              pageIndex: pageIndex,
              pageCount: row['pageCount'] as int?,
            )
          : null,
    );
  }

  static MangaLibraryStatus? _libraryStatus(Object? value) {
    if (value is! String) return null;
    for (final status in MangaLibraryStatus.values) {
      if (status.name == value) return status;
    }
    return null;
  }

  static MangaFormat _format(Object? value) {
    if (value is String) {
      for (final format in MangaFormat.values) {
        if (format.name == value) return format;
      }
    }
    return MangaFormat.unknown;
  }

  static MangaPublicationStatus _publicationStatus(Object? value) {
    if (value is String) {
      for (final status in MangaPublicationStatus.values) {
        if (status.name == value) return status;
      }
    }
    return MangaPublicationStatus.unknown;
  }

  static List<String> _decodeStringList(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return const [];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
