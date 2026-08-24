import 'package:goanime_core/goanime_core.dart';

import '../../models/history_anime.dart';
import '../watch_history_service.dart';

final class AnimePlaybackProgressPayload {
  const AnimePlaybackProgressPayload({
    required this.episodeNumber,
    required this.progress,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.isDubMode,
  });

  final int episodeNumber;
  final double? progress;
  final int? positionSeconds;
  final int? durationSeconds;
  final bool? isDubMode;
}

final class AnimeProgressEventAdapter {
  const AnimeProgressEventAdapter();

  MediaProgressEvent<AnimePlaybackProgressPayload>? fromHistory(
    HistoryAnime history,
  ) {
    final episodeNumber = history.episodeNumber;
    if (history.animeId.isEmpty ||
        episodeNumber == null ||
        episodeNumber <= 0) {
      return null;
    }

    final updatedAt = DateTime.tryParse(history.updatedAt ?? history.watchedAt);
    if (updatedAt == null) return null;

    final progress = history.progress;
    return MediaProgressEvent<AnimePlaybackProgressPayload>(
      mediaKind: MediaKind.anime,
      entityId: history.animeId,
      unitId: 'episode:$episodeNumber',
      updatedAt: updatedAt,
      completed:
          progress != null &&
          progress >= WatchHistoryService.watchedProgressThreshold,
      payload: AnimePlaybackProgressPayload(
        episodeNumber: episodeNumber,
        progress: progress,
        positionSeconds: history.positionSeconds,
        durationSeconds: history.durationSeconds,
        isDubMode: history.isDubMode,
      ),
    );
  }
}
