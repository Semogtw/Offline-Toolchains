import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/download/download_models.dart';
import 'package:goanime/services/media/anime_download_job_adapter.dart';
import 'package:goanime_core/goanime_core.dart';

void main() {
  test(
    'maps Anime download lifecycle and progress without changing semantics',
    () {
      final item = DownloadItem(
        id: 'download-1',
        animeId: 'anime-1',
        animeName: 'Anime',
        episodeNumber: '3',
        episodeTitle: 'Episode 3',
        videoUrl: 'https://example.test/video',
        thumbnailUrl: 'https://example.test/thumb',
        status: DownloadStatus.downloading,
        progress: 0.5,
        bytesDownloaded: 512,
        totalBytes: 1024,
      );

      final job = const AnimeDownloadJobAdapter().fromItem(item);

      expect(job.mediaKind, MediaKind.anime);
      expect(job.jobId, 'download-1');
      expect(job.entityId, 'anime-1');
      expect(job.phase, MediaDownloadJobPhase.transferring);
      expect(job.progress.bytesReceived, 512);
      expect(job.progress.expectedBytes, 1024);
      expect(job.progress.fraction, 0.5);
      expect(job.payload.item, same(item));
    },
  );

  test(
    'does not invent an expected byte count when Anime total is unknown',
    () {
      final item = DownloadItem(
        id: 'download-2',
        animeId: 'anime-2',
        animeName: 'Anime',
        episodeNumber: '1',
        episodeTitle: 'Episode 1',
        videoUrl: 'https://example.test/video',
        thumbnailUrl: '',
        status: DownloadStatus.queued,
        progress: 0,
        bytesDownloaded: 32,
        totalBytes: 0,
      );

      final job = const AnimeDownloadJobAdapter().fromItem(item);

      expect(job.progress.bytesReceived, 32);
      expect(job.progress.expectedBytes, isNull);
      expect(job.progress.fraction, 0);
    },
  );

  test('maps every Anime state to its shared lifecycle phase', () {
    const expected = <DownloadStatus, MediaDownloadJobPhase>{
      DownloadStatus.queued: MediaDownloadJobPhase.queued,
      DownloadStatus.downloading: MediaDownloadJobPhase.transferring,
      DownloadStatus.paused: MediaDownloadJobPhase.paused,
      DownloadStatus.completed: MediaDownloadJobPhase.completed,
      DownloadStatus.failed: MediaDownloadJobPhase.failed,
      DownloadStatus.cancelled: MediaDownloadJobPhase.cancelled,
    };

    for (final entry in expected.entries) {
      expect(AnimeDownloadJobAdapter.phaseFor(entry.key), entry.value);
    }
  });
}
