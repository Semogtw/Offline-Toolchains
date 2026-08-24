import 'package:goanime_core/goanime_core.dart';

abstract interface class UserMediaStateSyncSink {
  MediaKind get mediaKind;

  Future<void> sync(List<UserMediaStateEvent<dynamic>> events);
}

final class UserMediaStateSyncDispatcher {
  UserMediaStateSyncDispatcher({required List<UserMediaStateSyncSink> sinks}) {
    for (final sink in sinks) {
      if (_sinks.containsKey(sink.mediaKind)) {
        throw ArgumentError.value(
          sink.mediaKind,
          'sinks',
          'Duplicate user-state sync sink.',
        );
      }
      _sinks[sink.mediaKind] = sink;
    }
  }

  final Map<MediaKind, UserMediaStateSyncSink> _sinks =
      <MediaKind, UserMediaStateSyncSink>{};

  Future<void> dispatch(Iterable<UserMediaStateEvent<dynamic>> events) async {
    final grouped = <MediaKind, List<UserMediaStateEvent<dynamic>>>{};
    for (final event in events) {
      grouped
          .putIfAbsent(event.mediaKind, () => <UserMediaStateEvent<dynamic>>[])
          .add(event);
    }

    for (final entry in grouped.entries) {
      final sink = _sinks[entry.key];
      if (sink == null) {
        throw StateError(
          'No user-state sync sink registered for ${entry.key.name}.',
        );
      }
      await sink.sync(
        List<UserMediaStateEvent<dynamic>>.unmodifiable(entry.value),
      );
    }
  }
}
