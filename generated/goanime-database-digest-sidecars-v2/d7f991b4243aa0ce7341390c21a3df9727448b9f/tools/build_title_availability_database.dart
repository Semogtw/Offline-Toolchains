import 'dart:convert';
import 'dart:io';

import 'package:goanime_core/goanime_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'database_digest_sidecar.dart';

const _defaultTitlesPath = 'assets/data/available_animes.json';
const _defaultModesPath = 'assets/data/available_anime_modes.json';
const _defaultUnmatchedPath = 'assets/data/mal_availability_unmatched.json';
const _defaultOutputPath = 'assets/data/title_availability.db';

Future<void> main(List<String> args) async {
  final options = TitleAvailabilityDatabaseOptions.fromArgs(args);
  final payload = await loadTitleAvailabilityRows(options);
  if (!options.dryRun) {
    await buildTitleAvailabilityDatabase(payload, options.outputPath);
  } else {
    await buildTitleAvailabilityDatabase(payload, inMemoryDatabasePath);
  }
  stdout.writeln(
    'Title availability database ${options.dryRun ? 'validated' : 'generated'}: '
    '${payload.rows.length} titles.',
  );
  stdout.writeln('SQLite: ${options.outputPath}');
}

class TitleAvailabilityDatabaseOptions {
  final String titlesPath;
  final String modesPath;
  final String unmatchedPath;
  final String outputPath;
  final bool dryRun;

  const TitleAvailabilityDatabaseOptions({
    this.titlesPath = _defaultTitlesPath,
    this.modesPath = _defaultModesPath,
    this.unmatchedPath = _defaultUnmatchedPath,
    this.outputPath = _defaultOutputPath,
    this.dryRun = false,
  });

  factory TitleAvailabilityDatabaseOptions.fromArgs(List<String> args) {
    var titlesPath = _defaultTitlesPath;
    var modesPath = _defaultModesPath;
    var unmatchedPath = _defaultUnmatchedPath;
    var outputPath = _defaultOutputPath;
    final dryRun = args.contains('--dry-run');

    for (final arg in args) {
      if (arg.startsWith('--titles=')) {
        titlesPath = arg.substring('--titles='.length);
      } else if (arg.startsWith('--modes=')) {
        modesPath = arg.substring('--modes='.length);
      } else if (arg.startsWith('--unmatched=')) {
        unmatchedPath = arg.substring('--unmatched='.length);
      } else if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      }
    }

    return TitleAvailabilityDatabaseOptions(
      titlesPath: titlesPath,
      modesPath: modesPath,
      unmatchedPath: unmatchedPath,
      outputPath: outputPath,
      dryRun: dryRun,
    );
  }
}

class TitleAvailabilityPayload {
  final List<TitleAvailabilityRow> rows;
  final String generatedAt;

  const TitleAvailabilityPayload({
    required this.rows,
    required this.generatedAt,
  });
}

class TitleAvailabilityRow {
  final String normalizedTitle;
  final String displayTitle;
  final TitleModeAvailability modes;
  final String? unmatchedReason;
  final String? candidatesJson;

  const TitleAvailabilityRow({
    required this.normalizedTitle,
    required this.displayTitle,
    required this.modes,
    this.unmatchedReason,
    this.candidatesJson,
  });
}

Future<TitleAvailabilityPayload> loadTitleAvailabilityRows(
  TitleAvailabilityDatabaseOptions options,
) async {
  final titlesDecoded = jsonDecode(
    await File(options.titlesPath).readAsString(),
  );
  if (titlesDecoded is! List) {
    throw FormatException('${options.titlesPath} root is not a JSON list.');
  }

  final modeByTitle = await _loadModes(options.modesPath);
  final unmatchedByTitle = await _loadUnmatched(options.unmatchedPath);
  final rowsByTitle = <String, TitleAvailabilityRow>{};

  for (final rawTitle in titlesDecoded) {
    if (rawTitle is! String) continue;
    final normalized = TitleNormalizer.normalize(rawTitle);
    if (normalized.isEmpty) continue;
    final unmatched = unmatchedByTitle[normalized];
    rowsByTitle[normalized] = TitleAvailabilityRow(
      normalizedTitle: normalized,
      displayTitle: normalized,
      modes:
          modeByTitle[normalized] ??
          const TitleModeAvailability(hasSub: true, hasDub: false),
      unmatchedReason: unmatched?.reason,
      candidatesJson: unmatched == null
          ? null
          : jsonEncode([
              for (final candidate in unmatched.bestCandidates)
                {
                  'malId': candidate.malId,
                  'title': candidate.title,
                  'confidence': candidate.confidence,
                },
            ]),
    );
  }

  final rows = rowsByTitle.values.toList()
    ..sort((a, b) => a.normalizedTitle.compareTo(b.normalizedTitle));
  return TitleAvailabilityPayload(
    rows: rows,
    generatedAt: DateTime.now().toUtc().toIso8601String(),
  );
}

