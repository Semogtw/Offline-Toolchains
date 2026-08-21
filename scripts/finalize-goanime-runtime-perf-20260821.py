#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')


def replace_once(relative: str, old: str, new: str) -> None:
    path = root / relative
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{relative}: expected exactly one replacement, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


replace_once(
    'lib/platform/desktop/screens/desktop_unified_episode_view.dart',
    'onPressed: () => onOpenEpisode(firstPlayable),',
    'onPressed: () => onOpenEpisode(firstPlayable!),',
)

replace_once(
    'test/services/download_service_test.dart',
    "import 'package:goanime/services/download_service.dart';",
    "import 'package:goanime/services/download/download_queue_manager.dart';\n"
    "import 'package:goanime/services/download_service.dart';",
)

replace_once(
    'lib/platform/desktop/screens/desktop_video_player_screen_methods_3.dart',
    '''  UnifiedEpisode? get _nextEpisode {
    final playable =
        widget.allEpisodes
            .where(
              (episode) =>
                  episode.episodeNumber > _currentEpisode.episodeNumber &&
                  episode.hasProvider(isSub: !widget.isDubMode),
            )
            .toList()
          ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return playable.isEmpty ? null : playable.first;
  }
''',
    '''  UnifiedEpisode? get _nextEpisode {
    UnifiedEpisode? next;
    for (final episode in widget.allEpisodes) {
      if (episode.episodeNumber <= _currentEpisode.episodeNumber ||
          !episode.hasProvider(isSub: !widget.isDubMode)) {
        continue;
      }
      if (next == null || episode.episodeNumber < next.episodeNumber) {
        next = episode;
      }
    }
    return next;
  }
''',
)

replace_once(
    'lib/platform/mobile/screens/mobile_media_kit_video_player_screen_methods_1.dart',
    '''  UnifiedEpisode? get _nextEpisode {
    final playable =
        widget.allEpisodes
            .where(
              (episode) =>
                  episode.episodeNumber > _currentEpisode.episodeNumber &&
                  episode.hasProvider(isSub: !widget.isDubMode),
            )
            .toList()
          ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    return playable.isEmpty ? null : playable.first;
  }

  UnifiedEpisode? get _previousEpisode {
    final playable =
        widget.allEpisodes
            .where(
              (episode) =>
                  episode.episodeNumber < _currentEpisode.episodeNumber &&
                  episode.hasProvider(isSub: !widget.isDubMode),
            )
            .toList()
          ..sort((a, b) => b.episodeNumber.compareTo(a.episodeNumber));
    return playable.isEmpty ? null : playable.first;
  }
''',
    '''  UnifiedEpisode? get _nextEpisode {
    UnifiedEpisode? next;
    for (final episode in widget.allEpisodes) {
      if (episode.episodeNumber <= _currentEpisode.episodeNumber ||
          !episode.hasProvider(isSub: !widget.isDubMode)) {
        continue;
      }
      if (next == null || episode.episodeNumber < next.episodeNumber) {
        next = episode;
      }
    }
    return next;
  }

  UnifiedEpisode? get _previousEpisode {
    UnifiedEpisode? previous;
    for (final episode in widget.allEpisodes) {
      if (episode.episodeNumber >= _currentEpisode.episodeNumber ||
          !episode.hasProvider(isSub: !widget.isDubMode)) {
        continue;
      }
      if (previous == null ||
          episode.episodeNumber > previous.episodeNumber) {
        previous = episode;
      }
    }
    return previous;
  }
''',
)

replace_once(
    'lib/screens/history_screen.dart',
    '''      final targetEpisode = anime.episodeNumber == null
          ? episodes.first
          : await UnifiedSourceService.findEpisodeByNumber(
              jikanAnime,
              anime.episodeNumber!,
              isDubMode: anime.isDubMode,
            );

      if (!mounted) return;
''',
    '''      UnifiedEpisode? targetEpisode;
      final requestedEpisodeNumber = anime.episodeNumber;
      if (requestedEpisodeNumber == null) {
        targetEpisode = episodes.first;
      } else {
        for (final episode in episodes) {
          if (episode.episodeNumber != requestedEpisodeNumber) continue;
          final requestedMode = anime.isDubMode;
          if (requestedMode == null ||
              episode.hasProvider(isSub: !requestedMode)) {
            targetEpisode = episode;
          }
          break;
        }
      }

      if (!mounted) return;
''',
)

print('Applied GoAnime runtime performance fixups.')
