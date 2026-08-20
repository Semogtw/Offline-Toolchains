import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'super_animes_catalog_crosswalk.dart';
import 'super_animes_retry_policy.dart';

const _aniListEndpoint = 'https://graphql.anilist.co';
const _defaultRequestTimeout = Duration(seconds: 20);
const _defaultMinimumDelayBetweenRequests = Duration(milliseconds: 2100);
const _defaultMaxAttempts = 4;

typedef SuperAnimesAniListSleeper = Future<void> Function(Duration duration);

class SuperAnimesAniListGraphQlException implements Exception {
  const SuperAnimesAniListGraphQlException(this.messages);

  final List<String> messages;

  @override
  String toString() {
    final details = messages.isEmpty
        ? 'unknown GraphQL error'
        : messages.join('; ');
    return 'AniList GraphQL error: $details';
  }
}

class SuperAnimesAniListMalResolver {
  SuperAnimesAniListMalResolver(
    this._client, {
    Duration minimumDelayBetweenRequests = _defaultMinimumDelayBetweenRequests,
    Duration requestTimeout = _defaultRequestTimeout,
    int maxAttempts = _defaultMaxAttempts,
    SuperAnimesAniListSleeper sleeper = _defaultSleep,
  }) : _minimumDelayBetweenRequests = minimumDelayBetweenRequests,
       _requestTimeout = requestTimeout,
       _maxAttempts = maxAttempts,
       _sleeper = sleeper {
    if (minimumDelayBetweenRequests.isNegative) {
      throw ArgumentError.value(
        minimumDelayBetweenRequests,
        'minimumDelayBetweenRequests',
        'must not be negative',
      );
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
    if (maxAttempts <= 0) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
    }
  }

  final http.Client _client;
  final Duration _minimumDelayBetweenRequests;
  final Duration _requestTimeout;
  final int _maxAttempts;
  final SuperAnimesAniListSleeper _sleeper;
  DateTime? _lastRequestAt;

  Future<Map<int, int>> resolveBatch(Iterable<int> rawAniListIds) async {
    final ids = rawAniListIds.where((id) => id > 0).toSet().toList()..sort();
    if (ids.isEmpty) return const <int, int>{};
    if (ids.length > superAnimesAniListMalBatchSize) {
      throw ArgumentError.value(
        ids.length,
        'rawAniListIds',
        'cannot exceed $superAnimesAniListMalBatchSize unique positive ids',
      );
    }

    Object? lastError;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      await _respectRateLimit();
      try {
        _lastRequestAt = DateTime.now();
        final response = await _client
            .post(
              Uri.parse(_aniListEndpoint),
              headers: const <String, String>{
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'User-Agent': 'GoAnime-super-animes-crosswalk/1.0',
              },
              body: jsonEncode(<String, Object>{
                'query': superAnimesAniListMalBatchQuery,
                'variables': <String, Object>{'ids': ids},
              }),
            )
            .timeout(_requestTimeout);

        if (response.statusCode == 200) {
          _validateGraphQlResponse(response.body);
          return parseSuperAnimesAniListMalBatchResponse(
            response.body,
            expectedAniListIds: ids,
          );
        }

        final error = HttpException(
          'AniList returned HTTP ${response.statusCode}',
          uri: Uri.parse(_aniListEndpoint),
        );
        if (!_isRetryableStatus(response.statusCode)) throw error;
        lastError = error;
        if (attempt + 1 < _maxAttempts &&
            !await waitForSuperAnimesRetry(
              attempt: attempt,
              retryAfter: response.headers['retry-after'],
              sleeper: _sleeper,
            )) {
          break;
        }
      } on SuperAnimesAniListGraphQlException {
        rethrow;
      } on FormatException {
        rethrow;
      } on HttpException catch (error) {
        if (!_isRetryableHttpException(error)) rethrow;
        lastError = error;
        if (attempt + 1 < _maxAttempts &&
            !await waitForSuperAnimesRetry(
              attempt: attempt,
              sleeper: _sleeper,
            )) {
          break;
        }
      } on TimeoutException catch (error) {
        lastError = error;
        if (attempt + 1 < _maxAttempts &&
            !await waitForSuperAnimesRetry(
              attempt: attempt,
              sleeper: _sleeper,
            )) {
          break;
        }
      } on http.ClientException catch (error) {
        lastError = error;
        if (attempt + 1 < _maxAttempts &&
            !await waitForSuperAnimesRetry(
              attempt: attempt,
              sleeper: _sleeper,
            )) {
          break;
        }
      } on SocketException catch (error) {
        lastError = error;
        if (attempt + 1 < _maxAttempts &&
            !await waitForSuperAnimesRetry(
              attempt: attempt,
              sleeper: _sleeper,
            )) {
          break;
        }
      }
    }

    throw lastError ?? StateError('AniList MAL batch resolution failed');
  }

  Future<SuperAnimesCatalogCrosswalk> enrich(
    SuperAnimesCatalogCrosswalk crosswalk,
  ) async {
    final mappings = <int, int>{};
    for (final batch in superAnimesAniListMalBatches(crosswalk)) {
      mappings.addAll(await resolveBatch(batch));
    }
    return enrichSuperAnimesCatalogCrosswalkWithAniList(crosswalk, mappings);
  }

  Future<void> _respectRateLimit() async {
    final lastRequestAt = _lastRequestAt;
    if (lastRequestAt == null) return;
    final elapsed = DateTime.now().difference(lastRequestAt);
    if (elapsed < _minimumDelayBetweenRequests) {
      await _sleeper(_minimumDelayBetweenRequests - elapsed);
    }
  }
}

void _validateGraphQlResponse(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('AniList response must be a JSON object.');
  }

  final rawErrors = decoded['errors'];
  if (rawErrors is List && rawErrors.isNotEmpty) {
    final messages = rawErrors
        .whereType<Map<String, dynamic>>()
        .map((error) => error['message']?.toString().trim() ?? '')
        .where((message) => message.isNotEmpty)
        .toList();
    throw SuperAnimesAniListGraphQlException(messages);
  }

  final data = decoded['data'];
  final page = data is Map<String, dynamic> ? data['Page'] : null;
  final media = page is Map<String, dynamic> ? page['media'] : null;
  if (data is! Map<String, dynamic> ||
      page is! Map<String, dynamic> ||
      media is! List) {
    throw const FormatException('AniList response is missing data.Page.media.');
  }
}

bool _isRetryableStatus(int statusCode) =>
    statusCode == 429 || statusCode >= 500;

bool _isRetryableHttpException(HttpException error) {
  return RegExp(r'HTTP (429|5\d\d)\b').hasMatch(error.message);
}

Future<void> _defaultSleep(Duration duration) => Future<void>.delayed(duration);
