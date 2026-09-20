// ignore_for_file: inference_failure_on_collection_literal
part of 'jikan_service_search_test.dart';

void registerJikanServiceSearchCases1() {
  test('searchAnimes returns only available titles', () async {
    AvailabilityService.debugSetAvailableTitles(['naruto']);
    JikanService.httpClient = MockClient((request) async {
      expect(request.url.queryParameters['q'], 'naruto');
      return http.Response(
        jsonEncode({
          'data': [
            {
              'mal_id': 20,
              'title': 'Naruto',
              'title_english': 'Naruto',
              'title_japanese': null,
              'title_synonyms': [],
              'images': {
                'jpg': {'image_url': ''},
              },
              'genres': [],
            },
            {
              'mal_id': 999999,
              'title': 'Tian Guan Cifu Er',
              'title_english': null,
              'title_japanese': null,
              'title_synonyms': [],
              'images': {
                'jpg': {'image_url': ''},
              },
              'genres': [],
            },
          ],
        }),
        200,
      );
    });

    final service = JikanService();
    final results = await service.searchAnimes('naruto');

    expect(results.map((anime) => anime.title), ['Naruto']);
  });

  test(
    'searchAnimes can return metadata cache results before online fallback',
    () async {
      AvailabilityService.debugSetAvailableTitles(['cowboy bebop']);
      JikanService.debugSetAnimeMetadataCacheService(
        _FakeAnimeMetadataCacheService(
          searchResults: [
            AnimeMetadataCacheEntry(
              malId: 1,
              title: 'Cowboy Bebop',
              imageUrl: 'https://cdn.example/cowboy.webp',
              updatedAt: DateTime.utc(2026, 5, 15),
            ),
          ],
        ),
      );
      JikanService.httpClient = MockClient((request) async {
        return http.Response(jsonEncode({'data': []}), 200);
      });

      final results = await JikanService().searchAnimes('cowboy');

      expect(results.single.title, 'Cowboy Bebop');
      expect(results.single.imageUrl, 'https://cdn.example/cowboy.webp');
    },
  );

  test('searchCachedAnimes merges local titles with cached images', () async {
    AvailabilityService.debugSetAvailableTitles(['cowboy bebop', 'naruto']);
    JikanService.debugSetAnimeMetadataCacheService(
      _FakeAnimeMetadataCacheService(
        searchResults: [
          AnimeMetadataCacheEntry(
            malId: 1,
            title: 'Cowboy Bebop',
            imageUrl: 'https://cdn.example/cowboy.webp',
            updatedAt: DateTime.utc(2026, 5, 15),
          ),
        ],
      ),
    );

    final results = await JikanService().searchCachedAnimes('cowboy', limit: 3);

    expect(results.first.title, 'Cowboy Bebop');
    expect(results.first.imageUrl, 'https://cdn.example/cowboy.webp');
  });

  test('local search reuses metadata cache for immediate enrichment', () async {
    AvailabilityService.debugSetAvailableTitles(['cowboy bebop']);
    final metadataCache = _FakeAnimeMetadataCacheService(
      searchResults: [
        AnimeMetadataCacheEntry(
          malId: 1,
          title: 'Cowboy Bebop',
          imageUrl: 'https://cdn.example/cowboy.webp',
          updatedAt: DateTime.utc(2026, 5, 15),
        ),
      ],
    );
    JikanService.debugSetAnimeMetadataCacheService(metadataCache);
    JikanService.httpClient = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'pagination': {'has_next_page': false},
          'data': <Object>[],
        }),
        200,
      ),
    );

    final service = JikanService();
    final local = await service.searchCachedAnimes('cowboy', limit: 20);
    final enriched = await service.searchAnimeMetadata('cowboy', limit: 20);

    expect(local.single.title, 'Cowboy Bebop');
    expect(enriched.single.title, 'Cowboy Bebop');
    expect(metadataCache.searchCalls, 1);
  });

  test('getAnimeExtrasById parses studios and themes', () async {
    JikanService.httpClient = MockClient((request) async {
      expect(request.url.path, '/v4/anime/1/full');
      return http.Response(
        jsonEncode({
          'data': {
            'studios': [
              {'mal_id': 21, 'name': 'Studio A'},
            ],
            'theme': {
              'openings': ['"OP 1" by Artist', '"OP 2" by Artist'],
              'endings': ['"ED 1" by Artist'],
            },
          },
        }),
        200,
      );
    });

    final extras = await JikanService().getAnimeExtrasById(1);

    expect(extras?.studios.single.malId, 21);
    expect(extras?.openings, hasLength(2));
    expect(extras?.endings.single.title, '"ED 1" by Artist');
  });

  test('getAnimesByProducer uses Jikan producers filter', () async {
    AvailabilityService.debugSetAvailableTitles(['cowboy bebop']);
    JikanService.httpClient = MockClient((request) async {
      expect(request.url.queryParameters['producers'], '21');
      expect(request.url.queryParameters['order_by'], 'score');
      return http.Response(
        jsonEncode({
          'pagination': {'has_next_page': false},
          'data': [
            {
              'mal_id': 1,
              'title': 'Cowboy Bebop',
              'title_synonyms': [],
              'images': {
                'jpg': {'image_url': 'https://cdn.example/cowboy.jpg'},
              },
              'genres': [],
            },
          ],
        }),
        200,
      );
    });

    final results = await JikanService().getAnimesByProducer(21, limit: 25);

    expect(results.single.title, 'Cowboy Bebop');
  });

  test('findProducerByName maps studio name to Jikan producer id', () async {
    JikanService.httpClient = MockClient((request) async {
      expect(request.url.path, '/v4/producers');
      expect(request.url.queryParameters['q'], 'BUG FILMS');
      return http.Response(
        jsonEncode({
          'data': [
            {
              'mal_id': 2674,
              'url': 'https://myanimelist.net/anime/producer/2674/BUG_FILMS',
              'titles': [
                {'type': 'Default', 'title': 'BUG FILMS'},
              ],
            },
          ],
        }),
        200,
      );
    });

    final producer = await JikanService().findProducerByName('BUG FILMS');

    expect(producer?.malId, 2674);
    expect(producer?.name, 'BUG FILMS');
  });
}
