import 'package:goanime_core/goanime_core.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// AllAnime API Service - Integração com AllAnime.day
class AllAnimeService {
  static final RegExp _twoCharsRegExp = RegExp(r'..');

  static final RegExp _anyVideoRegExp = RegExp(
    r'(https?://[^\s<>"]+?\.(?:mp4|m3u8))',
  );

  // Optimization: Shared HTTP client for connection keep-alive to reduce TLS handshake overhead
  static http.Client? _clientInstance;
  static http.Client get _client => _clientInstance ??= http.Client();

  @visibleForTesting
  static void resetClient() {
    _clientInstance?.close();
    _clientInstance = null;
  }

  static Map<String, Map<String, dynamic>> _indexEpisodeInfos(
    Iterable<dynamic> episodeInfos,
  ) {
    final index = <String, Map<String, dynamic>>{};
    for (final rawInfo in episodeInfos) {
      final info = jsonMap(rawInfo);
      final episodeNumber = info?['episodeIdNum']?.toString();
      if (info == null || episodeNumber == null || episodeNumber.isEmpty) {
        continue;
      }
      index.putIfAbsent(episodeNumber, () => info);
    }
    return index;
  }

  @visibleForTesting
  static Map<String, Map<String, dynamic>> indexEpisodeInfosForTesting(
    Iterable<dynamic> episodeInfos,
  ) => _indexEpisodeInfos(episodeInfos);

  static const String _allAnimeReferer = 'https://allmanga.to';
  static const String _allAnimeBase = 'allanime.day';
  static const String _allAnimeAPI = 'https://api.allanime.day/api';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0';

