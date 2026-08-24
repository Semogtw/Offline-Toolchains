import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Anime download manager delegates queue concurrency to shared coordinator',
    () {
      final source = File(
        'lib/services/download/download_queue_manager.dart',
      ).readAsStringSync();

      expect(source, contains('DownloadQueueCoordinator<String>'));
      expect(source, contains('DownloadConcurrencyPolicy'));
      expect(source, isNot(contains('int _activeDownloadCount')));
      expect(source, isNot(contains('int _maxConcurrentDownloads')));
    },
  );

  test('Anime queued cancellation removes shared pending work', () {
    final source = File(
      'lib/services/download/download_queue_manager.dart',
    ).readAsStringSync();

    expect(source, contains('_queueCoordinator.cancel(id)'));
    expect(source, contains('_queueCoordinator.isKnown(download.id)'));
  });
}
