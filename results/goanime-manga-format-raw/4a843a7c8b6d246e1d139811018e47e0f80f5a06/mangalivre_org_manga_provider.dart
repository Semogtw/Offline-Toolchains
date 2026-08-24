import 'dart:convert';

import 'package:goanime_core/goanime_core.dart';
import 'package:html/parser.dart' as html_parser;

import '../../../utils/network_headers.dart';
import '../manga_http_client.dart';
import '../manga_provider_failures.dart';

final class MangaLivreOrgMangaProvider implements MangaSourceProvider {
  MangaLivreOrgMangaProvider({
    required MangaHttpClient httpClient,
    Uri? baseUri,
    Uri? apiUri,
  }) : _httpClient = httpClient,
       baseUri = baseUri ?? Uri.parse('https://mangalivre.org/'),
       apiUri = apiUri ?? Uri.parse('https://api.mangalivre.org/api/v1/');

  static const String sourceIdValue = 'ptbr.mangalivreorg';
  static const String _fallbackReaderNonce = '3dce95d4540e54086a970da4ea44cf46';
  static const int _nonceAssignmentLength = 300;
  static final RegExp _nonceVariableRegex = RegExp(
    r'''(?:X-ML-Nonce|Nonce"]\.join\("-"\))"?\]\s*=\s*(\w+)''',
  );
  static final RegExp _nonceLiteralRegex = RegExp(
    r'''["'`]([0-9a-fA-F]{32})["'`]''',
  );
  static final RegExp _nonceBase64Regex = RegExp(
    r'''atob\(\s*["']([A-Za-z0-9+/=]+)["']''',
  );
  static final RegExp _nonceCharCodeRegex = RegExp(
    r'''(?:String\.)?fromCharCode\(([\d,\s]+)\)''',
  );
  static final RegExp _nonceShapeRegex = RegExp(r'^[0-9a-fA-F]{32}$');

  final MangaHttpClient _httpClient;
  final Uri baseUri;
  final Uri apiUri;

  String? _cachedNonce;

  @override
  String get sourceId => sourceIdValue;

  @override
  String get name => 'MangaLivre.org';

  @override
  String get language => 'pt-BR';

  @override
  MangaProviderCapabilities get capabilities => const MangaProviderCapabilities(
    search: true,
    latest: true,
    details: true,
    chapterList: true,
    imagePages: true,
  );

  Map<String, String> get _apiHeaders => <String, String>{
    'User-Agent': NetworkHeaders.desktopChromeUserAgent,
    'Accept': 'application/json',
    'Accept-Language': NetworkHeaders.acceptLanguagePtBr,
  };

  Map<String, String> get _webHeaders => <String, String>{
    'User-Agent': NetworkHeaders.desktopChromeUserAgent,
    'Accept': NetworkHeaders.htmlAccept,
    'Accept-Language': NetworkHeaders.acceptLanguagePtBr,
    'Referer': baseUri.toString(),
  };

  @override
  Future<MangaSearchPage> search(MangaSearchRequest request) async {
    final page = _pageNumber(request.pageToken);
    final query = request.query.trim();
    final response = await _httpClient.get(
      apiUri
          .resolve('mangas/list')
          .replace(
            queryParameters: <String, String>{
              'page': '$page',
              if (query.isNotEmpty) 'filter': query,
              if (query.isEmpty) 'order': 'updates',
            },
          ),
      headers: _apiHeaders,
    );
    final root = _jsonObject(response.body, 'MangaLivre.org search');
    final rawItems = _searchItems(root);
    if (rawItems.isEmpty && root['series'] is! List) {
      throw const FormatException(
        'MangaLivre.org search response is missing series.',
      );
    }

    final items = <MangaSourceOccurrence>[];
    final seen = <String>{};
    for (final raw in rawItems) {
      final manga = _map(raw);
      if (manga == null) continue;
      final slug = _text(manga['slug']) ?? _slugFromLink(_text(manga['link']));
      final title =
          _text(manga['title']) ??
          _text(manga['name']) ??
          _text(manga['label']);
      if (slug == null || title == null || !seen.add(slug)) continue;
      final cover =
          _text(manga['coverUrl']) ??
          _text(manga['cover']) ??
          _text(manga['image']);
      items.add(
        MangaSourceOccurrence(
          sourceId: sourceId,
          mangaId: slug,
          title: title,
          coverUrl: cover == null ? null : _resolveAsset(cover).toString(),
        ),
      );
    }

    final currentPage = _positiveInt(root['page']) ?? page;
    final totalPages =
        _positiveInt(root['total_pages']) ??
        _positiveInt(root['nPages']) ??
        currentPage;
    return MangaSearchPage(
      items: List<MangaSourceOccurrence>.unmodifiable(items),
      nextPageToken: currentPage < totalPages ? '${currentPage + 1}' : null,
    );
  }

