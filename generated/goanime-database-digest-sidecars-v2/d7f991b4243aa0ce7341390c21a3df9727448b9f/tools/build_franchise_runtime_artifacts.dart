import 'dart:convert';
import 'dart:io';

import 'package:goanime/models/anime_franchise_models.dart';
import 'package:goanime/models/franchise_availability_cache_models.dart';
import 'package:goanime/models/franchise_runtime_index_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_digest_sidecar.dart';

const _defaultInputPath = 'assets/data/franchise_availability_map.json';
const _defaultIndexPath = 'assets/data/franchise_index.json';
const _defaultDbPath = 'assets/data/franchise_availability.db';

Future<void> main(List<String> args) async {
  final options = FranchiseRuntimeArtifactOptions.fromArgs(args);
  final result = await buildFranchiseRuntimeArtifacts(options);
  if (!options.dryRun) {
    if (options.buildIndex) {
      await writeFranchiseIndex(result.indexPayload, options.outputIndexPath);
    }
    if (options.buildSqlite) {
      await buildFranchiseSqliteDatabase(
        result.sourcePayload,
        options.outputDbPath,
      );
    }
  }

  stdout.writeln(
    'Runtime artifacts ${options.dryRun ? 'validated' : 'generated'}: '
    '${result.indexPayload.entries.length} index entries, '
    '${result.sourcePayload.franchises.length} franchises.',
  );
  if (options.buildIndex) stdout.writeln('Index: ${options.outputIndexPath}');
  if (options.buildSqlite) stdout.writeln('SQLite: ${options.outputDbPath}');
}

class FranchiseRuntimeArtifactOptions {
  final String inputPath;
  final bool buildIndex;
  final bool buildSqlite;
  final String outputIndexPath;
  final String outputDbPath;
  final bool dryRun;

  const FranchiseRuntimeArtifactOptions({
    this.inputPath = _defaultInputPath,
    this.buildIndex = true,
    this.buildSqlite = true,
    this.outputIndexPath = _defaultIndexPath,
    this.outputDbPath = _defaultDbPath,
    this.dryRun = false,
  });

  factory FranchiseRuntimeArtifactOptions.fromArgs(List<String> args) {
    var inputPath = _defaultInputPath;
    var outputIndexPath = _defaultIndexPath;
    var outputDbPath = _defaultDbPath;
    final explicitBuildFlag =
        args.contains('--build-index') || args.contains('--build-sqlite');
    var buildIndex = !explicitBuildFlag || args.contains('--build-index');
    final buildSqlite = !explicitBuildFlag || args.contains('--build-sqlite');
    final dryRun = args.contains('--dry-run');

    for (final arg in args) {
      if (arg.startsWith('--input=')) {
        inputPath = arg.substring('--input='.length);
      } else if (arg.startsWith('--output-index=')) {
        outputIndexPath = arg.substring('--output-index='.length);
      } else if (arg.startsWith('--output-db=')) {
        outputDbPath = arg.substring('--output-db='.length);
      }
    }

    if (!buildIndex && !buildSqlite) buildIndex = true;

    return FranchiseRuntimeArtifactOptions(
      inputPath: inputPath,
      buildIndex: buildIndex,
      buildSqlite: buildSqlite,
      outputIndexPath: outputIndexPath,
      outputDbPath: outputDbPath,
      dryRun: dryRun,
    );
  }
}

class FranchiseRuntimeArtifactResult {
  final FranchiseAvailabilityCachePayload sourcePayload;
  final FranchiseRuntimeIndexPayload indexPayload;

  const FranchiseRuntimeArtifactResult({
    required this.sourcePayload,
    required this.indexPayload,
  });
}

Future<FranchiseRuntimeArtifactResult> buildFranchiseRuntimeArtifacts(
  FranchiseRuntimeArtifactOptions options,
) async {
  final sourcePayload = await _loadSourcePayload(options.inputPath);
  _validateSourcePayload(sourcePayload);
  final indexPayload = buildFranchiseRuntimeIndex(sourcePayload);
  _validateIndexPayload(indexPayload, sourcePayload);

  if (options.buildSqlite && options.dryRun) {
    await buildFranchiseSqliteDatabase(sourcePayload, inMemoryDatabasePath);
  }

  return FranchiseRuntimeArtifactResult(
    sourcePayload: sourcePayload,
    indexPayload: indexPayload,
  );
}

