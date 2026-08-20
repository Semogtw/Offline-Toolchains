import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:goanime/models/anime_metadata_cache_models.dart';
import 'package:http/http.dart' as http;

import 'anilist_metadata_bulk_loader.dart';

const _targetsPath = 'tools/anime_metadata_seed_targets.json';
const _bundledSeedPath = 'assets/data/anime_metadata_seed.json';
const _malAvailabilityPath = 'assets/data/mal_availability_map.json';
const _outputDir = 'dist/anime_metadata_cache';
const _jikanBaseUrl = 'https://api.jikan.moe/v4';
const _requestDelay = Duration(milliseconds: 1100);
const _maxAttempts = 4;
const _minimumStrictAvailabilityCoverage = 0.90;

Future<void> main(List<String> args) async {
  final targetsPath =
      _optionValue(args, '--targets=') ??
      _firstPositionalArgument(args) ??
      _targetsPath;
  final baselinePath = _optionValue(args, '--baseline=') ?? _bundledSeedPath;
  final availabilityPath =
      _optionValue(args, '--availability=') ?? _malAvailabilityPath;

  final targetsFile = File(targetsPath);
  if (!await targetsFile.exists()) {
    stderr.writeln('Targets file not found: ${targetsFile.path}');
    exitCode = 1;
    return;
  }

  final decoded = jsonDecode(await targetsFile.readAsString());
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('Invalid targets file.');
    exitCode = 1;
    return;
  }

  final entriesById = await loadBundledMetadataBaseline(baselinePath);
  final baselineCount = entriesById.length;
  final strictAvailabilityTargets = await loadStrictAvailabilityTargets(
    availabilityPath,
  );
  final strictAvailabilityIds = strictAvailabilityTargets
      .map((target) => target.malId)
      .toSet();
  final ignoredUnsafeIds = <int>{};
  final client = http.Client();
  final broadcastsById = <int, Map<String, String?>>{};
  final failures = <String>[];
  final queries = decoded['queries'] is List
      ? decoded['queries'] as List
      : const <Object?>[];
  final targets = decoded['targets'] is List
      ? decoded['targets'] as List
      : const <Object?>[];
  final refreshReference = DateTime.now().toUtc();
  var fetchedExplicitTargets = 0;
  var fetchedAvailabilityTargets = 0;
  var jikanAvailabilityRepairAttempts = 0;
  var jikanAvailabilityRepairRecovered = 0;

  try {
    for (final rawQuery in queries) {
      if (rawQuery is! Map<String, dynamic>) continue;
      final path = rawQuery['path']?.toString().trim() ?? '';
      if (path.isEmpty || !path.startsWith('/')) {
        failures.add('query: invalid path "$path"');
        continue;
      }
      final pages = _asInt(rawQuery['pages']) ?? 1;
      final rawParameters = rawQuery['query'];
      final parameters = <String, String>{};
      if (rawParameters is Map) {
        for (final entry in rawParameters.entries) {
          final key = entry.key.toString().trim();
          final value = entry.value?.toString().trim() ?? '';
          if (key.isNotEmpty && value.isNotEmpty) parameters[key] = value;
        }
      }

      for (var page = 1; page <= pages; page += 1) {
        final queryParameters = <String, String>{
          ...parameters,
          if (pages > 1) 'page': '$page',
        };
        final uri = Uri.parse(
          '$_jikanBaseUrl$path',
        ).replace(queryParameters: queryParameters);
        try {
          final response = await _getWithRetry(client, uri);
          if (response.statusCode != 200) {
            failures.add('$path page $page: HTTP ${response.statusCode}');
            continue;
          }
          final body = jsonDecode(response.body);
          final data = body is Map<String, dynamic> ? body['data'] : null;
          if (data is! List) {
            failures.add('$path page $page: missing data list');
            continue;
          }
          for (final item in data.whereType<Map<String, dynamic>>()) {
            _addEntry(entriesById, item, replaceExisting: true);
            _addBroadcast(broadcastsById, item);
          }
        } catch (error) {
          failures.add('$path page $page: $error');
        }
        await Future<void>.delayed(_requestDelay);
      }
    }

    for (final target in targets) {
      if (target is! Map<String, dynamic>) continue;
      final malId = target['malId'] is int
          ? target['malId'] as int
          : int.tryParse(target['malId']?.toString() ?? '');
      final title = target['title']?.toString() ?? 'unknown';
      if (malId == null || malId <= 0) {
        failures.add('$title: invalid malId');
        continue;
      }
      final existing = entriesById[malId];
      if (existing != null &&
          !shouldRefreshBundledMetadata(existing, refreshReference)) {
        continue;
      }

      final result = await _fetchAnimeByMalId(
        client,
        malId: malId,
        title: title,
        entriesById: entriesById,
        broadcastsById: broadcastsById,
        failures: failures,
        ignoredUnsafeIds: ignoredUnsafeIds,
      );
      if (result == MetadataFetchResult.fetched) {
        fetchedExplicitTargets += 1;
      }
      await Future<void>.delayed(_requestDelay);
    }

    final missingStrictTargets = <int, String>{
      for (final target in strictAvailabilityTargets)
        if (!entriesById.containsKey(target.malId) &&
            !ignoredUnsafeIds.contains(target.malId))
          target.malId: target.title,
    };
    if (missingStrictTargets.isNotEmpty) {
      final bulkResult = await fetchAniListMetadataBulk(
        client: client,
        targets: missingStrictTargets,
      );
      entriesById.addAll(bulkResult.entries);
      ignoredUnsafeIds.addAll(bulkResult.unsafeMalIds);
      failures.addAll(bulkResult.failures);
      fetchedAvailabilityTargets += bulkResult.entries.length;
    }

    var strictAvailabilityAccounted = strictAvailabilityTargets
        .where(
          (target) =>
              entriesById.containsKey(target.malId) ||
              ignoredUnsafeIds.contains(target.malId),
        )
        .length;
    final requiredStrictAvailability = _requiredStrictAvailabilityCount(
      strictAvailabilityTargets.length,
    );

    // AniList is the broad, efficient enrichment path. Jikan is deliberately
    // reserved for the residual gap and stops as soon as the publication gate
    // is satisfied, avoiding thousands of individual requests.
    if (strictAvailabilityAccounted < requiredStrictAvailability) {
      for (final target in strictAvailabilityTargets) {
        if (strictAvailabilityAccounted >= requiredStrictAvailability) break;
        if (entriesById.containsKey(target.malId) ||
            ignoredUnsafeIds.contains(target.malId)) {
          continue;
        }

        jikanAvailabilityRepairAttempts += 1;
        final result = await _fetchAnimeByMalId(
          client,
          malId: target.malId,
          title: target.title,
          entriesById: entriesById,
          broadcastsById: broadcastsById,
          failures: failures,
          ignoredUnsafeIds: ignoredUnsafeIds,
        );
        if (result == MetadataFetchResult.fetched) {
          fetchedAvailabilityTargets += 1;
          jikanAvailabilityRepairRecovered += 1;
          strictAvailabilityAccounted += 1;
        } else if (result == MetadataFetchResult.unsafe) {
          strictAvailabilityAccounted += 1;
        }
        await Future<void>.delayed(_requestDelay);
      }
    }
  } finally {
    client.close();
  }

  final strictAvailabilityCovered = strictAvailabilityTargets
      .where((target) => entriesById.containsKey(target.malId))
      .length;
  final strictAvailabilityUnsafe = ignoredUnsafeIds
      .where(strictAvailabilityIds.contains)
      .length;
  final strictAvailabilityAccounted =
      strictAvailabilityCovered + strictAvailabilityUnsafe;
  if (!_hasRequiredStrictAvailabilityCoverage(
    covered: strictAvailabilityAccounted,
    total: strictAvailabilityTargets.length,
  )) {
    final required = _requiredStrictAvailabilityCount(
      strictAvailabilityTargets.length,
    );
    stderr.writeln(
      'Strict availability metadata coverage is incomplete: '
      '$strictAvailabilityCovered rich + $strictAvailabilityUnsafe unsafe '
      'of ${strictAvailabilityTargets.length}; required at least $required '
      'accounted identities.',
    );
    exitCode = 1;
    return;
  }

  final entries = entriesById.values.toList(growable: false)
    ..sort((a, b) {
      final popularity = (b.popularity ?? 0).compareTo(a.popularity ?? 0);
      if (popularity != 0) return popularity;
      return (b.score ?? 0).compareTo(a.score ?? 0);
    });

  if (entries.isEmpty) {
    final outputDirectory = Directory(_outputDir);
    if (await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
    stderr.writeln('No metadata entries were generated.');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  final generatedAt = DateTime.now().toUtc();
  final payload = AnimeMetadataSeedPayload(
    schemaVersion: AnimeMetadataSeedPayload.currentSchemaVersion,
    generatedAt: generatedAt,
    entries: entries,
  );
  final payloadJson = const JsonEncoder.withIndent(
    '  ',
  ).convert(payload.toJson());
  final payloadBytes = utf8.encode(payloadJson);
  final bundledDigest = sha256.convert(payloadBytes).toString();
  final gzipBytes = gzip.encode(payloadBytes);
  final digest = sha256.convert(gzipBytes).toString();

  final outputDirectory = Directory(_outputDir);
  await outputDirectory.create(recursive: true);

  final jsonFile = File('$_outputDir/anime_metadata_seed.json');
  final bundledShaFile = File('$_outputDir/anime_metadata_seed.json.sha256');
  final gzipFile = File('$_outputDir/anime_metadata_seed.json.gz');
  final shaFile = File('$_outputDir/anime_metadata_seed.sha256');
  final manifestFile = File('$_outputDir/anime_metadata_manifest.json');
  final broadcastFile = File('$_outputDir/broadcast_schedule.json');

  await jsonFile.writeAsString(payloadJson);
  await bundledShaFile.writeAsString('$bundledDigest\n');
  await gzipFile.writeAsBytes(gzipBytes);
  await shaFile.writeAsString('$digest  anime_metadata_seed.json.gz\n');

  final publicBaseUrl = Platform.environment['ANIME_METADATA_PUBLIC_BASE_URL'];
  final assetUrl = publicBaseUrl == null || publicBaseUrl.trim().isEmpty
      ? 'anime_metadata_seed.json.gz'
      : '${publicBaseUrl.replaceFirst(RegExp(r"/+$"), '')}/anime_metadata_seed.json.gz';
  final manifest = AnimeMetadataSeedManifest(
    schemaVersion: AnimeMetadataSeedManifest.currentSchemaVersion,
    generatedAt: generatedAt,
    expiresAt: generatedAt.add(const Duration(days: 30)),
    asset: AnimeMetadataSeedAsset(
      url: assetUrl,
      sha256: digest,
      sizeBytes: gzipBytes.length,
    ),
  );
  await manifestFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
  );
  await broadcastFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'generatedAt': generatedAt.toIso8601String(),
      'entries': {
        for (final entry in broadcastsById.entries)
          entry.key.toString(): {
            'broadcastDay': entry.value['broadcastDay'],
            if (entry.value['broadcastTime'] != null)
              'broadcastTime': entry.value['broadcastTime'],
            if (entry.value['broadcastString'] != null)
              'broadcastString': entry.value['broadcastString'],
          },
      },
    }),
  );

  stdout.writeln('Anime metadata seed generated.');
  stdout.writeln('baselineEntries=$baselineCount');
  stdout.writeln('queries=${queries.length}');
  stdout.writeln('targets=${targets.length}');
  stdout.writeln(
    'strictAvailabilityTargets=${strictAvailabilityTargets.length}',
  );
  stdout.writeln('strictAvailabilityCovered=$strictAvailabilityCovered');
  stdout.writeln('strictAvailabilityUnsafe=$strictAvailabilityUnsafe');
  stdout.writeln('fetchedExplicitTargets=$fetchedExplicitTargets');
  stdout.writeln('fetchedAvailabilityTargets=$fetchedAvailabilityTargets');
  stdout.writeln(
    'jikanAvailabilityRepairAttempts=$jikanAvailabilityRepairAttempts',
  );
  stdout.writeln(
    'jikanAvailabilityRepairRecovered=$jikanAvailabilityRepairRecovered',
  );
  stdout.writeln('success=${entries.length}');
  stdout.writeln('broadcasts=${broadcastsById.length}');
  stdout.writeln('failures=${failures.length}');
  stdout.writeln('jsonBytes=${payloadBytes.length}');
  stdout.writeln('gzipBytes=${gzipBytes.length}');
  if (failures.isNotEmpty) {
    stdout.writeln('Failure report:');
    for (final failure in failures) {
      stdout.writeln('- $failure');
    }
  }
}