  @override
  Future<MangaSourceDetails> details(MangaSourceOccurrence occurrence) async {
    _requireOccurrence(occurrence);
    final manga = await _fetchManga(occurrence.mangaId);
    final author = _text(manga['author']);
    final artist = _text(manga['artist']);
    final type = _text(manga['type']);
    final genres = _stringList(manga['genres']);
    final cover = _text(manga['coverUrl']) ?? _text(manga['cover']);

    return MangaSourceDetails(
      occurrence: MangaSourceOccurrence(
        sourceId: sourceId,
        mangaId: occurrence.mangaId,
        title: _text(manga['title']) ?? occurrence.title,
        coverUrl: cover == null
            ? occurrence.coverUrl
            : _resolveAsset(cover).toString(),
      ),
      alternativeTitles: _alternativeTitles(
        manga['alternative'] ?? manga['altTitles'],
      ),
      description: _text(manga['description']),
      authors: author == null ? const <String>[] : <String>[author],
      artists: artist == null ? const <String>[] : <String>[artist],
      genres: genres,
      status: _status(_text(manga['status'])),
      format: _format(type),
    );
  }

  @override
  Future<List<MangaSourceChapter>> chapters(
    MangaSourceOccurrence occurrence,
  ) async {
    _requireOccurrence(occurrence);
    final manga = await _fetchManga(occurrence.mangaId);
    final chapters = <MangaSourceChapter>[];
    final seen = <String>{};
    for (final raw in _listOfMaps(manga['chapters'])) {
      final numberText = _text(raw['number']);
      if (numberText == null) continue;
      final number = double.tryParse(numberText.replaceAll(',', '.'));
      final chapterId =
          _text(raw['id']) ??
          _positiveIdentifier(raw['legacyId']) ??
          numberText;
      if (!seen.add(chapterId)) continue;
      chapters.add(
        MangaSourceChapter(
          sourceId: sourceId,
          mangaId: occurrence.mangaId,
          chapterId: chapterId,
          title: _text(raw['title']) ?? 'Capítulo $numberText',
          number: number,
          language: language,
          publishedAt: _date(raw['publishedAt'] ?? raw['date']),
        ),
      );
    }
    chapters.sort((left, right) {
      final leftNumber = left.number ?? double.negativeInfinity;
      final rightNumber = right.number ?? double.negativeInfinity;
      return rightNumber.compareTo(leftNumber);
    });
    return List<MangaSourceChapter>.unmodifiable(chapters);
  }

  @override
  Future<ChapterContentManifest> resolveContent(
    MangaSourceChapter chapter,
  ) async {
    if (chapter.sourceId != sourceId) {
      throw ArgumentError.value(chapter.sourceId, 'chapter.sourceId');
    }
    final response = await _fetchChapterWithNonceRetry(chapter.chapterId);
    final root = _jsonObject(response.body, 'MangaLivre.org chapter');
    final rawPages = root['pages'] ?? root['images'];
    if (rawPages is! List) {
      throw const FormatException(
        'MangaLivre.org chapter response is missing pages.',
      );
    }

    final ordered = <MapEntry<int, String>>[];
    for (var index = 0; index < rawPages.length; index++) {
      final raw = rawPages[index];
      final map = _map(raw);
      final value = map == null
          ? _text(raw)
          : _text(map['imageUrl']) ?? _text(map['url']);
      if (value == null) continue;
      final order = map == null
          ? index + 1
          : _positiveInt(map['number']) ??
                _positiveInt(map['order']) ??
                index + 1;
      ordered.add(MapEntry<int, String>(order, value));
    }
    ordered.sort((left, right) => left.key.compareTo(right.key));

    final pages = <MangaPageRequest>[];
    final seen = <String>{};
    for (final entry in ordered) {
      final uri = _resolveAsset(entry.value);
      if (!seen.add(uri.toString())) continue;
      pages.add(
        MangaPageRequest(
          index: pages.length,
          uri: uri,
          headers: <String, String>{'Referer': baseUri.toString()},
        ),
      );
    }
    if (pages.isEmpty) {
      throw const FormatException(
        'MangaLivre.org chapter has no readable image pages.',
      );
    }
    return ImageSequenceContentManifest(
      sourceId: sourceId,
      mangaId: chapter.mangaId,
      chapterId: chapter.chapterId,
      pages: List<MangaPageRequest>.unmodifiable(pages),
    );
  }

