import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/manga/storage/manga_database.dart';
import 'package:goanime/services/manga/storage/manga_library_repository.dart';
import 'package:goanime/services/manga/storage/manga_progress_repository.dart';
import 'package:goanime/services/manga/sync/manga_sync_local_store.dart';
import 'package:goanime/services/manga/sync/manga_sync_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDirectory;
  late MangaDatabase mangaDatabase;
  late MangaSyncLocalStore store;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'manga_sync_restore_',
    );
    mangaDatabase = MangaDatabase(
      databasePath: '${tempDirectory.path}/manga_library.db',
    );
    store = MangaSyncLocalStore(database: mangaDatabase);
  });

  tearDown(() async {
    await mangaDatabase.close();
    await tempDirectory.delete(recursive: true);
  });

  test('restores remote library state into a fresh Manga database', () async {
    await store.applyRemote(
      MangaSyncRecord(
        recordKey: MangaSyncRecordKeys.library('work-1'),
        kind: MangaSyncRecordKind.library,
        workId: 'work-1',
        updatedAt: DateTime.utc(2026, 8, 24, 22),
        tombstone: false,
        payload: const <String, dynamic>{
          'status': 'reading',
          'canonicalTitle': 'Remote Work',
          'coverUrl': 'https://cdn.example/cover.jpg',
        },
      ),
    );

    final entry = await MangaLibraryRepository(
      database: mangaDatabase,
    ).entryForWork('work-1');
    final works = await (await mangaDatabase.database).query(
      'manga_works',
      where: 'workId = ?',
      whereArgs: <Object?>['work-1'],
    );

    expect(entry?.status, MangaLibraryStatus.reading);
    expect(works.single['canonicalTitle'], 'Remote Work');
    expect(works.single['coverUrl'], 'https://cdn.example/cover.jpg');
  });

  test('restores bookmark progress and the canonical chapter', () async {
    await store.applyRemote(
      MangaSyncRecord(
        recordKey: MangaSyncRecordKeys.progress('work-1', 'chapter-7'),
        kind: MangaSyncRecordKind.progress,
        workId: 'work-1',
        canonicalChapterId: 'chapter-7',
        updatedAt: DateTime.utc(2026, 8, 24, 23),
        tombstone: false,
        payload: const <String, dynamic>{
          'canonicalTitle': 'Remote Work',
          'chapterTitle': 'Chapter 7',
          'chapterNumber': '7',
          'chapterKind': 'regular',
          'completed': false,
          'sourceId': 'ptbr.remote',
          'mangaId': 'source-work-1',
          'chapterId': 'source-chapter-7',
          'pageIndex': 14,
          'pageCount': 30,
        },
      ),
    );

    final progress = await MangaProgressRepository(
      database: mangaDatabase,
    ).progressForChapter('work-1', 'chapter-7');

    expect(progress?.lastReadAt, DateTime.utc(2026, 8, 24, 23));
    expect(progress?.bookmark?.sourceId, 'ptbr.remote');
    expect(progress?.bookmark?.pageIndex, 14);
    expect(progress?.bookmark?.pageCount, 30);
  });
}
