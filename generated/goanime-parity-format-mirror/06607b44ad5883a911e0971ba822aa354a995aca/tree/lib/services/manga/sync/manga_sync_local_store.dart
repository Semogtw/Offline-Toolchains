import 'package:sqflite/sqflite.dart';

import '../storage/manga_database.dart';
import 'manga_sync_record.dart';

final class MangaSyncLocalStore {
  MangaSyncLocalStore({MangaDatabase? database})
    : _database = database ?? MangaDatabase.instance;

  final MangaDatabase _database;

  Future<Map<String, MangaSyncRecord>> loadAll() async {
    final records = <String, MangaSyncRecord>{};
    final database = await _database.database;

    for (final row in await database.rawQuery(_librarySelect)) {
      final record = _libraryRecordFromRow(row);
      records[record.recordKey] = record;
    }
    for (final row in await database.rawQuery(_progressSelect)) {
      final record = _progressRecordFromRow(row);
      records[record.recordKey] = record;
    }
    for (final row in await database.rawQuery(_readerPreferenceSelect)) {
      final record = _readerPreferenceRecordFromRow(row);
      records[record.recordKey] = record;
    }
    for (final row in await database.rawQuery(_sourcePreferenceSelect)) {
      final record = _sourcePreferenceRecordFromRow(row);
      records[record.recordKey] = record;
    }
    for (final row in await database.query('manga_global_preferences')) {
      final record = _globalPreferenceRecordFromRow(row);
      records[record.recordKey] = record;
    }

    return records;
  }

  Future<MangaSyncRecord?> libraryRecord(String workId) async {
    final database = await _database.database;
    final rows = await database.rawQuery(
      '$_librarySelect WHERE l.workId = ? LIMIT 1',
      <Object?>[workId],
    );
    return rows.isEmpty ? null : _libraryRecordFromRow(rows.single);
  }

  Future<MangaSyncRecord?> progressRecord(
    String workId,
    String canonicalChapterId,
  ) async {
    final database = await _database.database;
    final rows = await database.rawQuery(
      '$_progressSelect WHERE p.workId = ? AND p.canonicalChapterId = ? LIMIT 1',
      <Object?>[workId, canonicalChapterId],
    );
    return rows.isEmpty ? null : _progressRecordFromRow(rows.single);
  }

  Future<MangaSyncRecord?> readerPreferenceRecord(String workId) async {
    final database = await _database.database;
    final rows = await database.rawQuery(
      '$_readerPreferenceSelect WHERE r.workId = ? LIMIT 1',
      <Object?>[workId],
    );
    return rows.isEmpty ? null : _readerPreferenceRecordFromRow(rows.single);
  }

  Future<MangaSyncRecord?> sourcePreferenceRecord(String workId) async {
    final database = await _database.database;
    final rows = await database.rawQuery(
      '$_sourcePreferenceSelect WHERE s.workId = ? LIMIT 1',
      <Object?>[workId],
    );
    return rows.isEmpty ? null : _sourcePreferenceRecordFromRow(rows.single);
  }

  Future<MangaSyncRecord?> globalPreferenceRecord(String preferenceKey) async {
    final database = await _database.database;
    final rows = await database.query(
      'manga_global_preferences',
      where: 'preferenceKey = ?',
      whereArgs: <Object?>[preferenceKey],
      limit: 1,
    );
    return rows.isEmpty ? null : _globalPreferenceRecordFromRow(rows.single);
  }

  Future<void> applyRemote(MangaSyncRecord record) async {
    final database = await _database.database;
    await database.transaction((transaction) async {
      if (!record.tombstone && record.workId != null) {
        await _ensureWork(transaction, record);
      }
      if (!record.tombstone && record.kind == MangaSyncRecordKind.progress) {
        await _ensureChapter(transaction, record);
      }

      switch (record.kind) {
        case MangaSyncRecordKind.library:
          await _applyLibrary(transaction, record);
          break;
        case MangaSyncRecordKind.progress:
          await _applyProgress(transaction, record);
          break;
        case MangaSyncRecordKind.readerPreference:
          await _applyReaderPreference(transaction, record);
          break;
        case MangaSyncRecordKind.sourcePreference:
          await _applySourcePreference(transaction, record);
          break;
        case MangaSyncRecordKind.globalPreference:
          await _applyGlobalPreference(transaction, record);
          break;
      }
    });
  }

