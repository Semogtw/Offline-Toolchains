import 'package:goanime_core/goanime_core.dart';

import '../manga/download/manga_download_models.dart';

final class MangaDownloadJobPayload {
  MangaDownloadJobPayload({
    required this.parent,
    required Iterable<MangaDownloadChapterRecord> chapters,
  }) : chapters = List<MangaDownloadChapterRecord>.unmodifiable(chapters);

  final MangaDownloadRecord parent;
  final List<MangaDownloadChapterRecord> chapters;
}

final class MangaDownloadJobAdapter {
  const MangaDownloadJobAdapter();

  MediaDownloadJob<MangaDownloadJobPayload> fromRecord({
    required MangaDownloadRecord parent,
    required Iterable<MangaDownloadChapterRecord> chapters,
  }) {
    final chapterList = chapters.toList(growable: false);
    var bytesReceived = 0;
    var expectedBytes = 0;
    var hasKnownTotal = chapterList.isNotEmpty;

    for (final chapter in chapterList) {
      bytesReceived += chapter.bytesReceived;
      final expected = chapter.expectedBytes;
      if (expected == null || expected <= 0) {
        hasKnownTotal = false;
      } else {
        expectedBytes += expected;
      }
    }

    final total = hasKnownTotal ? expectedBytes : null;
    final fraction = total == null
        ? null
        : (bytesReceived / total).clamp(0.0, 1.0).toDouble();

    return MediaDownloadJob<MangaDownloadJobPayload>(
      mediaKind: MediaKind.manga,
      jobId: parent.downloadId,
      entityId: parent.workId,
      phase: phaseFor(parent.state),
      progress: MediaDownloadProgress(
        bytesReceived: bytesReceived,
        expectedBytes: total,
        fraction: fraction,
      ),
      payload: MangaDownloadJobPayload(parent: parent, chapters: chapterList),
    );
  }

  static MediaDownloadJobPhase phaseFor(MangaDownloadState state) {
    return switch (state) {
      MangaDownloadState.queued => MediaDownloadJobPhase.queued,
      MangaDownloadState.resolving => MediaDownloadJobPhase.resolving,
      MangaDownloadState.downloading => MediaDownloadJobPhase.transferring,
      MangaDownloadState.paused => MediaDownloadJobPhase.paused,
      MangaDownloadState.verifying => MediaDownloadJobPhase.verifying,
      MangaDownloadState.completed => MediaDownloadJobPhase.completed,
      MangaDownloadState.failed => MediaDownloadJobPhase.failed,
      MangaDownloadState.cancelled => MediaDownloadJobPhase.cancelled,
    };
  }
}
