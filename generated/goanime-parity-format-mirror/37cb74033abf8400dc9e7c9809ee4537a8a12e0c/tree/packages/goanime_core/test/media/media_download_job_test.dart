import 'package:goanime_core/goanime_core.dart';
import 'package:test/test.dart';

void main() {
  test('MediaDownloadJob preserves extensible lifecycle and typed payload', () {
    final job = MediaDownloadJob<_Payload>(
      mediaKind: MediaKind.manga,
      jobId: 'download-1',
      entityId: 'work-1',
      phase: MediaDownloadJobPhase.verifying,
      progress: MediaDownloadProgress(
        bytesReceived: 75,
        expectedBytes: 100,
        fraction: 0.75,
      ),
      payload: const _Payload('chapter-package'),
    );

    expect(job.mediaKind, MediaKind.manga);
    expect(job.jobId, 'download-1');
    expect(job.entityId, 'work-1');
    expect(job.phase, MediaDownloadJobPhase.verifying);
    expect(job.progress.bytesReceived, 75);
    expect(job.progress.expectedBytes, 100);
    expect(job.progress.fraction, 0.75);
    expect(job.payload.value, 'chapter-package');
  });

  test(
    'download progress accepts unknown totals without inventing a fraction',
    () {
      final progress = MediaDownloadProgress(bytesReceived: 512);

      expect(progress.expectedBytes, isNull);
      expect(progress.fraction, isNull);
    },
  );

  test('download identities and progress values are validated', () {
    expect(
      () => MediaDownloadJob<int>(
        mediaKind: MediaKind.anime,
        jobId: '',
        entityId: 'anime-1',
        phase: MediaDownloadJobPhase.queued,
        progress: MediaDownloadProgress(bytesReceived: 0),
        payload: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => MediaDownloadJob<int>(
        mediaKind: MediaKind.anime,
        jobId: 'job-1',
        entityId: '',
        phase: MediaDownloadJobPhase.queued,
        progress: MediaDownloadProgress(bytesReceived: 0),
        payload: 1,
      ),
      throwsArgumentError,
    );
    expect(() => MediaDownloadProgress(bytesReceived: -1), throwsArgumentError);
    expect(
      () => MediaDownloadProgress(bytesReceived: 1, expectedBytes: 0),
      throwsArgumentError,
    );
    expect(
      () => MediaDownloadProgress(bytesReceived: 1, fraction: 1.1),
      throwsArgumentError,
    );
  });
}

final class _Payload {
  const _Payload(this.value);

  final String value;
}
