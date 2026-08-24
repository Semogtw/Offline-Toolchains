import 'package:goanime_core/goanime_core.dart';
import 'package:test/test.dart';

void main() {
  test('UserMediaStateEvent preserves typed payload and domain metadata', () {
    final event = UserMediaStateEvent<_Payload>(
      mediaKind: MediaKind.anime,
      entityId: 'anime-1',
      category: UserMediaStateCategory.progress,
      updatedAt: DateTime.parse('2026-08-24T08:00:00-03:00'),
      tombstone: false,
      partial: true,
      payload: const _Payload('playback'),
    );

    expect(event.mediaKind, MediaKind.anime);
    expect(event.entityId, 'anime-1');
    expect(event.category, UserMediaStateCategory.progress);
    expect(event.updatedAt, DateTime.utc(2026, 8, 24, 11));
    expect(event.tombstone, isFalse);
    expect(event.partial, isTrue);
    expect(event.payload!.value, 'playback');
  });

  test('tombstone envelopes can omit a domain payload', () {
    final event = UserMediaStateEvent<Object?>(
      mediaKind: MediaKind.manga,
      entityId: 'work-1',
      category: UserMediaStateCategory.library,
      updatedAt: DateTime.utc(2026, 8, 24),
      tombstone: true,
      partial: true,
      payload: null,
    );

    expect(event.tombstone, isTrue);
    expect(event.payload, isNull);
  });

  test(
    'latestUserMediaStateEvents deduplicates each category independently',
    () {
      final library = UserMediaStateEvent<int>(
        mediaKind: MediaKind.anime,
        entityId: 'anime-1',
        category: UserMediaStateCategory.library,
        updatedAt: DateTime.utc(2026, 8, 24, 9),
        tombstone: false,
        partial: true,
        payload: 1,
      );
      final olderProgress = UserMediaStateEvent<int>(
        mediaKind: MediaKind.anime,
        entityId: 'anime-1',
        category: UserMediaStateCategory.progress,
        updatedAt: DateTime.utc(2026, 8, 24, 10),
        tombstone: false,
        partial: true,
        payload: 2,
      );
      final newerProgress = UserMediaStateEvent<int>(
        mediaKind: MediaKind.anime,
        entityId: 'anime-1',
        category: UserMediaStateCategory.progress,
        updatedAt: DateTime.utc(2026, 8, 24, 11),
        tombstone: true,
        partial: true,
        payload: 3,
      );

      final result = latestUserMediaStateEvents(<UserMediaStateEvent<int>>[
        olderProgress,
        library,
        newerProgress,
      ]);

      expect(result, hasLength(2));
      expect(result.first.category, UserMediaStateCategory.progress);
      expect(result.first.payload, 3);
      expect(result.first.tombstone, isTrue);
      expect(result.last.category, UserMediaStateCategory.library);
    },
  );

  test('empty entity identity is rejected', () {
    expect(
      () => UserMediaStateEvent<int>(
        mediaKind: MediaKind.anime,
        entityId: '',
        category: UserMediaStateCategory.rating,
        updatedAt: DateTime.utc(2026, 8, 24),
        tombstone: false,
        partial: true,
        payload: 5,
      ),
      throwsArgumentError,
    );
  });
}

final class _Payload {
  const _Payload(this.value);

  final String value;
}