  Future<void> _ensureWork(
    DatabaseExecutor database,
    MangaSyncRecord record,
  ) async {
    final workId = record.workId!;
    final existing = await database.query(
      'manga_works',
      columns: <String>['workId', 'coverUrl'],
      where: 'workId = ?',
      whereArgs: <Object?>[workId],
      limit: 1,
    );
    if (existing.isEmpty) {
      final timestamp = record.updatedAt.toIso8601String();
      await database.insert('manga_works', <String, Object?>{
        'workId': workId,
        'canonicalTitle':
            _nonEmptyString(record.payload['canonicalTitle']) ?? workId,
        'alternativeTitlesJson': '[]',
        'coverUrl': _nonEmptyString(record.payload['coverUrl']),
        'authorsJson': '[]',
        'createdAt':
            _nonEmptyString(record.payload['workCreatedAt']) ?? timestamp,
        'updatedAt': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return;
    }

    final remoteCover = _nonEmptyString(record.payload['coverUrl']);
    if (remoteCover != null && existing.single['coverUrl'] == null) {
      await database.update(
        'manga_works',
        <String, Object?>{'coverUrl': remoteCover},
        where: 'workId = ?',
        whereArgs: <Object?>[workId],
      );
    }
  }

  Future<void> _ensureChapter(
    DatabaseExecutor database,
    MangaSyncRecord record,
  ) async {
    final chapterId = record.canonicalChapterId!;
    final existing = await database.query(
      'manga_canonical_chapters',
      columns: <String>['canonicalChapterId'],
      where: 'canonicalChapterId = ?',
      whereArgs: <Object?>[chapterId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    await database.insert('manga_canonical_chapters', <String, Object?>{
      'canonicalChapterId': chapterId,
      'workId': record.workId,
      'title': _nullableScalar(record.payload['chapterTitle']),
      'number': _nullableScalar(record.payload['chapterNumber']),
      'volume': _nullableScalar(record.payload['chapterVolume']),
      'kind': _nonEmptyString(record.payload['chapterKind']) ?? 'regular',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _applyLibrary(
    DatabaseExecutor database,
    MangaSyncRecord record,
  ) async {
    final workId = record.workId;
    if (workId == null) return;
    if (record.tombstone) {
      await database.delete(
        'manga_library',
        where: 'workId = ?',
        whereArgs: <Object?>[workId],
      );
      return;
    }

    final status = _nonEmptyString(record.payload['status']);
    if (!_libraryStatuses.contains(status)) return;
    final timestamp = record.updatedAt.toIso8601String();
    final values = <String, Object?>{'status': status, 'updatedAt': timestamp};
    final updated = await database.update(
      'manga_library',
      values,
      where: 'workId = ?',
      whereArgs: <Object?>[workId],
    );
    if (updated == 0) {
      await database.insert('manga_library', <String, Object?>{
        'workId': workId,
        'status': status,
        'addedAt': _nonEmptyString(record.payload['addedAt']) ?? timestamp,
        'updatedAt': timestamp,
      });
    }
  }

  Future<void> _applyProgress(
    DatabaseExecutor database,
    MangaSyncRecord record,
  ) async {
    final workId = record.workId;
    final chapterId = record.canonicalChapterId;
    if (workId == null || chapterId == null) return;
    if (record.tombstone) {
      await database.delete(
        'manga_progress',
        where: 'workId = ? AND canonicalChapterId = ?',
        whereArgs: <Object?>[workId, chapterId],
      );
      return;
    }

    final sourceId = _nonEmptyString(record.payload['sourceId']);
    final mangaId = _nonEmptyString(record.payload['mangaId']);
    final sourceChapterId = _nonEmptyString(record.payload['chapterId']);
    final pageIndex = _intValue(record.payload['pageIndex']);
    final pageCount = _intValue(record.payload['pageCount']);
    final hasCompleteBookmark =
        sourceId != null &&
        mangaId != null &&
        sourceChapterId != null &&
        pageIndex != null &&
        pageIndex >= 0 &&
        (pageCount == null || (pageCount > 0 && pageIndex < pageCount));
    final timestamp = record.updatedAt.toIso8601String();
    final values = <String, Object?>{
      'completed': record.payload['completed'] == true ? 1 : 0,
      'lastReadAt': timestamp,
      'sourceId': hasCompleteBookmark ? sourceId : null,
      'mangaId': hasCompleteBookmark ? mangaId : null,
      'chapterId': hasCompleteBookmark ? sourceChapterId : null,
      'pageIndex': hasCompleteBookmark ? pageIndex : null,
      'pageCount': hasCompleteBookmark ? pageCount : null,
    };
    final updated = await database.update(
      'manga_progress',
      values,
      where: 'workId = ? AND canonicalChapterId = ?',
      whereArgs: <Object?>[workId, chapterId],
    );
    if (updated == 0) {
      await database.insert('manga_progress', <String, Object?>{
        'workId': workId,
        'canonicalChapterId': chapterId,
        ...values,
      });
    }
  }

  Future<void> _applyReaderPreference(
    DatabaseExecutor database,
    MangaSyncRecord record,
  ) async {
    final workId = record.workId;
    if (workId == null) return;
    if (record.tombstone) {
      await database.delete(
        'manga_reader_preferences',
        where: 'workId = ?',
        whereArgs: <Object?>[workId],
      );
      return;
    }
    final mode = _nonEmptyString(record.payload['readerMode']);
    if (!_readerModes.contains(mode)) return;
    await _upsertSingleKey(
      database,
      table: 'manga_reader_preferences',
      key: 'workId',
      keyValue: workId,
      values: <String, Object?>{
        'readerMode': mode,
        'updatedAt': record.updatedAt.toIso8601String(),
      },
    );
  }

  Future<void> _applySourcePreference(
    DatabaseExecutor database,
    MangaSyncRecord record,
  ) async {
    final workId = record.workId;
    if (workId == null) return;
    if (record.tombstone) {
      await database.delete(
        'manga_source_preferences',
        where: 'workId = ?',
        whereArgs: <Object?>[workId],
      );
      return;
    }
    final mode = _nonEmptyString(record.payload['mode']);
    final sourceId = _nonEmptyString(record.payload['sourceId']);
    if (!_sourceModes.contains(mode)) return;
    if ((mode == 'automatic' && sourceId != null) ||
        (mode != 'automatic' && sourceId == null)) {
      return;
    }
    await _upsertSingleKey(
      database,
      table: 'manga_source_preferences',
      key: 'workId',
      keyValue: workId,
      values: <String, Object?>{
        'mode': mode,
        'sourceId': sourceId,
        'updatedAt': record.updatedAt.toIso8601String(),
      },
    );
  }

  Future<void> _applyGlobalPreference(
    DatabaseExecutor database,
    MangaSyncRecord record,
  ) async {
    final key = _nonEmptyString(record.payload['preferenceKey']);
    if (key == null) return;
    if (record.tombstone) {
      await database.delete(
        'manga_global_preferences',
        where: 'preferenceKey = ?',
        whereArgs: <Object?>[key],
      );
      return;
    }
    final value = _nonEmptyString(record.payload['preferenceValue']);
    if (value == null) return;
    await _upsertSingleKey(
      database,
      table: 'manga_global_preferences',
      key: 'preferenceKey',
      keyValue: key,
      values: <String, Object?>{
        'preferenceValue': value,
        'updatedAt': record.updatedAt.toIso8601String(),
      },
    );
  }

  Future<void> _upsertSingleKey(
    DatabaseExecutor database, {
    required String table,
    required String key,
    required String keyValue,
    required Map<String, Object?> values,
  }) async {
    final updated = await database.update(
      table,
      values,
      where: '$key = ?',
      whereArgs: <Object?>[keyValue],
    );
    if (updated == 0) {
      await database.insert(table, <String, Object?>{key: keyValue, ...values});
    }
  }

  MangaSyncRecord _libraryRecordFromRow(Map<String, Object?> row) {
    final workId = row['workId']! as String;
    return MangaSyncRecord(
      recordKey: MangaSyncRecordKeys.library(workId),
      kind: MangaSyncRecordKind.library,
      workId: workId,
      updatedAt: DateTime.parse(row['updatedAt']! as String),
      tombstone: false,
      payload: <String, dynamic>{
        'status': row['status'],
        'addedAt': row['addedAt'],
        ..._workPayload(row),
      },
    );
  }

  MangaSyncRecord _progressRecordFromRow(Map<String, Object?> row) {
    final workId = row['workId']! as String;
    final canonicalChapterId = row['canonicalChapterId']! as String;
    return MangaSyncRecord(
      recordKey: MangaSyncRecordKeys.progress(workId, canonicalChapterId),
      kind: MangaSyncRecordKind.progress,
      workId: workId,
      canonicalChapterId: canonicalChapterId,
      updatedAt: DateTime.parse(row['lastReadAt']! as String),
      tombstone: false,
      payload: <String, dynamic>{
        'completed': row['completed'] == 1,
        'sourceId': row['sourceId'],
        'mangaId': row['mangaId'],
        'chapterId': row['chapterId'],
        'pageIndex': row['pageIndex'],
        'pageCount': row['pageCount'],
        'chapterTitle': row['chapterTitle'],
        'chapterNumber': row['chapterNumber'],
        'chapterVolume': row['chapterVolume'],
        'chapterKind': row['chapterKind'],
        ..._workPayload(row),
      },
    );
  }

  MangaSyncRecord _readerPreferenceRecordFromRow(Map<String, Object?> row) {
    final workId = row['workId']! as String;
    return MangaSyncRecord(
      recordKey: MangaSyncRecordKeys.readerPreference(workId),
      kind: MangaSyncRecordKind.readerPreference,
      workId: workId,
      updatedAt: DateTime.parse(row['updatedAt']! as String),
      tombstone: false,
      payload: <String, dynamic>{
        'readerMode': row['readerMode'],
        ..._workPayload(row),
      },
    );
  }

  MangaSyncRecord _sourcePreferenceRecordFromRow(Map<String, Object?> row) {
    final workId = row['workId']! as String;
    return MangaSyncRecord(
      recordKey: MangaSyncRecordKeys.sourcePreference(workId),
      kind: MangaSyncRecordKind.sourcePreference,
      workId: workId,
      updatedAt: DateTime.parse(row['updatedAt']! as String),
      tombstone: false,
      payload: <String, dynamic>{
        'mode': row['mode'],
        'sourceId': row['sourceId'],
        ..._workPayload(row),
      },
    );
  }

  MangaSyncRecord _globalPreferenceRecordFromRow(Map<String, Object?> row) {
    final key = row['preferenceKey']! as String;
    return MangaSyncRecord(
      recordKey: MangaSyncRecordKeys.globalPreference(key),
      kind: MangaSyncRecordKind.globalPreference,
      updatedAt: DateTime.parse(row['updatedAt']! as String),
      tombstone: false,
      payload: <String, dynamic>{
        'preferenceKey': key,
        'preferenceValue': row['preferenceValue'],
      },
    );
  }

  Map<String, dynamic> _workPayload(Map<String, Object?> row) {
    return <String, dynamic>{
      'canonicalTitle': row['canonicalTitle'],
      'coverUrl': row['coverUrl'],
      'workCreatedAt': row['workCreatedAt'],
    };
  }

  static const String _workColumns =
      'w.canonicalTitle AS canonicalTitle, '
      'w.coverUrl AS coverUrl, '
      'w.createdAt AS workCreatedAt';

  static const String _librarySelect =
      'SELECT l.workId, l.status, l.addedAt, l.updatedAt, $_workColumns '
      'FROM manga_library l JOIN manga_works w ON w.workId = l.workId';

  static const String _progressSelect =
      'SELECT p.workId, p.canonicalChapterId, p.completed, p.lastReadAt, '
      'p.sourceId, p.mangaId, p.chapterId, p.pageIndex, p.pageCount, '
      'c.title AS chapterTitle, c.number AS chapterNumber, '
      'c.volume AS chapterVolume, c.kind AS chapterKind, $_workColumns '
      'FROM manga_progress p '
      'JOIN manga_works w ON w.workId = p.workId '
      'JOIN manga_canonical_chapters c '
      'ON c.canonicalChapterId = p.canonicalChapterId';

  static const String _readerPreferenceSelect =
      'SELECT r.workId, r.readerMode, r.updatedAt, $_workColumns '
      'FROM manga_reader_preferences r '
      'JOIN manga_works w ON w.workId = r.workId';

  static const String _sourcePreferenceSelect =
      'SELECT s.workId, s.mode, s.sourceId, s.updatedAt, $_workColumns '
      'FROM manga_source_preferences s '
      'JOIN manga_works w ON w.workId = s.workId';

  static const Set<String?> _libraryStatuses = <String?>{
    'reading',
    'planToRead',
    'completed',
    'onHold',
    'dropped',
  };
  static const Set<String?> _readerModes = <String?>{
    'continuousVertical',
    'pagedLtr',
    'pagedRtl',
    'pagedVertical',
  };
  static const Set<String?> _sourceModes = <String?>{
    'automatic',
    'prefer',
    'strict',
  };
}

String? _nonEmptyString(Object? value) {
  final encoded = value?.toString();
  if (encoded == null || encoded.trim().isEmpty) return null;
  return encoded;
}

Object? _nullableScalar(Object? value) {
  if (value == null || value is num || value is String) return value;
  return value.toString();
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
