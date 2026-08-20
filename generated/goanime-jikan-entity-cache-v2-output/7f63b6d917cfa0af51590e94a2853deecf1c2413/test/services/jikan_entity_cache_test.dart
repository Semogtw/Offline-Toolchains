import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/jikan_models.dart';
import 'package:goanime/services/jikan_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    JikanService.httpClient = null;
    JikanService.debugResetCache();
  });

  test('deduplicates concurrent anime-by-id requests', () async {
    JikanService.debugResetCache();
    final release = Completer<void>();
    var requests = 0;
    JikanService.httpClient = MockClient((request) async {
      requests += 1;
      await release.future;
      return http.Response(
        jsonEncode({
          'data': {
            'mal_id': 123,
            'title': 'Fixture Anime',
            'images': {
              'jpg': {'image_url': 'https://example.test/123.jpg'},
            },
          },
        }),
        200,
      );
    });
    final service = JikanService(propagateErrors: true);

    final first = service.getAnimeById(123);
    final second = service.getAnimeById(123);
    await Future<void>.delayed(Duration.zero);
    release.complete();

    final results = await Future.wait([first, second]);
    expect(requests, 1);
    expect(results[0]?.malId, 123);
    expect(results[1]?.malId, 123);
  });

  test('deduplicates concurrent anime-relations requests', () async {
    JikanService.debugResetCache();
    final release = Completer<void>();
    var requests = 0;
    JikanService.httpClient = MockClient((request) async {
      requests += 1;
      await release.future;
      return http.Response(jsonEncode({'data': <Object>[]}), 200);
    });
    final service = JikanService(propagateErrors: true);

    final first = service.getAnimeRelations(321);
    final second = service.getAnimeRelations(321);
    await Future<void>.delayed(Duration.zero);
    release.complete();

    final results = await Future.wait([first, second]);
    expect(requests, 1);
    expect(results[0], isEmpty);
    expect(results[1], isEmpty);
  });

  test('entity caches remain bounded during long sessions', () {
    JikanService.debugResetCache();
    final maxSize = JikanService.debugEntityCacheMaxSize;
    JikanService.debugPrimeEntityCachesForTesting([
      for (var id = 1; id <= maxSize + 50; id++)
        JikanAnime(malId: id, title: 'Anime $id', imageUrl: ''),
    ]);

    expect(JikanService.debugAnimeByIdCacheSize, maxSize);
    expect(JikanService.debugAnimeRelationsCacheSize, maxSize);
  });
}
