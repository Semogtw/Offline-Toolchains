import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../tools/super_animes_anilist_mal_resolver.dart';

void main() {
  test('rejects HTTP 200 AniList payload missing data.Page.media', () async {
    final resolver = SuperAnimesAniListMalResolver(
      MockClient(
        (request) async =>
            http.Response(jsonEncode({'data': <String, Object?>{}}), 200),
      ),
      minimumDelayBetweenRequests: Duration.zero,
    );

    await expectLater(resolver.resolveBatch([1535]), throwsFormatException);
  });

  test('accepts a structurally valid empty AniList media list', () async {
    final resolver = SuperAnimesAniListMalResolver(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': {
              'Page': {'media': <Object>[]},
            },
          }),
          200,
        ),
      ),
      minimumDelayBetweenRequests: Duration.zero,
    );

    expect(await resolver.resolveBatch([1535]), isEmpty);
  });
}
