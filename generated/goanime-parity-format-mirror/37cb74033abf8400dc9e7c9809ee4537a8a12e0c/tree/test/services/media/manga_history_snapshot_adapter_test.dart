import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/manga/manga_history_data_source.dart';
import 'package:goanime/services/media/manga_history_snapshot_adapter.dart';

void main() {
  test(
    'MangaHistorySnapshotAdapter delegates every load to MangaHistoryDataSource',
    () async {
      final source = _CountingMangaHistoryDataSource();
      final adapter = MangaHistorySnapshotAdapter(source);

      expect(await adapter.load(forceRefresh: false), hasLength(1));
      expect(await adapter.load(forceRefresh: true), hasLength(1));
      expect(source.loadCalls, 2);
    },
  );
}

final class _CountingMangaHistoryDataSource implements MangaHistoryDataSource {
  int loadCalls = 0;

  @override
  Future<List<MangaReadingHistoryItem>> load({int limit = 100}) async {
    loadCalls += 1;
    return <MangaReadingHistoryItem>[
      MangaReadingHistoryItem(
        workId: 'work-1',
        workTitle: 'Stable Manga',
        canonicalChapterId: 'chapter-1',
        completed: false,
        lastReadAt: DateTime.utc(2026, 8, 24),
      ),
    ];
  }
}
