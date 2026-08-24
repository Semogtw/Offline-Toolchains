import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/unified_anime_model.dart';
import 'package:goanime/services/source/episode_cache_repository.dart';
import 'package:goanime_core/goanime_core.dart';

void main() {
  test('EpisodeCacheRepository obeys CachePolicy TTL', () async {
    final cache = EpisodeCacheRepository(
      policy: () =>
          const CachePolicy(ttl: Duration(milliseconds: 20), maxEntries: 4),
    );

    cache.saveMemory('one', const <UnifiedEpisode>[]);
    expect(cache.getFreshMemory('one'), isNotNull);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(cache.getFreshMemory('one'), isNull);
  });

  test('EpisodeCacheRepository obeys CachePolicy LRU capacity', () {
    final cache = EpisodeCacheRepository(
      policy: () => const CachePolicy(ttl: Duration(minutes: 5), maxEntries: 2),
    );

    cache.saveMemory('one', const <UnifiedEpisode>[]);
    cache.saveMemory('two', const <UnifiedEpisode>[]);
    expect(cache.getFreshMemory('one'), isNotNull);

    cache.saveMemory('three', const <UnifiedEpisode>[]);

    expect(cache.getFreshMemory('one'), isNotNull);
    expect(cache.getFreshMemory('two'), isNull);
    expect(cache.getFreshMemory('three'), isNotNull);
  });
}