Future<Map<int, AnimeMetadataCacheEntry>> loadBundledMetadataBaseline(
  String path,
) async {
  final file = File(path);
  if (!await file.exists()) return <int, AnimeMetadataCacheEntry>{};
  try {
    final payload = AnimeMetadataSeedPayload.fromJson(
      jsonDecode(await file.readAsString()),
    );
    if (!payload.isCompatible) return <int, AnimeMetadataCacheEntry>{};
    return <int, AnimeMetadataCacheEntry>{
      for (final entry in payload.entries)
        if (entry.malId > 0 &&
            entry.title.trim().isNotEmpty &&
            (entry.imageUrl?.trim().isNotEmpty ?? false) &&
            _isSafeCachedMetadata(entry))
          entry.malId: entry,
    };
  } catch (error) {
    stderr.writeln('Ignoring invalid metadata baseline at $path: $error');
    return <int, AnimeMetadataCacheEntry>{};
  }
}

Future<List<MetadataAvailabilityTarget>> loadStrictAvailabilityTargets(
  String path,
) async {
  final file = File(path);
  if (!await file.exists()) return const <MetadataAvailabilityTarget>[];
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) {
    throw FormatException('$path root must be a JSON object.');
  }
  final rawEntries = decoded['entries'];
  if (rawEntries is! List) return const <MetadataAvailabilityTarget>[];

  final targetsById = <int, MetadataAvailabilityTarget>{};
  for (final raw in rawEntries) {
    if (raw is! Map) continue;
    final malId = _asInt(raw['malId']);
    final title = raw['canonicalTitle']?.toString().trim() ?? '';
    final modes = raw['modes'];
    final isAvailable =
        modes is Map && (modes['sub'] == true || modes['dub'] == true);
    if (malId == null || malId <= 0 || title.isEmpty || !isAvailable) continue;
    targetsById.putIfAbsent(
      malId,
      () => MetadataAvailabilityTarget(malId: malId, title: title),
    );
  }
  final targets = targetsById.values.toList(growable: false)
    ..sort((a, b) => a.malId.compareTo(b.malId));
  return targets;
}

