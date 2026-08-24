import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/media/manga_user_state_sync_sink.dart';
import 'package:goanime_core/goanime_core.dart';

void main() {
  test(
    'accepts Manga events while declaring there is no remote backend',
    () async {
      const sink = MangaUserStateSyncSink();
      final event = UserMediaStateEvent<dynamic>(
        mediaKind: MediaKind.manga,
        entityId: 'manga-1',
        category: UserMediaStateCategory.progress,
        updatedAt: DateTime.utc(2026, 8, 24, 13),
        tombstone: false,
        partial: true,
        payload: 'local-progress',
      );

      expect(sink.mediaKind, MediaKind.manga);
      expect(sink.supportsRemoteBackend, isFalse);
      await expectLater(
        sink.sync(<UserMediaStateEvent<dynamic>>[event]),
        completes,
      );
    },
  );

  test('rejects Anime events instead of pretending to sync them', () async {
    const sink = MangaUserStateSyncSink();
    final event = UserMediaStateEvent<dynamic>(
      mediaKind: MediaKind.anime,
      entityId: 'anime-1',
      category: UserMediaStateCategory.library,
      updatedAt: DateTime.utc(2026, 8, 24, 13),
      tombstone: false,
      partial: true,
      payload: 'anime',
    );

    await expectLater(
      sink.sync(<UserMediaStateEvent<dynamic>>[event]),
      throwsArgumentError,
    );
  });
}