FranchiseRuntimeIndexPayload buildFranchiseRuntimeIndex(
  FranchiseAvailabilityCachePayload payload,
) {
  final franchisesById = {
    for (final franchise in payload.franchises)
      franchise.franchiseId: franchise,
  };
  final entries = <FranchiseIndexEntry>[];
  final sortedIndex = payload.franchiseIdByMalId.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));

  for (final indexEntry in sortedIndex) {
    final franchise = franchisesById[indexEntry.value];
    if (franchise == null) continue;
    final entry = franchise.entries
        .where((entry) => entry.malId == indexEntry.key)
        .firstOrNull;
    if (entry == null) continue;
    entries.add(
      FranchiseIndexEntry(
        malId: entry.malId,
        franchiseId: franchise.franchiseId,
        canonicalMalId: franchise.canonicalMalId,
        displayTitle: franchise.displayTitle,
        group: entry.group.name,
        sortIndex: entry.sortIndex,
        latestMainlineMalId:
            payload.latestMainlineMalIdByFranchiseId[franchise.franchiseId],
      ),
    );
  }

  return FranchiseRuntimeIndexPayload(
    schemaVersion: FranchiseRuntimeIndexPayload.currentSchemaVersion,
    generatedAt: DateTime.now().toUtc().toIso8601String(),
    franchiseCount: payload.franchises.length,
    entries: entries,
  );
}

Future<void> writeFranchiseIndex(
  FranchiseRuntimeIndexPayload payload,
  String outputPath,
) async {
  final file = File(outputPath);
  await file.parent.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  final content = '${encoder.convert(payload.toJson())}\n';
  jsonDecode(content);
  final tempFile = File('$outputPath.tmp');
  await tempFile.writeAsString(content, flush: true);
  FranchiseRuntimeIndexPayload.fromJson(
    jsonDecode(await tempFile.readAsString()) as Map<String, dynamic>,
  );
  await tempFile.rename(outputPath);
}

