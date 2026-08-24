import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/manga/manga_http_client.dart';
import 'package:goanime/services/manga/manga_provider_definitions.dart';
import 'package:goanime/services/manga/manga_provider_policy.dart';
import 'package:goanime/services/manga/providers/mangalivre_org_manga_provider.dart';
import 'package:goanime_core/goanime_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../../helpers/manga_provider_contract_harness.dart';

void main() {
  late String searchFixture;
  late String detailsFixture;
  late String chapterFixture;
  late String homeFixture;
  late String bundleFixture;

  setUpAll(() {
    const base = 'test/fixtures/manga/providers/mangalivreorg';
    searchFixture = File('$base/search_page_1.json').readAsStringSync();
    detailsFixture = File('$base/details.json').readAsStringSync();
    chapterFixture = File('$base/chapter.json').readAsStringSync();
    homeFixture = File('$base/home.html').readAsStringSync();
    bundleFixture = File('$base/app_bundle.js').readAsStringSync();
  });

  test('keeps MangaLivre.org identity and conservative network policy', () {
    final definition = releaseCandidateMangaProviderDefinition(
      MangaLivreOrgMangaProvider.sourceIdValue,
    );

    expect(definition.sourceId, MangaLivreOrgMangaProvider.sourceIdValue);
    expect(definition.name, 'MangaLivre.org');
    expect(definition.policy.minimumRequestSpacing, const Duration(seconds: 1));
    expect(definition.policy.timeout, const Duration(seconds: 20));
    expect(definition.policy.maxConcurrent, 1);
    expect(
      definition.policy.allowedContentHosts,
      containsAll(<String>{
        'mangalivre.org',
        'www.mangalivre.org',
        'api.mangalivre.org',
        'picture.mangalivre.org',
      }),
    );
  });

  test(
    'search uses the dedicated API host and no same-origin fetch header',
    () async {
      http.Request? searchRequest;
      final provider = _provider((request) async {
        if (request.url.host == 'api.mangalivre.org' &&
            request.url.path == '/api/v1/mangas/list') {
          searchRequest = request;
          return _json(searchFixture);
        }
        return http.Response('not found', 404);
      });

      final page = await provider.search(
        const MangaSearchRequest(query: 'Org Example'),
      );

      expect(provider.sourceId, MangaLivreOrgMangaProvider.sourceIdValue);
      expect(provider.name, 'MangaLivre.org');
      expect(page.items.single.mangaId, 'org-example');
      expect(page.items.single.title, 'Org Example');
      expect(page.nextPageToken, isNull);
      expect(searchRequest, isNotNull);
      expect(searchRequest!.method, 'GET');
      expect(searchRequest!.url.queryParameters['filter'], 'Org Example');
      expect(searchRequest!.url.queryParameters['page'], '1');
      expect(searchRequest!.headers['user-agent'], contains('Chrome'));
      expect(searchRequest!.headers['accept-language'], contains('pt-BR'));
      expect(
        searchRequest!.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('sec-fetch-site')),
      );
    },
  );

  test('maps current API chapter ids and sorted chapter image pages', () async {
    final provider = _provider((request) async {
      if (request.url.path == '/api/v1/mangas/org-example') {
        return _json(detailsFixture);
      }
      if (request.url.path == '/') {
        return _text(homeFixture, contentType: 'text/html; charset=utf-8');
      }
      if (request.url.path == '/assets/app-abc.js') {
        return _text(bundleFixture, contentType: 'application/javascript');
      }
      if (request.url.path == '/api/v1/chapters/chapter-20') {
        return _json(chapterFixture);
      }
      return http.Response('not found', 404);
    });
    const occurrence = MangaSourceOccurrence(
      sourceId: MangaLivreOrgMangaProvider.sourceIdValue,
      mangaId: 'org-example',
      title: 'Org Example',
    );

    final details = await provider.details(occurrence);
    final chapters = await provider.chapters(occurrence);
    final manifest = await provider.resolveContent(chapters.first);

    expect(details.alternativeTitles, <String>['Org Alt', 'Org Alternative']);
    expect(details.description, contains('Sinopse sanitizada'));
    expect(details.authors, <String>['Autor Org']);
    expect(details.artists, <String>['Artista Org']);
    expect(details.genres, containsAll(<String>['Ação', 'Fantasia']));
    expect(details.status, MangaPublicationStatus.ongoing);
    expect(chapters.map((chapter) => chapter.number).toList(), <double?>[
      20,
      19.5,
    ]);
    expect(chapters.map((chapter) => chapter.chapterId).toList(), <String>[
      'chapter-20',
      'chapter-195',
    ]);
    expect(manifest, isA<ImageSequenceContentManifest>());
    final images = manifest as ImageSequenceContentManifest;
    expect(images.pages, hasLength(2));
    expect(images.pages.first.uri.path, '/org-example/001.webp');
    expect(images.pages.last.uri.path, '/org-example/002.webp');
  });

  test(
    'refreshes a rotated runtime nonce and retries the chapter once',
    () async {
      final nonces = <String?>[];
      var bundleRequests = 0;
      final provider = _provider((request) async {
        if (request.url.path == '/') {
          return _text(homeFixture, contentType: 'text/html; charset=utf-8');
        }
        if (request.url.path == '/assets/app-abc.js') {
          bundleRequests += 1;
          return _text(
            bundleRequests == 1
                ? bundleFixture
                : bundleFixture.replaceAll('97', '98'),
            contentType: 'application/javascript',
          );
        }
        if (request.url.path == '/api/v1/chapters/chapter-20') {
          nonces.add(_header(request, 'x-ml-nonce'));
          if (nonces.length == 1) return http.Response('stale nonce', 404);
          return _json(chapterFixture);
        }
        return http.Response('not found', 404);
      });

      const chapter = MangaSourceChapter(
        sourceId: MangaLivreOrgMangaProvider.sourceIdValue,
        mangaId: 'org-example',
        chapterId: 'chapter-20',
        title: 'Capítulo 20',
        number: 20,
        language: 'pt-BR',
      );

      final manifest = await provider.resolveContent(chapter);

      expect(manifest, isA<ImageSequenceContentManifest>());
      expect(bundleRequests, 2);
      expect(nonces, <String>[
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ]);
    },
  );

  test(
    'passes generic provider contract with independent current API fixtures',
    () async {
      final provider = _provider((request) async {
        if (request.url.path == '/api/v1/mangas/list') {
          return _json(searchFixture);
        }
        if (request.url.path == '/api/v1/mangas/org-example') {
          return _json(detailsFixture);
        }
        if (request.url.path == '/') {
          return _text(homeFixture, contentType: 'text/html; charset=utf-8');
        }
        if (request.url.path == '/assets/app-abc.js') {
          return _text(bundleFixture, contentType: 'application/javascript');
        }
        if (request.url.path == '/api/v1/chapters/chapter-20') {
          return _json(chapterFixture);
        }
        return http.Response('not found', 404);
      });

      final result = await const MangaProviderContractHarness().probe(provider);
      expect(result.outcome, MangaProviderProbeOutcome.readable);
      expect(result.violations, isEmpty);
    },
  );
}

MangaLivreOrgMangaProvider _provider(
  Future<http.Response> Function(http.Request request) handler,
) {
  const policy = MangaProviderPolicy(
    sourceId: MangaLivreOrgMangaProvider.sourceIdValue,
    minimumRequestSpacing: Duration.zero,
    allowedContentHosts: <String>{
      'mangalivre.org',
      'www.mangalivre.org',
      'api.mangalivre.org',
      'picture.mangalivre.org',
    },
  );
  return MangaLivreOrgMangaProvider(
    httpClient: MangaHttpClient(policy: policy, client: MockClient(handler)),
  );
}

String? _header(http.Request request, String name) {
  final wanted = name.toLowerCase();
  for (final entry in request.headers.entries) {
    if (entry.key.toLowerCase() == wanted) return entry.value;
  }
  return null;
}

http.Response _json(String body, [int statusCode = 200]) => http.Response.bytes(
  utf8.encode(body),
  statusCode,
  headers: const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
);

http.Response _text(
  String body, {
  required String contentType,
  int statusCode = 200,
}) => http.Response.bytes(
  utf8.encode(body),
  statusCode,
  headers: <String, String>{'content-type': contentType},
);
