import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/manga/storage/manga_progress_repository.dart';
import 'package:goanime/services/media/manga_progress_event_adapter.dart';
import 'package:goanime_core/goanime_core.dart';

void main() {
  test('maps manga reading progress without changing page units', () {
    final progress = MangaChapterProgress(
      workId: 'work-1',
      canonicalChapterId: 'chapter-7',
      completed: false,
      lastReadAt: DateTime.parse('2026-08-24T08:00:00-03:00'),
      bookmark: MangaVariantBookmark(
        sourceId: 'source-1',
        mangaId: 'remote-work',
        chapterId: 'remote-chapter',
        pageIndex: 12,
        pageCount: 30,
      ),
    );

    final event = const MangaProgressEventAdapter().fromProgress(progress);

    expect(event.mediaKind, MediaKind.manga);
    expect(event.entityId, 'work-1');
    expect(event.unitId, 'chapter-7');
    expect(event.updatedAt, DateTime.utc(2026, 8, 24, 11));
    expect(event.completed, isFalse);
    expect(event.payload.sourceId, 'source-1');
    expect(event.payload.mangaId, 'remote-work');
    expect(event.payload.chapterId, 'remote-chapter');
    expect(event.payload.pageIndex, 12);
    expect(event.payload.pageCount, 30);
  });

  test(
    'logical manga progress remains valid when no physical bookmark exists',
    () {
      final progress = MangaChapterProgress(
        workId: 'work-1',
        canonicalChapterId: 'chapter-8',
        completed: true,
        lastReadAt: DateTime.utc(2026, 8, 24, 12),
      );

      final event = const MangaProgressEventAdapter().fromProgress(progress);

      expect(event.completed, isTrue);
      expect(event.payload.sourceId, isNull);
      expect(event.payload.pageIndex, isNull);
      expect(event.payload.pageCount, isNull);
    },
  );
}
