import 'media_kind.dart';

final class MediaProgressEvent<TPayload> {
  MediaProgressEvent({
    required this.mediaKind,
    required this.entityId,
    required this.unitId,
    required DateTime updatedAt,
    required this.completed,
    required this.payload,
  }) : updatedAt = updatedAt.toUtc() {
    if (entityId.isEmpty) {
      throw ArgumentError.value(entityId, 'entityId', 'Must not be empty.');
    }
    if (unitId.isEmpty) {
      throw ArgumentError.value(unitId, 'unitId', 'Must not be empty.');
    }
  }

  final MediaKind mediaKind;
  final String entityId;
  final String unitId;
  final DateTime updatedAt;
  final bool completed;
  final TPayload payload;
}

List<MediaProgressEvent<TPayload>> latestMediaProgressEvents<TPayload>(
  Iterable<MediaProgressEvent<TPayload>> events,
) {
  final latest = <(MediaKind, String, String), MediaProgressEvent<TPayload>>{};
  for (final event in events) {
    final key = (event.mediaKind, event.entityId, event.unitId);
    final current = latest[key];
    if (current == null || !event.updatedAt.isBefore(current.updatedAt)) {
      latest[key] = event;
    }
  }

  final ordered = latest.values.toList()
    ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
  return List<MediaProgressEvent<TPayload>>.unmodifiable(ordered);
}
