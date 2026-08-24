import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Manga download queue delegates lifecycle scheduling to shared coordinator',
    () {
      final source = File(
        'lib/services/manga/download/manga_download_queue.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('DownloadQueueCoordinator<MangaDownloadChapterJobKey>'),
      );
      expect(source, contains('DownloadConcurrencyPolicy'));
      expect(source, isNot(contains('List<_QueuedChapterJob>')));
      expect(
        source,
        isNot(contains('Set<MangaDownloadChapterJobKey> _active')),
      );
    },
  );

  test(
    'Manga compatibility surface keeps pending-only cancellation semantics',
    () {
      final source = File(
        'lib/services/manga/download/manga_download_queue.dart',
      ).readAsStringSync();

      expect(source, contains('MangaDownloadQueueCancelledException'));
      expect(source, contains('_coordinator.isActive(key)'));
      expect(source, contains('_coordinator.cancel(key)'));
    },
  );
}
