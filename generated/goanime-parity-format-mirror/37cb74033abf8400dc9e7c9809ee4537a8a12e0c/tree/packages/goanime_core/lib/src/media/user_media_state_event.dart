import 'media_kind.dart';

enum UserMediaStateCategory { library, progress, rating }

final class UserMediaStateEvent<TPayload> {
  UserMediaStateEvent({
    required this.mediaKind,
    required this.entityId,
    required this.category,
    required DateTime updatedAt,
    required this.tombstone,
    required this.partial,
    required this.payload,
  }) : updatedAt = updatedAt.toUtc() {
    if (entityId.isEmpty) {
      throw ArgumentError.value(entityId, 'entityId', 'Must not be empty.');
    }
  }

  final MediaKind mediaKind;
  final String entityId;
  final UserMediaStateCategory category;
  final DateTime updatedAt;
  final bool tombstone;
  final bool partial;
  final TPayload? payload;
}

List<UserMediaStateEvent<TPayload>> latestUserMediaStateEvents<TPayload>(
  Iterable<UserMediaStateEvent<TPayload>> events,
) {
  final latest =
      <
        (MediaKind, String, UserMediaStateCategory),
        UserMediaStateEvent<TPayload>
      >{};
  for (final event in events) {
    final key = (event.mediaKind, event.entityId, event.category);
    final current = latest[key];
    if (current == null || !event.updatedAt.isBefore(current.updatedAt)) {
      latest[key] = event;
    }
  }

  final ordered = latest.values.toList()
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return List<UserMediaStateEvent<TPayload>>.unmodifiable(ordered);
}