bool shouldRefreshBundledMetadata(AnimeMetadataCacheEntry entry, DateTime now) {
  final reference = now.toUtc();
  final currentSeason = switch (reference.month) {
    >= 1 && <= 3 => 'winter',
    >= 4 && <= 6 => 'spring',
    >= 7 && <= 9 => 'summer',
    _ => 'fall',
  };
  final entrySeason = entry.season?.trim().toLowerCase();
  if (entry.year == reference.year && entrySeason == currentSeason) {
    return true;
  }

  final status = entry.status?.trim().toLowerCase() ?? '';
  return status.contains('currently airing') ||
      status == 'airing' ||
      status.contains('releasing') ||
      status.contains('not yet') ||
      status.contains('upcoming');
}

int strictAvailabilityRepairBudget({
  required int accounted,
  required int total,
}) {
  final required = _requiredStrictAvailabilityCount(total);
  final remaining = required - accounted;
  return remaining > 0 ? remaining : 0;
}

bool hasRequiredStrictAvailabilityCoverage({
  required int covered,
  required int total,
}) {
  return _hasRequiredStrictAvailabilityCoverage(covered: covered, total: total);
}

bool _hasRequiredStrictAvailabilityCoverage({
  required int covered,
  required int total,
}) {
  if (total <= 0) return true;
  return covered >= _requiredStrictAvailabilityCount(total);
}

