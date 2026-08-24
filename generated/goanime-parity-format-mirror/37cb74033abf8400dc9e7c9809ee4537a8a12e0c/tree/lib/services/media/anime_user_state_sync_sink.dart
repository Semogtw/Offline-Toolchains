import 'package:goanime_core/goanime_core.dart';

import '../../models/user_anime_state.dart';
import '../user_sync_service.dart';
import 'user_media_state_sync_dispatcher.dart';

typedef AnimeUserStateRecorder = Future<void> Function(UserAnimeState state);

final class AnimeUserStateSyncSink implements UserMediaStateSyncSink {
  AnimeUserStateSyncSink({AnimeUserStateRecorder? recordState})
    : _recordState = recordState ?? UserSyncService.instance.recordAnimeState;

  final AnimeUserStateRecorder _recordState;

  @override
  MediaKind get mediaKind => MediaKind.anime;

  @override
  Future<void> sync(List<UserMediaStateEvent<dynamic>> events) async {
    final states = <UserAnimeState>{};
    for (final event in events) {
      if (event.mediaKind != MediaKind.anime) {
        throw ArgumentError.value(
          event.mediaKind,
          'events',
          'AnimeUserStateSyncSink only accepts Anime events.',
        );
      }
      final payload = event.payload;
      if (payload is! UserAnimeState) {
        throw StateError(
          'Anime user-state event is missing a UserAnimeState payload.',
        );
      }
      states.add(payload);
    }

    for (final state in states) {
      await _recordState(state);
    }
  }
}
