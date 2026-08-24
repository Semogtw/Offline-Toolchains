import 'package:goanime_core/goanime_core.dart';

import '../../models/user_anime_state.dart';

final class AnimeUserStateEventAdapter {
  const AnimeUserStateEventAdapter();

  List<UserMediaStateEvent<UserAnimeState>> fromState(UserAnimeState state) {
    if (state.animeId.isEmpty)
      return const <UserMediaStateEvent<UserAnimeState>>[];

    if (state.isDeleted) {
      final deletedAt = state.deletedAt ?? state.updatedAt;
      return _sorted(<UserMediaStateEvent<UserAnimeState>>[
        for (final category in UserMediaStateCategory.values)
          UserMediaStateEvent<UserAnimeState>(
            mediaKind: MediaKind.anime,
            entityId: state.animeId,
            category: category,
            updatedAt: deletedAt,
            tombstone: true,
            partial: false,
            payload: state,
          ),
      ]);
    }

    final events = <UserMediaStateEvent<UserAnimeState>>[];
    final isPartial = state.isPartial;

    if (!isPartial || state.playbackOnly) {
      events.add(
        UserMediaStateEvent<UserAnimeState>(
          mediaKind: MediaKind.anime,
          entityId: state.animeId,
          category: UserMediaStateCategory.progress,
          updatedAt: state.playbackUpdatedAt ?? state.updatedAt,
          tombstone: state.playbackDeletedAt != null,
          partial: isPartial,
          payload: state,
        ),
      );
    }

    if (!isPartial || state.watchlistOnly) {
      events.add(
        UserMediaStateEvent<UserAnimeState>(
          mediaKind: MediaKind.anime,
          entityId: state.animeId,
          category: UserMediaStateCategory.library,
          updatedAt: state.watchlistUpdatedAt ?? state.updatedAt,
          tombstone: !state.saved,
          partial: isPartial,
          payload: state,
        ),
      );
    }

    if (!isPartial || state.ratingOnly) {
      events.add(
        UserMediaStateEvent<UserAnimeState>(
          mediaKind: MediaKind.anime,
          entityId: state.animeId,
          category: UserMediaStateCategory.rating,
          updatedAt: state.ratingUpdatedAt ?? state.updatedAt,
          tombstone: false,
          partial: isPartial,
          payload: state,
        ),
      );
    }

    return _sorted(events);
  }

  static List<UserMediaStateEvent<UserAnimeState>> _sorted(
    List<UserMediaStateEvent<UserAnimeState>> events,
  ) {
    events.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List<UserMediaStateEvent<UserAnimeState>>.unmodifiable(events);
  }
}
