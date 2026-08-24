import 'package:goanime_core/goanime_core.dart';
import 'package:test/test.dart';

void main() {
  test('rejects providers from the wrong media kind', () {
    final entry = _Entry(
      providerKey: ProviderKey.manga('source'),
      displayName: 'Source',
    );

    expect(
      () => MediaProviderRegistryValidator.validateAndIndexBy<_Entry>(
        [entry],
        keyOf: (value) => value.providerKey,
        displayNameOf: (value) => value.displayName,
        expectedMedia: MediaKind.anime,
      ),
      throwsStateError,
    );
  });

  test(
    'rejects empty operation declarations when capabilities are required',
    () {
      final entry = _Entry(
        providerKey: ProviderKey.anime('source'),
        displayName: 'Source',
      );

      expect(
        () => MediaProviderRegistryValidator.validateAndIndexBy<_Entry>(
          [entry],
          keyOf: (value) => value.providerKey,
          displayNameOf: (value) => value.displayName,
          expectedMedia: MediaKind.anime,
          operationsOf: (_) => const <ProviderOperation>{},
        ),
        throwsStateError,
      );
    },
  );

  test('rejects operations that belong to another media kind', () {
    final entry = _Entry(
      providerKey: ProviderKey.manga('source'),
      displayName: 'Source',
    );

    expect(
      () => MediaProviderRegistryValidator.validateAndIndexBy<_Entry>(
        [entry],
        keyOf: (value) => value.providerKey,
        displayNameOf: (value) => value.displayName,
        expectedMedia: MediaKind.manga,
        operationsOf: (_) => const {ProviderOperation.playback},
      ),
      throwsStateError,
    );
  });

  test('requires policy when the domain declares it mandatory', () {
    final entry = _Entry(
      providerKey: ProviderKey.manga('source'),
      displayName: 'Source',
    );

    expect(
      () => MediaProviderRegistryValidator.validateAndIndexBy<_Entry>(
        [entry],
        keyOf: (value) => value.providerKey,
        displayNameOf: (value) => value.displayName,
        expectedMedia: MediaKind.manga,
        operationsOf: (_) => const {ProviderOperation.search},
        requiresPolicy: (_) => true,
        policyKeyOf: (_) => null,
      ),
      throwsStateError,
    );
  });

  test('rejects policy mapped to a different provider key', () {
    final entry = _Entry(
      providerKey: ProviderKey.manga('source'),
      displayName: 'Source',
    );

    expect(
      () => MediaProviderRegistryValidator.validateAndIndexBy<_Entry>(
        [entry],
        keyOf: (value) => value.providerKey,
        displayNameOf: (value) => value.displayName,
        expectedMedia: MediaKind.manga,
        operationsOf: (_) => const {ProviderOperation.search},
        requiresPolicy: (_) => true,
        policyKeyOf: (_) => ProviderKey.manga('other-source'),
      ),
      throwsStateError,
    );
  });
}

final class _Entry implements MediaProviderRegistryEntry {
  const _Entry({required this.providerKey, required this.displayName});

  @override
  final ProviderKey providerKey;

  @override
  final String displayName;
}
