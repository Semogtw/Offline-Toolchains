import 'package:flutter/foundation.dart';
import 'package:goanime_core/goanime_core.dart';
import 'package:sqflite/sqflite.dart';

import 'availability_service.dart';
import 'bundled_database_asset_service.dart';
import 'runtime_database_update_service.dart';

class TitleAvailabilityDatabaseService {
  static const String databaseId = 'title_availability';
  static const String assetPath = 'assets/data/title_availability.db';
  static const String digestAssetPath =
      'assets/data/title_availability.db.sha256';
  static const String _databasePrefix = 'title_availability_asset';

  static Database? _database;
  static Future<void>? _initializeFuture;
  static bool _initialized = false;
  static bool _available = false;

  static bool get isAvailable => _available;

  static Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializeFuture ??= _load();
  }

  static Future<List<TitleAvailabilityDbEntry>> loadAllEntries() async {
    await initialize();
    final db = _database;
    if (!_available || db == null) return const [];

    final rows = await db.query(
      'title_availability',
      columns: ['normalizedTitle', 'hasSub', 'hasDub'],
      orderBy: 'normalizedTitle ASC',
    );
    return rows.map(TitleAvailabilityDbEntry.fromMap).toList();
  }

  static Future<TitleAvailabilityDbEntry?> entryForTitle(String title) async {
    await initialize();
    final db = _database;
    if (!_available || db == null) return null;

    final keys = TitleNormalizer.keysForTitle(title).toList();
    if (keys.isEmpty) return null;

    final keyRows = await db.query(
      'title_keys',
      columns: ['normalizedTitle'],
      where: 'titleKey IN (${List.filled(keys.length, '?').join(',')})',
      whereArgs: keys,
      limit: 1,
    );
    if (keyRows.isEmpty) return null;
    final normalizedTitle = keyRows.first['normalizedTitle']?.toString();
    if (normalizedTitle == null || normalizedTitle.isEmpty) return null;

    final rows = await db.query(
      'title_availability',
      where: 'normalizedTitle = ?',
      whereArgs: [normalizedTitle],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TitleAvailabilityDbEntry.fromMap(rows.single);
  }

  static Future<void> debugSetDatabasePathForTesting(String path) async {
    await resetForRuntimeDatabaseUpdate();
    _database = await openDatabase(path, readOnly: true);
    _available = true;
    _initialized = true;
  }

  static Future<void> resetForRuntimeDatabaseUpdate() async {
    final db = _database;
    _database = null;
    _available = false;
    _initialized = false;
    _initializeFuture = null;
    await db?.close();
  }

  @visibleForTesting
  static Future<void> debugResetForTesting() {
    return resetForRuntimeDatabaseUpdate();
  }

  static Future<void> _load() async {
    try {
      final remotePath =
          await RuntimeDatabaseUpdateService.activeDatabasePathFor(databaseId);
      if (remotePath != null) {
        final db = await openDatabase(remotePath, readOnly: true);
        try {
          await _validate(db);
          _database = db;
          _available = true;
          return;
        } catch (error) {
          await db.close();
          debugPrint('[TitleAvailabilityDb] Invalid remote DB: $error');
        }
      }

      final targetPath = await BundledDatabaseAssetService.prepare(
        assetPath: assetPath,
        databasePrefix: _databasePrefix,
        digestAssetPath: digestAssetPath,
      );
      if (targetPath == null) {
        await _useUnavailable('empty asset');
        return;
      }

      final db = await openDatabase(targetPath, readOnly: true);
      try {
        await _validate(db);
        _database = db;
        _available = true;
      } catch (_) {
        await db.close();
        final repairedPath = await BundledDatabaseAssetService.prepare(
          assetPath: assetPath,
          databasePrefix: _databasePrefix,
          digestAssetPath: digestAssetPath,
          forceRefresh: true,
        );
        if (repairedPath == null) {
          await _useUnavailable('empty asset');
          return;
        }
        final freshDb = await openDatabase(repairedPath, readOnly: true);
        await _validate(freshDb);
        _database = freshDb;
        _available = true;
      }
    } catch (error) {
      await _useUnavailable(error);
    } finally {
      _initialized = true;
      _initializeFuture = null;
    }
  }

  static Future<void> _validate(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
      "('metadata', 'title_availability', 'title_keys')",
    );
    if (rows.length < 3) {
      throw StateError('required tables are missing');
    }
    final schemaRows = await db.query(
      'metadata',
      where: 'key = ? AND value = ?',
      whereArgs: ['schemaVersion', '1'],
      limit: 1,
    );
    if (schemaRows.isEmpty) throw StateError('incompatible schema');
  }

  static Future<void> validateDatabaseFile(String path) async {
    final db = await openDatabase(path, readOnly: true);
    try {
      await _validate(db);
    } finally {
      await db.close();
    }
  }

  static Future<void> _useUnavailable(Object reason) async {
    debugPrint('[TitleAvailabilityDb] Unavailable: $reason');
    final db = _database;
    _database = null;
    _available = false;
    await db?.close();
  }
}

class TitleAvailabilityDbEntry {
  final String normalizedTitle;
  final String displayTitle;
  final AnimeModeAvailability modes;
  final String? unmatchedReason;
  final String? bestCandidatesJson;

  const TitleAvailabilityDbEntry({
    required this.normalizedTitle,
    required this.displayTitle,
    required this.modes,
    this.unmatchedReason,
    this.bestCandidatesJson,
  });

  factory TitleAvailabilityDbEntry.fromMap(Map<String, Object?> map) {
    return TitleAvailabilityDbEntry(
      normalizedTitle: map['normalizedTitle']?.toString() ?? '',
      displayTitle: map['displayTitle']?.toString() ?? '',
      modes: AnimeModeAvailability(
        hasSub: map['hasSub'] == 1,
        hasDub: map['hasDub'] == 1,
      ),
      unmatchedReason: _nullableString(map['unmatchedReason']),
      bestCandidatesJson: _nullableString(map['bestCandidatesJson']),
    );
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
