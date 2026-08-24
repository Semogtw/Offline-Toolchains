import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared download job stays domain-neutral and adapters preserve states',
    () {
      final core = File(
        'packages/goanime_core/lib/src/media/media_download_job.dart',
      ).readAsStringSync();
      final anime = File(
        'lib/services/media/anime_download_job_adapter.dart',
      ).readAsStringSync();
      final manga = File(
        'lib/services/media/manga_download_job_adapter.dart',
      ).readAsStringSync();

      expect(core, contains('MediaDownloadJob<TPayload>'));
      expect(core, contains('verifying'));
      expect(core, isNot(contains('DownloadItem')));
      expect(core, isNot(contains('MangaDownloadRecord')));
      expect(core, isNot(contains('Episode')));
      expect(core, isNot(contains('Chapter')));

      expect(anime, contains('DownloadStatus.downloading'));
      expect(anime, contains('MediaDownloadJobPhase.transferring'));
      expect(anime, isNot(contains('MangaDownloadState')));

      expect(manga, contains('MangaDownloadState.resolving'));
      expect(manga, contains('MediaDownloadJobPhase.resolving'));
      expect(manga, contains('MangaDownloadState.verifying'));
      expect(manga, contains('MediaDownloadJobPhase.verifying'));
      expect(manga, isNot(contains('DownloadStatus')));
    },
  );
}