Future<void> buildFranchiseSqliteDatabase(
  FranchiseAvailabilityCachePayload payload,
  String outputPath,
) async {
  sqfliteFfiInit();

  final isMemory = outputPath == inMemoryDatabasePath;
  final databasePath = isMemory ? outputPath : File(outputPath).absolute.path;
  if (!isMemory) {
    final file = File(databasePath);
    await file.parent.create(recursive: true);
    if (await file.exists()) await file.delete();
  }

  final db = await databaseFactoryFfi.openDatabase(databasePath);
  try {
    await _createSchema(db);
    await _insertPayload(db, payload);
    await _validateSqlite(db, payload);
  } finally {
    await db.close();
  }
  if (!isMemory) {
    await writeDatabaseDigestSidecar(databasePath);
  }
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
CREATE TABLE franchises (
  franchiseId TEXT PRIMARY KEY,
  canonicalMalId INTEGER NOT NULL,
  displayTitle TEXT NOT NULL,
  coverImage TEXT,
  bannerImage TEXT,
  savedAt TEXT,
  expiresAt TEXT,
  isStale INTEGER,
  payloadJson TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE entries (
  malId INTEGER NOT NULL,
  franchiseId TEXT NOT NULL,
  title TEXT NOT NULL,
  titleEnglish TEXT,
  titleJapanese TEXT,
  year INTEGER,
  season TEXT,
  mediaType TEXT,
  relationType TEXT,
  kind TEXT,
  groupName TEXT,
  isAvailable INTEGER,
  isMainline INTEGER,
  label TEXT,
  sortIndex INTEGER,
  isCanonical INTEGER,
  unavailableReason TEXT,
  animeJson TEXT NOT NULL,
  PRIMARY KEY (franchiseId, malId)
)
''');
  await db.execute('''
CREATE TABLE graph_edges (
  franchiseId TEXT NOT NULL,
  sourceMalId INTEGER NOT NULL,
  targetMalId INTEGER NOT NULL,
  relationType TEXT NOT NULL,
  PRIMARY KEY (franchiseId, sourceMalId, targetMalId, relationType)
)
''');
  await db.execute('''
CREATE TABLE mal_id_index (
  malId INTEGER PRIMARY KEY,
  franchiseId TEXT NOT NULL,
  canonicalMalId INTEGER NOT NULL,
  groupName TEXT,
  sortIndex INTEGER
)
''');
  await db.execute('''
CREATE TABLE latest_mainline (
  franchiseId TEXT PRIMARY KEY,
  malId INTEGER NOT NULL
)
''');
  await db.execute('''
CREATE TABLE anime_images (
  malId INTEGER PRIMARY KEY,
  imageUrl TEXT,
  largeImageUrl TEXT,
  bannerImageUrl TEXT,
  source TEXT NOT NULL DEFAULT 'jikan',
  cachedAt TEXT NOT NULL,
  updatedAt TEXT,
  isFallback INTEGER NOT NULL DEFAULT 0
)
''');
  await db.execute('''
CREATE TABLE franchise_images (
  franchiseId TEXT PRIMARY KEY,
  canonicalMalId INTEGER NOT NULL,
  coverImage TEXT,
  bannerImage TEXT,
  source TEXT NOT NULL DEFAULT 'franchise_cache',
  cachedAt TEXT NOT NULL
)
''');

  await db.execute('CREATE INDEX idx_entries_malId ON entries(malId)');
  await db.execute(
    'CREATE INDEX idx_entries_franchiseId ON entries(franchiseId)',
  );
  await db.execute('CREATE INDEX idx_entries_groupName ON entries(groupName)');
  await db.execute(
    'CREATE INDEX idx_graph_edges_source ON graph_edges(sourceMalId)',
  );
  await db.execute(
    'CREATE INDEX idx_graph_edges_target ON graph_edges(targetMalId)',
  );
  await db.execute(
    'CREATE INDEX idx_mal_id_index_malId ON mal_id_index(malId)',
  );
  await db.execute(
    'CREATE INDEX idx_anime_images_mal_id ON anime_images(malId)',
  );
  await db.execute(
    'CREATE INDEX idx_franchise_images_canonical_mal_id '
    'ON franchise_images(canonicalMalId)',
  );
}

Future<void> _insertPayload(
  Database db,
  FranchiseAvailabilityCachePayload payload,
) async {
  final batch = db.batch();
  for (final franchise in payload.franchises) {
    final franchiseCachedAt = franchise.savedAt.toIso8601String();
    batch.insert('franchises', {
      'franchiseId': franchise.franchiseId,
      'canonicalMalId': franchise.canonicalMalId,
      'displayTitle': franchise.displayTitle,
      'coverImage': franchise.coverImage,
      'bannerImage': franchise.bannerImage,
      'savedAt': franchise.savedAt.toIso8601String(),
      'expiresAt': franchise.expiresAt.toIso8601String(),
      'isStale': franchise.isStale ? 1 : 0,
      'payloadJson': jsonEncode(_compactFranchiseJson(franchise)),
    });
    final franchiseCoverImage = _safeImageUrl(franchise.coverImage);
    final franchiseBannerImage = _safeImageUrl(franchise.bannerImage);
    if (franchiseCoverImage != null || franchiseBannerImage != null) {
      batch.insert('franchise_images', {
        'franchiseId': franchise.franchiseId,
        'canonicalMalId': franchise.canonicalMalId,
        'coverImage': franchiseCoverImage,
        'bannerImage': franchiseBannerImage,
        'source': 'franchise_cache',
        'cachedAt': franchiseCachedAt,
      });
    }

    for (final entry in franchise.entries) {
      batch.insert('entries', {
        'malId': entry.malId,
        'franchiseId': franchise.franchiseId,
        'title': entry.anime.title,
        'titleEnglish': entry.anime.titleEnglish,
        'titleJapanese': entry.anime.titleJapanese,
        'year': entry.anime.year,
        'season': entry.anime.season,
        'mediaType': entry.anime.mediaType,
        'relationType': entry.relationType,
        'kind': entry.kind.name,
        'groupName': entry.group.name,
        'isAvailable': entry.isAvailable ? 1 : 0,
        'isMainline': entry.isMainline ? 1 : 0,
        'label': entry.label,
        'sortIndex': entry.sortIndex,
        'isCanonical': entry.isCanonical ? 1 : 0,
        'unavailableReason': entry.unavailableReason,
        'animeJson': jsonEncode(_pruneJson(entry.anime.toJson())),
      });
      final directImageUrl = _safeImageUrl(
        entry.anime.thumbnailImageUrl ?? entry.anime.imageUrl,
      );
      final directLargeImageUrl = _safeImageUrl(entry.anime.largImageUrl);
      final directBannerImageUrl = _safeImageUrl(entry.anime.bannerImageUrl);
      final hasDirectImage =
          directImageUrl != null ||
          directLargeImageUrl != null ||
          directBannerImageUrl != null;
      final imageUrl = directImageUrl ?? franchiseCoverImage;
      final largeImageUrl = directLargeImageUrl ?? franchiseCoverImage;
      final bannerImageUrl = directBannerImageUrl ?? franchiseBannerImage;
      if (imageUrl != null || largeImageUrl != null || bannerImageUrl != null) {
        batch.insert('anime_images', {
          'malId': entry.malId,
          'imageUrl': imageUrl,
          'largeImageUrl': largeImageUrl,
          'bannerImageUrl': bannerImageUrl,
          'source': hasDirectImage ? 'jikan' : 'franchise_cache',
          'cachedAt': franchiseCachedAt,
          'updatedAt': null,
          'isFallback': hasDirectImage ? 0 : 1,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    for (final edge in franchise.graphEdges) {
      batch.insert('graph_edges', {
        'franchiseId': franchise.franchiseId,
        'sourceMalId': edge.sourceMalId,
        'targetMalId': edge.targetMalId,
        'relationType': edge.relationType,
      });
    }
  }

  final franchisesById = {
    for (final franchise in payload.franchises)
      franchise.franchiseId: franchise,
  };
  for (final item in payload.franchiseIdByMalId.entries) {
    final franchise = franchisesById[item.value];
    final entry = franchise?.entries
        .where((entry) => entry.malId == item.key)
        .firstOrNull;
    if (franchise == null || entry == null) continue;
    batch.insert('mal_id_index', {
      'malId': item.key,
      'franchiseId': item.value,
      'canonicalMalId': franchise.canonicalMalId,
      'groupName': entry.group.name,
      'sortIndex': entry.sortIndex,
    });
  }

  for (final item in payload.latestMainlineMalIdByFranchiseId.entries) {
    batch.insert('latest_mainline', {
      'franchiseId': item.key,
      'malId': item.value,
    });
  }
  await batch.commit(noResult: true);
}

Future<FranchiseAvailabilityCachePayload> _loadSourcePayload(
  String inputPath,
) async {
  final decoded = jsonDecode(await File(inputPath).readAsString());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$inputPath root is not a JSON object.');
  }
  final payload = FranchiseAvailabilityCachePayload.fromJson(decoded);
  if (!payload.hasCompatibleSchema) {
    throw FormatException('$inputPath has incompatible schema.');
  }
  return payload;
}

void _validateSourcePayload(FranchiseAvailabilityCachePayload payload) {
  final franchiseIds = <String>{};
  for (final franchise in payload.franchises) {
    if (!franchiseIds.add(franchise.franchiseId)) {
      throw FormatException('Duplicate franchiseId ${franchise.franchiseId}.');
    }
  }

  final franchisesById = {
    for (final franchise in payload.franchises)
      franchise.franchiseId: franchise,
  };
  for (final indexEntry in payload.franchiseIdByMalId.entries) {
    final franchise = franchisesById[indexEntry.value];
    if (franchise == null) {
      throw FormatException(
        'MAL ${indexEntry.key} points to missing ${indexEntry.value}.',
      );
    }
    if (!franchise.entries.any((entry) => entry.malId == indexEntry.key)) {
      throw FormatException(
        'MAL ${indexEntry.key} points to ${indexEntry.value} without entry.',
      );
    }
  }

  for (final latest in payload.latestMainlineMalIdByFranchiseId.entries) {
    final franchise = franchisesById[latest.key];
    if (franchise == null) {
      throw FormatException('Latest points to missing ${latest.key}.');
    }
    if (!franchise.entries.any((entry) => entry.malId == latest.value)) {
      throw FormatException(
        'Latest for ${latest.key} points to missing MAL ${latest.value}.',
      );
    }
  }
}

void _validateIndexPayload(
  FranchiseRuntimeIndexPayload index,
  FranchiseAvailabilityCachePayload source,
) {
  if (!index.hasCompatibleSchema) {
    throw FormatException('Generated index has incompatible schema.');
  }
  final availableIds = source.franchiseIdByMalId.keys.toSet();
  final indexedIds = index.entries.map((entry) => entry.malId).toSet();
  if (!indexedIds.containsAll(availableIds)) {
    throw FormatException('Generated index is missing available MAL IDs.');
  }
  final sourceFranchiseIds = source.franchises
      .map((franchise) => franchise.franchiseId)
      .toSet();
  for (final entry in index.entries) {
    if (!sourceFranchiseIds.contains(entry.franchiseId)) {
      throw FormatException(
        'Index entry ${entry.malId} points to missing ${entry.franchiseId}.',
      );
    }
    final latest = entry.latestMainlineMalId;
    if (latest != null &&
        !source.franchiseIdByMalId.containsKey(latest) &&
        !source.franchises.any(
          (franchise) =>
              franchise.franchiseId == entry.franchiseId &&
              franchise.entries.any((item) => item.malId == latest),
        )) {
      throw FormatException(
        'Index entry ${entry.malId} has invalid latest $latest.',
      );
    }
  }
}

Future<void> _validateSqlite(
  Database db,
  FranchiseAvailabilityCachePayload payload,
) async {
  if (payload.franchises.isNotEmpty) {
    final franchiseCount = _firstInt(
      await db.rawQuery('SELECT COUNT(*) AS count FROM franchises'),
    );
    final entryCount = _firstInt(
      await db.rawQuery('SELECT COUNT(*) AS count FROM entries'),
    );
    final indexCount = _firstInt(
      await db.rawQuery('SELECT COUNT(*) AS count FROM mal_id_index'),
    );
    if ((franchiseCount ?? 0) == 0 ||
        (entryCount ?? 0) == 0 ||
        (indexCount ?? 0) == 0) {
      throw FormatException('Generated SQLite database has empty tables.');
    }
  }

  final firstIndex = await db.query('mal_id_index', limit: 1);
  if (firstIndex.isNotEmpty) {
    final malId = firstIndex.single['malId'] as int;
    final lookup = await db.query(
      'mal_id_index',
      where: 'malId = ?',
      whereArgs: [malId],
    );
    if (lookup.isEmpty) {
      throw FormatException('Generated SQLite cannot lookup MAL $malId.');
    }
    final franchiseId = lookup.single['franchiseId'] as String;
    final entries = await db.query(
      'entries',
      where: 'franchiseId = ?',
      whereArgs: [franchiseId],
      orderBy: 'sortIndex ASC',
    );
    if (entries.isEmpty) {
      throw FormatException(
        'Generated SQLite cannot load entries for $franchiseId.',
      );
    }
  }

  final indexes = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'index'",
  );
  final indexNames = indexes
      .map((row) => row['name'])
      .whereType<String>()
      .toSet();
  for (final required in const {
    'idx_entries_malId',
    'idx_entries_franchiseId',
    'idx_entries_groupName',
    'idx_graph_edges_source',
    'idx_graph_edges_target',
    'idx_mal_id_index_malId',
    'idx_anime_images_mal_id',
    'idx_franchise_images_canonical_mal_id',
  }) {
    if (!indexNames.contains(required)) {
      throw FormatException('Generated SQLite is missing index $required.');
    }
  }

  await _validateImageTables(db, payload);
}

int? _firstInt(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return null;
  final value = rows.first.values.first;
  return value is int ? value : int.tryParse(value?.toString() ?? '');
}

Future<void> _validateImageTables(
  Database db,
  FranchiseAvailabilityCachePayload payload,
) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  final tableNames = tables
      .map((row) => row['name'])
      .whereType<String>()
      .toSet();
  if (!tableNames.contains('anime_images')) {
    throw FormatException('Generated SQLite is missing anime_images.');
  }
  if (!tableNames.contains('franchise_images')) {
    throw FormatException('Generated SQLite is missing franchise_images.');
  }

  final uniqueMalIds = {
    for (final franchise in payload.franchises)
      for (final entry in franchise.entries)
        if (entry.malId > 0) entry.malId,
  };
  final imageCount = _firstInt(
    await db.rawQuery('SELECT COUNT(*) AS count FROM anime_images'),
  );
  if ((imageCount ?? 0) > uniqueMalIds.length) {
    throw FormatException('anime_images contains duplicated MAL IDs.');
  }

  final duplicateAnimeImages = _firstInt(
    await db.rawQuery('''
SELECT COUNT(*) AS count FROM (
  SELECT malId FROM anime_images GROUP BY malId HAVING COUNT(*) > 1
)
'''),
  );
  if ((duplicateAnimeImages ?? 0) > 0) {
    throw FormatException('anime_images has duplicate malId rows.');
  }

  final duplicateFranchiseImages = _firstInt(
    await db.rawQuery('''
SELECT COUNT(*) AS count FROM (
  SELECT franchiseId FROM franchise_images GROUP BY franchiseId HAVING COUNT(*) > 1
)
'''),
  );
  if ((duplicateFranchiseImages ?? 0) > 0) {
    throw FormatException('franchise_images has duplicate franchiseId rows.');
  }

  for (final table in const ['anime_images', 'franchise_images']) {
    final rows = await db.query(table);
    for (final row in rows) {
      for (final value in row.values.whereType<String>()) {
        if (_containsUnsafeImagePayload(value)) {
          throw FormatException('$table contains unsafe image value.');
        }
      }
    }
  }
}

Map<String, Object?> _compactFranchiseJson(AnimeFranchise franchise) {
  final json = franchise.toJson();
  json['graphNodes'] = [
    for (final node in franchise.graphNodes) {'malId': node.malId},
  ];
  return _pruneJson(json) as Map<String, Object?>;
}

Object? _pruneJson(Object? value) {
  if (value == null) return null;
  if (value is String && value.isEmpty) return null;
  if (value is List) {
    final list = value.map(_pruneJson).where((item) => item != null).toList();
    return list.isEmpty ? null : list;
  }
  if (value is Map) {
    final map = <String, Object?>{};
    for (final entry in value.entries) {
      final pruned = _pruneJson(entry.value);
      if (pruned != null) map[entry.key.toString()] = pruned;
    }
    return map.isEmpty ? null : map;
  }
  return value;
}

String? _safeImageUrl(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  if (_containsUnsafeImagePayload(text)) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  const sensitiveKeys = {
    'token',
    'auth',
    'authorization',
    'cookie',
    'signature',
    'signed',
    'expires',
    'x-amz-signature',
    'x-amz-credential',
  };
  for (final key in uri.queryParameters.keys) {
    if (sensitiveKeys.contains(key.toLowerCase())) return null;
  }
  return text;
}

bool _containsUnsafeImagePayload(String value) {
  final lower = value.toLowerCase();
  return lower.startsWith('data:') ||
      lower.contains(';base64') ||
      lower.contains('base64,');
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