int _requiredStrictAvailabilityCount(int total) {
  if (total <= 0) return 0;
  return (total * _minimumStrictAvailabilityCoverage).ceil();
}

Future<MetadataFetchResult> _fetchAnimeByMalId(
  http.Client client, {
  required int malId,
  required String title,
  required Map<int, AnimeMetadataCacheEntry> entriesById,
  required Map<int, Map<String, String?>> broadcastsById,
  required List<String> failures,
  required Set<int> ignoredUnsafeIds,
}) async {
  try {
    final response = await _getWithRetry(
      client,
      Uri.parse('$_jikanBaseUrl/anime/$malId'),
    );
    if (response.statusCode != 200) {
      failures.add('$title: HTTP ${response.statusCode}');
      return MetadataFetchResult.failed;
    }
    final body = jsonDecode(response.body);
    final data = body is Map<String, dynamic> ? body['data'] : null;
    if (data is! Map<String, dynamic>) {
      failures.add('$title: missing data');
      return MetadataFetchResult.failed;
    }
    if (!_isSafeJikanMetadata(data)) {
      ignoredUnsafeIds.add(malId);
      entriesById.remove(malId);
      return MetadataFetchResult.unsafe;
    }
    _addEntry(entriesById, data, replaceExisting: true);
    _addBroadcast(broadcastsById, data);
    return entriesById.containsKey(malId)
        ? MetadataFetchResult.fetched
        : MetadataFetchResult.failed;
  } catch (error) {
    failures.add('$title: $error');
    return MetadataFetchResult.failed;
  }
}