  /// Busca animes no AllAnime
  static Future<AllAnimeSearchResponse?> searchAnime(String query) async {
    try {
      debugPrint('[AllAnime] Searching for: $query');

      // GraphQL query com thumbnail
      const searchGql = '''
        query(\$search: SearchInput, \$limit: Int, \$page: Int, \$translationType: VaildTranslationTypeEnumType, \$countryOrigin: VaildCountryOriginEnumType) {
          shows(search: \$search, limit: \$limit, page: \$page, translationType: \$translationType, countryOrigin: \$countryOrigin) {
            edges {
              _id
              name
              englishName
              availableEpisodes
              thumbnail
              __typename
            }
          }
        }
      ''';

      // Variáveis da query
      final variables = {
        'search': {'allowAdult': false, 'allowUnknown': false, 'query': query},
        'limit': 40,
        'page': 1,
        'translationType': 'sub',
        'countryOrigin': 'ALL',
      };

      final body = jsonEncode({'variables': variables, 'query': searchGql});

      final url = Uri.parse(_allAnimeAPI);

      final response = await _client
          .post(
            url,
            headers: {
              'User-Agent': _userAgent,
              'Referer': _allAnimeReferer,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonMap(jsonDecode(response.body)) ?? const {};
        final showEdges = jsonList(
          jsonMap(jsonMap(data['data'])?['shows'])?['edges'],
        );
        debugPrint('[AllAnime] Found ${showEdges.length} results');
        return AllAnimeSearchResponse.fromJson(data);
      } else {
        debugPrint('[AllAnime] Error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[AllAnime] Search error: $e');
      return null;
    }
  }

  /// Busca lista detalhada de episódios com thumbnails
  static Future<List<AllAnimeEpisode>> getEpisodesListDetailed(
    String animeId, {
    String mode = 'sub',
    String? showThumbnail,
  }) async {
    try {
      debugPrint('[AllAnime] Getting detailed episodes for anime: $animeId');

      const episodesDetailGql = '''
        query (\$showId: String!) {
          show(_id: \$showId) {
            _id
            thumbnail
            episodeInfos
            availableEpisodesDetail
          }
        }
      ''';

      final variables = {'showId': animeId};
      final body = jsonEncode({
        'variables': variables,
        'query': episodesDetailGql,
      });

      final url = Uri.parse(_allAnimeAPI);

      final response = await _client
          .post(
            url,
            headers: {
              'User-Agent': _userAgent,
              'Referer': _allAnimeReferer,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonMap(jsonDecode(response.body)) ?? const {};
        final show = jsonMap(jsonMap(data['data'])?['show']);

        if (show != null) {
          final episodeInfos = jsonList(show['episodeInfos']);
          final episodeInfoByNumber = _indexEpisodeInfos(episodeInfos);
          final availableDetail = jsonMap(show['availableEpisodesDetail']);
          final fallbackThumbnail =
              showThumbnail ?? jsonString(show['thumbnail']);

          // Get available episodes for the mode
          List<String> availableEpisodes = [];
          final modeEpisodes = jsonList(availableDetail?[mode]);
          if (modeEpisodes.isNotEmpty) {
            availableEpisodes = modeEpisodes
                .map((episode) => episode.toString())
                .toList();
          }

          debugPrint(
            '[AllAnime] Processing ${availableEpisodes.length} episodes',
          );
          debugPrint('[AllAnime] Fallback thumbnail: $fallbackThumbnail');

          // Map episode infos with available episodes
          final List<AllAnimeEpisode> episodes = [];
          for (final episodeNum in availableEpisodes) {
            final episodeInfo =
                episodeInfoByNumber[episodeNum] ?? <String, dynamic>{};

            // Try to get episode-specific thumbnail
            String? episodeThumbnail;
            if (episodeInfo.isNotEmpty) {
              // Check for thumbnails array
              if (episodeInfo['thumbnails'] != null &&
                  episodeInfo['thumbnails'] is List) {
                final thumbnails = jsonList(episodeInfo['thumbnails']);
                if (thumbnails.isNotEmpty) {
                  episodeThumbnail = thumbnails.first?.toString();
                }
              }
              // Fallback to single thumbnail field
              episodeThumbnail ??= episodeInfo['thumbnail']?.toString();
            }

            // Use show thumbnail as final fallback
            final finalThumbnail = episodeThumbnail ?? fallbackThumbnail;

            episodes.add(
              AllAnimeEpisode(
                episodeNumber: episodeNum,
                thumbnail: finalThumbnail,
                title:
                    jsonString(episodeInfo['notes']) ?? 'Episode $episodeNum',
                description: jsonString(episodeInfo['description']),
              ),
            );

            if (episodes.length <= 3) {
              debugPrint(
                '[AllAnime] Episode $episodeNum thumbnail: $finalThumbnail',
              );
            }
          }

          debugPrint(
            '[AllAnime] Found ${episodes.length} detailed episodes with thumbnails',
          );
          return episodes;
        }
      }

      debugPrint(
        '[AllAnime] Falling back to simple episode list with show thumbnail',
      );
      final simpleList = await getEpisodesList(animeId, mode: mode);
      return simpleList
          .map(
            (episodeNum) => AllAnimeEpisode(
              episodeNumber: episodeNum,
              thumbnail: showThumbnail,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('[AllAnime] Get detailed episodes error: $e');
      // Return episodes with fallback thumbnail
      try {
        final simpleList = await getEpisodesList(animeId, mode: mode);
        return simpleList
            .map(
              (episodeNum) => AllAnimeEpisode(
                episodeNumber: episodeNum,
                thumbnail: showThumbnail,
              ),
            )
            .toList();
      } catch (fallbackError) {
        debugPrint('[AllAnime] Fallback also failed: $fallbackError');
        return [];
      }
    }
  }

  /// Busca lista de episódios de um anime (versão simples)
  static Future<List<String>> getEpisodesList(
    String animeId, {
    String mode = 'sub',
  }) async {
    try {
      debugPrint('[AllAnime] Getting episodes for anime: $animeId');

      const episodesListGql = '''
        query (\$showId: String!) {
          show(_id: \$showId) {
            _id
            availableEpisodesDetail
          }
        }
      ''';

      final variables = {'showId': animeId};
      final body = jsonEncode({
        'variables': variables,
        'query': episodesListGql,
      });

      final url = Uri.parse(_allAnimeAPI);

      final response = await _client
          .post(
            url,
            headers: {
              'User-Agent': _userAgent,
              'Referer': _allAnimeReferer,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonMap(jsonDecode(response.body)) ?? const {};
        final availableEpisodesDetail = jsonMap(
          jsonMap(jsonMap(data['data'])?['show'])?['availableEpisodesDetail'],
        );

        final modeEpisodes = jsonList(availableEpisodesDetail?[mode]);
        if (modeEpisodes.isNotEmpty) {
          final episodes = modeEpisodes
              .map((episode) => episode.toString())
              .toList();
          episodes.sort((a, b) {
            final numA = double.tryParse(a) ?? 0;
            final numB = double.tryParse(b) ?? 0;
            return numA.compareTo(numB);
          });
          debugPrint('[AllAnime] Found ${episodes.length} episodes');
          return episodes;
        }
      }

      debugPrint('[AllAnime] No episodes found');
      return [];
    } catch (e) {
      debugPrint('[AllAnime] Get episodes error: $e');
      return [];
    }
  }

  /// Decodifica URL encoded do AllAnime (baseado no Curd)
  static String _decodeSourceURL(String encoded) {
    // Mapeamento de decodificação exato do Curd
    const replacements = {
      '01': '9',
      '08': '0',
      '05': '=',
      '0a': '2',
      '0b': '3',
      '0c': '4',
      '07': '?',
      '00': '8',
      '5c': 'd',
      '0f': '7',
      '5e': 'f',
      '17': '/',
      '54': 'l',
      '09': '1',
      '48': 'p',
      '4f': 'w',
      '0e': '6',
      '5b': 'c',
      '5d': 'e',
      '0d': '5',
      '53': 'k',
      '1e': '&',
      '5a': 'b',
      '59': 'a',
      '4a': 'r',
      '4c': 't',
      '4e': 'v',
      '57': 'o',
      '51': 'i',
    };

    final parts = encoded.split(':');
    final mainPart = parts[0];
    final port = parts.length > 1 ? ':${parts[1]}' : '';

    final regex = _twoCharsRegExp;
    final pairs = regex.allMatches(mainPart).map((m) => m.group(0)!).toList();

    for (int i = 0; i < pairs.length; i++) {
      if (replacements.containsKey(pairs[i])) {
        pairs[i] = replacements[pairs[i]]!;
      }
    }

    var result = pairs.join('') + port;
    result = result.replaceAll('/clock', '/clock.json');

    if (result.startsWith('/')) {
      result = 'https://$_allAnimeBase$result';
    }

    return result;
  }

  /// Extrai URLs de fonte da resposta da API
  static List<String> _extractSourceURLs(Map<String, dynamic> data) {
    final urls = <String>[];
    final sourceUrls = jsonList(
      jsonMap(jsonMap(data['data'])?['episode'])?['sourceUrls'],
    );

    if (sourceUrls.isNotEmpty) {
      for (final source in sourceUrls.map(jsonMap).nonNulls) {
        final sourceUrl = jsonString(source['sourceUrl']);
        if (sourceUrl != null) {
          if (sourceUrl.startsWith('--')) {
            final encoded = sourceUrl.substring(2);
            final decoded = _decodeSourceURL(encoded);
            urls.add(decoded);
          } else {
            urls.add(sourceUrl);
          }
        }
      }
    }

    return urls;
  }

  /// Busca URL do episódio
  static Future<String?> getEpisodeURL(
    String animeId,
    String episodeNo, {
    String mode = 'sub',
  }) async {
    try {
      debugPrint(
        '[AllAnime] Getting episode URL: $animeId - Episode $episodeNo',
      );

      const episodeEmbedGQL = '''
        query (\$showId: String!, \$translationType: VaildTranslationTypeEnumType!, \$episodeString: String!) {
          episode(showId: \$showId, translationType: \$translationType, episodeString: \$episodeString) {
            episodeString
            sourceUrls
          }
        }
      ''';

      final variables = {
        'showId': animeId,
        'translationType': mode,
        'episodeString': episodeNo,
      };

      final body = jsonEncode({
        'variables': variables,
        'query': episodeEmbedGQL,
      });

      final url = Uri.parse(_allAnimeAPI);

      final response = await _client
          .post(
            url,
            headers: {
              'User-Agent': _userAgent,
              'Referer': _allAnimeReferer,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonMap(jsonDecode(response.body)) ?? const {};
        final sourceURLs = _extractSourceURLs(data);

        if (sourceURLs.isNotEmpty) {
          // Tentar obter o link de vídeo da primeira fonte
          for (final sourceURL in sourceURLs) {
            final videoURL = await _getVideoLink(sourceURL);
            if (videoURL != null) {
              debugPrint('[AllAnime] Found video URL: $videoURL');
              return videoURL;
            }
          }
        }
      }

      debugPrint('[AllAnime] No video URL found');
      return null;
    } catch (e) {
      debugPrint('[AllAnime] Get episode URL error: $e');
      return null;
    }
  }

  /// Extrai link de vídeo da URL de fonte
  static Future<String?> _getVideoLink(String sourceURL) async {
    try {
      final response = await _client
          .get(
            Uri.parse(sourceURL),
            headers: {'User-Agent': _userAgent, 'Referer': _allAnimeReferer},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonMap(jsonDecode(response.body)) ?? const {};

        final html = response.body;

        // Regex for HLS / MP4
        final mp4Regex = RegExp(
          r'"(https?://[^"]+\.mp4[^"]*)"\s*,\s*"([^"]+)"',
        );
        final mp4Matches = mp4Regex.allMatches(html);
        if (mp4Matches.isNotEmpty) {
          return mp4Matches.first.group(1)!.replaceAll(r'\', '');
        }

        final m3u8Regex = RegExp(r'"(https?://[^"]+\.m3u8[^"]*)"');
        final m3u8Matches = m3u8Regex.allMatches(html);
        if (m3u8Matches.isNotEmpty) {
          return m3u8Matches.first.group(1)!.replaceAll(r'\', '');
        }

        final anyRegex = _anyVideoRegExp;
        final anyMatch = anyRegex.firstMatch(html);
        if (anyMatch != null) {
          return anyMatch.group(1)!.replaceAll(r'\', '');
        }

        // Buscar por links no formato JSON

        final links = jsonList(data['links']);
        if (links.isNotEmpty) {
          for (final link in links.map(jsonMap).nonNulls) {
            final videoLink = jsonString(link['link']);
            if (videoLink != null) {
              return videoLink.replaceAll(r'\', '');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AllAnime] Get video link error: $e');
    }
    return null;
  }
}

/// Resposta da busca do AllAnime
class AllAnimeSearchResponse {
  final List<AllAnimeShow> shows;

  AllAnimeSearchResponse({required this.shows});

  factory AllAnimeSearchResponse.fromJson(Map<String, dynamic> json) {
    final edges = jsonList(jsonMap(jsonMap(json['data'])?['shows'])?['edges']);
    final shows = edges
        .map(jsonMap)
        .nonNulls
        .map(AllAnimeShow.fromJson)
        .toList();
    return AllAnimeSearchResponse(shows: shows);
  }
}

/// Informações de um anime do AllAnime
class AllAnimeShow {
  final String id;
  final String name;
  final String? englishName;
  final Map<String, dynamic>? availableEpisodes;
  final String? thumbnail;

  AllAnimeShow({
    required this.id,
    required this.name,
    this.englishName,
    this.availableEpisodes,
    this.thumbnail,
  });

  factory AllAnimeShow.fromJson(Map<String, dynamic> json) {
    return AllAnimeShow(
      id: jsonStringOr(json['_id'], ''),
      name: jsonStringOr(json['name'], ''),
      englishName: jsonString(json['englishName']),
      availableEpisodes: jsonMap(json['availableEpisodes']),
      thumbnail: jsonString(json['thumbnail']),
    );
  }

  String get displayName =>
      englishName?.isNotEmpty == true ? englishName! : name;

  int get episodeCount {
    if (availableEpisodes != null) {
      final sub = availableEpisodes!['sub'];
      if (sub is num) return sub.toInt();
    }
    return 0;
  }
}

/// Episode information from AllAnime
class AllAnimeEpisode {
  final String episodeNumber;
  final String? thumbnail;
  final String? title;
  final String? description;

  AllAnimeEpisode({
    required this.episodeNumber,
    this.thumbnail,
    this.title,
    this.description,
  });

  /// Get episode thumbnail URL
  String? getImageUrl() {
    if (thumbnail == null || thumbnail!.isEmpty) return null;
    // Ensure thumbnail is a full URL
    if (thumbnail!.startsWith('http')) return thumbnail;
    return 'https://wp.youtube-anime.com/aln.youtube-anime.com/$thumbnail';
  }

  factory AllAnimeEpisode.fromJson(Map<String, dynamic> json) {
    return AllAnimeEpisode(
      episodeNumber: jsonStringOr(json['episodeNumber'], ''),
      thumbnail:
          jsonString(json['thumbnail']) ??
          jsonString(jsonList(json['thumbnails']).firstOrNull),
      title: jsonString(json['title']) ?? jsonString(json['notes']),
      description: jsonString(json['description']),
    );
  }
}