  Future<MangaHttpResponse> _fetchChapterWithNonceRetry(
    String chapterId,
  ) async {
    final uri = apiUri.resolve('chapters/${Uri.encodeComponent(chapterId)}');
    try {
      return await _httpClient.get(uri, headers: await _chapterHeaders());
    } on MangaProviderFailure catch (failure) {
      final statusCode = failure.statusCode;
      final canRefreshNonce =
          failure.kind == MangaProviderFailureKind.httpStatus &&
          (statusCode == 401 || statusCode == 403 || statusCode == 404);
      if (!canRefreshNonce) rethrow;
      _cachedNonce = null;
      return _httpClient.get(uri, headers: await _chapterHeaders());
    }
  }

  Future<Map<String, String>> _chapterHeaders() async => <String, String>{
    ..._apiHeaders,
    'X-ML-Nonce': await _nonce(),
  };

  Future<String> _nonce() async {
    final cached = _cachedNonce;
    if (cached != null) return cached;
    final resolved = await _fetchNonce();
    _cachedNonce = resolved;
    return resolved;
  }

  Future<String> _fetchNonce() async {
    final home = await _httpClient.get(baseUri, headers: _webHeaders);
    final document = html_parser.parse(home.body);
    final scriptElement =
        document.querySelector('script[type="module"][src*="/assets/"]') ??
        document.querySelector('script[src*="/assets/"]');
    final scriptSource = scriptElement?.attributes['src']?.trim();
    if (scriptSource == null || scriptSource.isEmpty) {
      return _fallbackReaderNonce;
    }

    final script = await _httpClient.get(
      baseUri.resolve(scriptSource),
      headers: <String, String>{..._webHeaders, 'Accept': '*/*'},
    );
    final variable = _nonceVariableRegex.firstMatch(script.body)?.group(1);
    if (variable == null || variable.isEmpty) {
      return _fallbackReaderNonce;
    }

    final assignmentRegex = RegExp('\\b${RegExp.escape(variable)}\\s*=\\s*');
    for (final match in assignmentRegex.allMatches(script.body)) {
      final start = match.end;
      final requestedEnd = start + _nonceAssignmentLength;
      final end = requestedEnd < script.body.length
          ? requestedEnd
          : script.body.length;
      final assignment = script.body.substring(start, end).split(';').first;
      final decoded = _decodeNonceAssignment(assignment);
      if (decoded != null) return decoded;
    }
    return _fallbackReaderNonce;
  }

  String? _decodeNonceAssignment(String assignment) {
    String? decoded = _nonceLiteralRegex.firstMatch(assignment)?.group(1);

    if (decoded == null) {
      final encoded = _nonceBase64Regex.firstMatch(assignment)?.group(1);
      if (encoded != null) {
        try {
          decoded = utf8.decode(base64Decode(encoded));
        } on FormatException {
          decoded = null;
        }
      }
    }

    if (decoded == null) {
      final values = _nonceCharCodeRegex.firstMatch(assignment)?.group(1);
      if (values != null) {
        final codes = <int>[];
        for (final raw in values.split(',')) {
          final code = int.tryParse(raw.trim());
          if (code == null) return null;
          codes.add(code);
        }
        decoded = String.fromCharCodes(codes);
      }
    }

    if (decoded == null || !_nonceShapeRegex.hasMatch(decoded)) return null;
    return assignment.contains('reverse()')
        ? decoded.split('').reversed.join()
        : decoded;
  }