Future<http.Response> _getWithRetry(http.Client client, Uri uri) async {
  http.Response? lastResponse;
  Object? lastError;
  for (var attempt = 1; attempt <= _maxAttempts; attempt += 1) {
    try {
      final response = await client
          .get(uri)
          .timeout(const Duration(seconds: 20));
      lastResponse = response;
      if (response.statusCode == 200) return response;
      final retryable =
          response.statusCode == 429 || response.statusCode >= 500;
      if (!retryable || attempt == _maxAttempts) return response;

      final retryAfter =
          response.headers['Retry-After'] ?? response.headers['retry-after'];
      final retryAfterSeconds = int.tryParse(retryAfter ?? '');
      await Future<void>.delayed(
        Duration(seconds: retryAfterSeconds ?? attempt * 2),
      );
    } catch (error) {
      lastError = error;
      if (attempt == _maxAttempts) rethrow;
      await Future<void>.delayed(Duration(seconds: attempt * 2));
    }
  }
  if (lastResponse != null) return lastResponse;
  throw StateError('Jikan request failed without response: $lastError');
}

void _addEntry(
  Map<int, AnimeMetadataCacheEntry> entries,
  Map<String, dynamic> data, {
  bool replaceExisting = false,
}) {
  if (!_isSafeJikanMetadata(data)) return;
  final entry = _entryFromJikan(data);
  if (entry.malId <= 0 ||
      entry.title.trim().isEmpty ||
      (entry.imageUrl?.trim().isEmpty ?? true)) {
    return;
  }
  if (replaceExisting) {
    entries[entry.malId] = entry;
  } else {
    entries.putIfAbsent(entry.malId, () => entry);
  }
}

