import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/manga/manga_browse_data_source.dart';
import 'package:goanime/services/media/manga_library_snapshot_adapter.dart';

void main() {
  test(
    'MangaLibrarySnapshotAdapter delegates every load to browse Library',
    () async {
      final source = _CountingMangaBrowseDataSource();
      final adapter = MangaLibrarySnapshotAdapter(source);

      expect(await adapter.load(forceRefresh: false), isEmpty);
      expect(await adapter.load(forceRefresh: true), isEmpty);
      expect(source.libraryCalls, 2);
    },
  );
}

final class _CountingMangaBrowseDataSource implements MangaBrowseDataSource {
  int libraryCalls = 0;

  @override
  Future<MangaHomeSnapshot> loadHome() async => const MangaHomeSnapshot();

  @override
  Future<List<MangaBrowseItem>> loadCategories() async => const [];

  @override
  Future<List<MangaBrowseItem>> loadLibrary() async {
    libraryCalls += 1;
    return const <MangaBrowseItem>[];
  }
}
