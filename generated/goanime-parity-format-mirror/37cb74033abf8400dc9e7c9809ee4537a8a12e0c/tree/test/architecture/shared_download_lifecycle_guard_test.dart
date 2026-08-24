import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared download lifecycle stays domain-neutral while adapters preserve semantics',
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
      expect(core, contains('MediaDownloadJobPhase'));
      expect(core, contains('verifying'));
      expect(core, isNot(contains('DownloadItem')));
      expect(core, isNot(contains('MangaDownloadRecord')));
      expect(core, isNot(contains('hls')));
      expect(core, isNot(contains('pdf')));

      expect(anime, contains('MediaKind.anime'));
      expect(anime, contains('DownloadStatus.downloading'));
      expect(anime, contains('MediaDownloadJobPhase.transferring'));
      expect(anime, isNot(contains('MangaDownloadState')));

      expect(manga, contains('MediaKind.manga'));
      expect(manga, contains('MangaDownloadState.resolving'));
      expect(manga, contains('MangaDownloadState.verifying'));
      expect(manga, contains('MediaDownloadJobPhase.verifying'));
      expect(manga, isNot(contains('DownloadStatus.')));
    },
  );
}