bool _isSafeJikanMetadata(Map<String, dynamic> data) {
  final rating = data['rating']?.toString().toLowerCase() ?? '';
  if (rating.contains('rx') ||
      rating.contains('hentai') ||
      rating.contains('r+')) {
    return false;
  }
  final genres = _namedList(
    data['genres'],
  ).map((genre) => genre.toLowerCase()).toSet();
  return !genres.contains('hentai') && !genres.contains('erotica');
}

bool _isSafeCachedMetadata(AnimeMetadataCacheEntry entry) {
  final genres = entry.genres.map((genre) => genre.toLowerCase()).toSet();
  return !genres.contains('hentai') && !genres.contains('erotica');
}

AnimeMetadataCacheEntry _entryFromJikan(Map<String, dynamic> data) {
  final images = data['images'] as Map<String, dynamic>?;
  final webp = images?['webp'] as Map<String, dynamic>?;
  final jpg = images?['jpg'] as Map<String, dynamic>?;
  final aired = data['aired'] as Map<String, dynamic>?;
  final prop = aired?['prop'] as Map<String, dynamic>?;
  final from = prop?['from'] as Map<String, dynamic>?;

  return AnimeMetadataCacheEntry(
    malId: _asInt(data['mal_id']) ?? 0,
    title: data['title']?.toString() ?? 'Unknown',
    titleEnglish: _optionalString(data['title_english']),
    titleJapanese: _optionalString(data['title_japanese']),
    synonyms: _stringList(data['title_synonyms']),
    status: _optionalString(data['status']),
    episodes: _asInt(data['episodes']),
    year: _asInt(data['year']) ?? _asInt(from?['year']),
    season: _optionalString(data['season']),
    score: _asDouble(data['score']),
    popularity: _asInt(data['members']) ?? _asInt(data['popularity']),
    imageUrl:
        _optionalString(webp?['large_image_url']) ??
        _optionalString(webp?['image_url']) ??
        _optionalString(jpg?['large_image_url']) ??
        _optionalString(jpg?['image_url']),
    genres: _namedList(data['genres']),
    updatedAt: DateTime.now().toUtc(),
    source: 'jikan',
  );
}

void _addBroadcast(
  Map<int, Map<String, String?>> broadcasts,
  Map<String, dynamic> data,
) {
  final malId = _asInt(data['mal_id']);
  if (malId == null || malId <= 0) return;

  final status = data['status']?.toString().trim().toLowerCase() ?? '';
  if (status.contains('finished')) return;
  final isRelevant =
      status.contains('currently airing') ||
      status == 'airing' ||
      status.contains('releasing') ||
      status.contains('not yet') ||
      status.contains('upcoming');
  if (!isRelevant) return;

  final broadcast = data['broadcast'];
  if (broadcast is! Map) return;
  final day = _optionalString(broadcast['day']);
  if (day == null || day.toLowerCase() == 'unknown') return;

  broadcasts[malId] = {
    'broadcastDay': day,
    'broadcastTime': _optionalString(broadcast['time']),
    'broadcastString': _optionalString(broadcast['string']),
  };
}

String? _optionValue(List<String> args, String prefix) {
  for (final arg in args) {
    if (arg.startsWith(prefix)) return arg.substring(prefix.length);
  }
  return null;
}

String? _firstPositionalArgument(List<String> args) {
  for (final arg in args) {
    if (!arg.startsWith('--')) return arg;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item?.toString().trim())
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toList();
}

List<String> _namedList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((item) => item['name']?.toString().trim())
      .whereType<String>()
      .where((item) => item.isNotEmpty)
      .toList();
}

class MetadataAvailabilityTarget {
  final int malId;
  final String title;

  const MetadataAvailabilityTarget({required this.malId, required this.title});
}

enum MetadataFetchResult { fetched, unsafe, failed }