Future<void> buildTitleAvailabilityDatabase(
  TitleAvailabilityPayload payload,
  String outputPath,
) async {
  sqfliteFfiInit();

  final isMemory = outputPath == inMemoryDatabasePath;
  final databasePath = isMemory ? outputPath : File(outputPath).absolute.path;
  if (!isMemory) {
    final output = File(databasePath);
    await output.parent.create(recursive: true);
    if (await output.exists()) await output.delete();
  }

  final db = await databaseFactoryFfi.openDatabase(databasePath);
  try {
    await _createSchema(db);
    final batch = db.batch();
    batch.insert('metadata', {'key': 'schemaVersion', 'value': '1'});
    batch.insert('metadata', {
      'key': 'generatedAt',
      'value': payload.generatedAt,
    });
    for (final row in payload.rows) {
      batch.insert('title_availability', {
        'normalizedTitle': row.normalizedTitle,
        'displayTitle': row.displayTitle,
        'hasSub': row.modes.hasSub ? 1 : 0,
        'hasDub': row.modes.hasDub ? 1 : 0,
        'unmatchedReason': row.unmatchedReason,
        'bestCandidatesJson': row.candidatesJson,
      });
      for (final key in TitleNormalizer.keysForTitle(row.normalizedTitle)) {
        batch.insert('title_keys', {
          'titleKey': key,
          'normalizedTitle': row.normalizedTitle,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    await batch.commit(noResult: true);
    await _validate(db, payload);
  } finally {
    await db.close();
  }
  if (!isMemory) {
    await writeDatabaseDigestSidecar(databasePath);
  }
}

Future<void> _createSchema(Database db) async {
  await db.execute('''
CREATE TABLE metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');
  await db.execute('''
CREATE TABLE title_availability (
  normalizedTitle TEXT PRIMARY KEY,
  displayTitle TEXT NOT NULL,
  hasSub INTEGER NOT NULL,
  hasDub INTEGER NOT NULL,
  unmatchedReason TEXT,
  bestCandidatesJson TEXT
)
''');
  await db.execute('''
CREATE TABLE title_keys (
  titleKey TEXT PRIMARY KEY,
  normalizedTitle TEXT NOT NULL
)
''');
  await db.execute(
    'CREATE INDEX idx_title_keys_normalized ON title_keys(normalizedTitle)',
  );
  await db.execute(
    'CREATE INDEX idx_title_availability_modes '
    'ON title_availability(hasSub, hasDub)',
  );
}

Future<void> _validate(Database db, TitleAvailabilityPayload payload) async {
  final tables = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  final tableNames = tables
      .map((row) => row['name'])
      .whereType<String>()
      .toSet();
  for (final required in const {
    'metadata',
    'title_availability',
    'title_keys',
  }) {
    if (!tableNames.contains(required)) {
      throw FormatException('Generated SQLite is missing $required.');
    }
  }
  final countRows = await db.rawQuery(
    'SELECT COUNT(*) AS count FROM title_availability',
  );
  final count = countRows.first['count'] as int?;
  if (count != payload.rows.length) {
    throw FormatException('Generated SQLite title count mismatch.');
  }
  if (payload.rows.isNotEmpty) {
    final sample = payload.rows.first;
    final keys = TitleNormalizer.keysForTitle(sample.normalizedTitle);
    final rows = await db.query(
      'title_keys',
      where: 'titleKey IN (${List.filled(keys.length, '?').join(',')})',
      whereArgs: keys.toList(),
    );
    if (rows.isEmpty) {
      throw FormatException('Generated SQLite cannot lookup title keys.');
    }
  }
}

Future<Map<String, TitleModeAvailability>> _loadModes(String path) async {
  final file = File(path);
  if (!await file.exists()) return const {};
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) return const {};

  final modes = <String, TitleModeAvailability>{};
  for (final entry in decoded.entries) {
    final title = entry.key;
    if (title is! String) continue;
    final normalized = TitleNormalizer.normalize(title);
    if (normalized.isEmpty) continue;
    final mode = TitleModeAvailability.fromJson(entry.value);
    modes[normalized] = modes[normalized]?.merge(mode) ?? mode;
  }
  return modes;
}

class TitleModeAvailability {
  final bool hasSub;
  final bool hasDub;

  const TitleModeAvailability({required this.hasSub, required this.hasDub});

  factory TitleModeAvailability.fromJson(Object? json) {
    if (json is Map) {
      return TitleModeAvailability(
        hasSub: json['sub'] == true,
        hasDub: json['dub'] == true,
      );
    }
    return const TitleModeAvailability(hasSub: false, hasDub: false);
  }

  TitleModeAvailability merge(TitleModeAvailability other) {
    return TitleModeAvailability(
      hasSub: hasSub || other.hasSub,
      hasDub: hasDub || other.hasDub,
    );
  }
}

Future<Map<String, _UnmatchedEntry>> _loadUnmatched(String path) async {
  final file = File(path);
  if (!await file.exists()) return const {};
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) return const {};
  final entries = decoded['entries'];
  if (entries is! List) return const {};

  final unmatched = <String, _UnmatchedEntry>{};
  for (final entry in entries) {
    if (entry is! Map) continue;
    final normalized = TitleNormalizer.normalize(
      entry['normalizedTitle']?.toString() ??
          entry['availableTitle']?.toString() ??
          '',
    );
    if (normalized.isEmpty) continue;
    final candidates = <_UnmatchedCandidate>[];
    final rawCandidates = entry['bestCandidates'];
    if (rawCandidates is List) {
      for (final candidate in rawCandidates.take(5)) {
        if (candidate is! Map) continue;
        final malId = int.tryParse(candidate['malId']?.toString() ?? '');
        final title = candidate['title']?.toString();
        final confidence = double.tryParse(
          candidate['confidence']?.toString() ?? '',
        );
        if (malId == null || title == null || confidence == null) continue;
        candidates.add(
          _UnmatchedCandidate(
            malId: malId,
            title: title,
            confidence: confidence,
          ),
        );
      }
    }
    unmatched[normalized] = _UnmatchedEntry(
      reason: entry['reason']?.toString() ?? 'unknown',
      bestCandidates: candidates,
    );
  }
  return unmatched;
}

class _UnmatchedEntry {
  final String reason;
  final List<_UnmatchedCandidate> bestCandidates;

  const _UnmatchedEntry({required this.reason, required this.bestCandidates});
}

class _UnmatchedCandidate {
  final int malId;
  final String title;
  final double confidence;

  const _UnmatchedCandidate({
    required this.malId,
    required this.title,
    required this.confidence,
  });
}