  Future<Map<String, dynamic>> _fetchManga(String slug) async {
    final response = await _httpClient.get(
      apiUri.resolve('mangas/${Uri.encodeComponent(slug)}'),
      headers: _apiHeaders,
    );
    final root = _jsonObject(response.body, 'MangaLivre.org details');
    final manga = _map(root['manga']);
    if (manga == null) return root;
    return <String, dynamic>{
      ...manga,
      if (root['chapters'] != null) 'chapters': root['chapters'],
    };
  }

  Uri _resolveAsset(String value) =>
      Uri.parse(value).hasScheme ? Uri.parse(value) : baseUri.resolve(value);

  void _requireOccurrence(MangaSourceOccurrence occurrence) {
    if (occurrence.sourceId != sourceId) {
      throw ArgumentError.value(occurrence.sourceId, 'occurrence.sourceId');
    }
  }
}

Map<String, dynamic> _jsonObject(String body, String label) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$label response must be an object.');
  }
  return decoded;
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

List<Map<String, dynamic>> _listOfMaps(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .map(_map)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

List<Map<String, dynamic>> _searchItems(Map<String, dynamic> root) {
  final series = root['series'];
  if (series is List<Object?>) {
    return series.map(_map).whereType<Map<String, dynamic>>().toList();
  }

  return root.values
      .whereType<List<Object?>>()
      .expand((items) => items)
      .map(_map)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

String? _slugFromLink(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.pathSegments.isEmpty) return null;
  final index = uri.pathSegments.indexOf('manga');
  if (index < 0 || index + 1 >= uri.pathSegments.length) return null;
  return _text(uri.pathSegments[index + 1]);
}

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((item) => item is Map ? _text(item['name']) : _text(item))
      .whereType<String>()
      .toSet()
      .toList(growable: false);
}

List<String> _alternativeTitles(Object? value) {
  if (value is String) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }
  return _stringList(value);
}

String? _text(Object? value) {
  if (value is String) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
  if (value is num) return value.toString();
  return null;
}

String? _positiveIdentifier(Object? value) {
  final text = _text(value);
  if (text == null) return null;
  final number = int.tryParse(text);
  return number != null && number > 0 ? text : null;
}

int _pageNumber(String? token) {
  if (token == null || token.trim().isEmpty) return 1;
  final value = int.tryParse(token);
  if (value == null || value <= 0) {
    throw ArgumentError.value(
      token,
      'pageToken',
      'Must be a positive integer.',
    );
  }
  return value;
}

int? _positiveInt(Object? value) {
  if (value is int && value > 0) return value;
  if (value is num && value > 0) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null && parsed > 0) return parsed;
  }
  return null;
}

DateTime? _date(Object? value) {
  final text = _text(value);
  if (text == null) return null;
  return DateTime.tryParse(text)?.toUtc();
}

MangaPublicationStatus _status(String? value) {
  switch (value?.toLowerCase()) {
    case 'em andamento':
    case 'lançando':
    case 'lancando':
    case 'ongoing':
      return MangaPublicationStatus.ongoing;
    case 'completo':
    case 'completed':
      return MangaPublicationStatus.completed;
    case 'hiato':
    case 'pausado':
    case 'paused':
    case 'hiatus':
      return MangaPublicationStatus.hiatus;
    case 'cancelado':
    case 'cancelled':
    case 'canceled':
      return MangaPublicationStatus.cancelled;
    default:
      return MangaPublicationStatus.unknown;
  }
}

MangaFormat _format(String? value) {
  switch (value?.toLowerCase()) {
    case 'mangá':
    case 'manga':
      return MangaFormat.manga;
    case 'manhwa':
      return MangaFormat.manhwa;
    case 'manhua':
      return MangaFormat.manhua;
    case 'novel':
    case 'web novel':
    case 'light novel':
      return MangaFormat.other;
    default:
      return MangaFormat.unknown;
  }
}
