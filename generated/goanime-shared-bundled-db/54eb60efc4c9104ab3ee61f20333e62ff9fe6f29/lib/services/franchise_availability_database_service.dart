import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/anime_franchise_models.dart';
import 'bundled_database_asset_service.dart';
import 'runtime_database_update_service.dart';

class FranchiseAvailabilityDatabaseService {
  static const String databaseId = 'franchise_availability';
  static const String assetPath = 'assets/data/franchise_availability.db';
  static const String _databasePrefix = 'franchise_availability_asset';
  static const int _queryChunkSize = 400;

  static Database? _database;
  static Database? _fallbackDatabase;
  static Future<void>? _initializeFuture;
  static bool _initialized = false;
  static bool _available = false;

  static bool get isAvailable => _available;

  static Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializeFuture ??= _load();
  }

  static Future<String?> franchiseIdForMalId(int malId) async {
    if (malId <= 0) return null;
    await initialize();
    final db = _database;
    if (!_available || db == null) return null;

    final primary = await _franchiseIdForMalIdIn(db, malId);
    if (primary != null) return primary;

    final fallbackDb = _fallbackDatabase;
    if (fallbackDb == null) return null;
    return _franchiseIdForMalIdIn(fallbackDb, malId);
  }

  static Future<String?> _franchiseIdForMalIdIn(Database db, int malId) async {
    final rows = await db.query(
      'mal_id_index',
      columns: ['franchiseId'],
      where: 'malId = ?',
      whereArgs: [malId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final franchiseId = rows.first['franchiseId']?.toString() ?? '';
    return franchiseId.isEmpty ? null : franchiseId;
  }

  static Future<AnimeFranchise?> franchiseForMalId(int malId) async {
    if (malId <= 0) return null;
    await initialize();
    final db = _database;
    if (!_available || db == null) return null;

    final primaryFranchiseId = await _franchiseIdForMalIdIn(db, malId);
    if (primaryFranchiseId != null) {
      final primary = await _franchiseForIdIn(db, primaryFranchiseId);
      final fallbackDb = _fallbackDatabase;
      final fallback = fallbackDb == null
          ? null
          : await _fallbackFranchiseForMalId(fallbackDb, malId);
      return _preferFallbackWhenMoreComplete(
        primary: primary,
        fallback: fallback,
        malId: malId,
      );
    }

    final fallbackDb = _fallbackDatabase;
    if (fallbackDb == null) return null;
    final fallbackFranchiseId = await _franchiseIdForMalIdIn(fallbackDb, malId);
    if (fallbackFranchiseId == null) return null;
    return _franchiseForIdIn(fallbackDb, fallbackFranchiseId);
  }

  static Future<Map<int, AnimeFranchise>> franchisesForMalIds(
    Iterable<int> malIds,
  ) async {
    final requestedIds = malIds.where((malId) => malId > 0).toSet();
    if (requestedIds.isEmpty) return const <int, AnimeFranchise>{};

    await initialize();
    final db = _database;
    if (!_available || db == null) return const <int, AnimeFranchise>{};

    final primary = await _franchisesForMalIdsIn(db, requestedIds);
    final fallbackDb = _fallbackDatabase;
    if (fallbackDb == null) return primary;

    final fallback = await _franchisesForMalIdsIn(fallbackDb, requestedIds);
    final result = <int, AnimeFranchise>{};
    for (final malId in requestedIds) {
      final selected = _preferFallbackWhenMoreComplete(
        primary: primary[malId],
        fallback: fallback[malId],
        malId: malId,
      );
      if (selected != null) result[malId] = selected;
    }
    return result;
  }

  static Future<Map<int, AnimeFranchise>> _franchisesForMalIdsIn(
    Database db,
    Set<int> malIds,
  ) async {
    final franchiseIdByMalId = <int, String>{};
    for (final chunk in _chunked(malIds)) {
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'mal_id_index',
        columns: ['malId', 'franchiseId'],
        where: 'malId IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final malId = row['malId'];
        final franchiseId = row['franchiseId']?.toString() ?? '';
        if (malId is int && franchiseId.isNotEmpty) {
          franchiseIdByMalId[malId] = franchiseId;
        }
      }
    }
    if (franchiseIdByMalId.isEmpty) {
      return const <int, AnimeFranchise>{};
    }

    final franchiseById = <String, AnimeFranchise>{};
    for (final chunk in _chunked(franchiseIdByMalId.values.toSet())) {
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        'franchises',
        columns: ['franchiseId', 'payloadJson'],
        where: 'franchiseId IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in rows) {
        final franchiseId = row['franchiseId']?.toString() ?? '';
        final franchise = _decodeFranchisePayload(
          franchiseId,
          row['payloadJson'],
        );
        if (franchise != null) franchiseById[franchiseId] = franchise;
      }
    }

    final result = <int, AnimeFranchise>{};
    for (final entry in franchiseIdByMalId.entries) {
      final franchise = franchiseById[entry.value];
      if (franchise != null) result[entry.key] = franchise;
    }
    return result;
  }

  static Iterable<List<T>> _chunked<T>(Iterable<T> values) sync* {
    final items = values.toList(growable: false);
    for (var start = 0; start < items.length; start += _queryChunkSize) {
      final proposedEnd = start + _queryChunkSize;
      final end = proposedEnd < items.length ? proposedEnd : items.length;
      yield items.sublist(start, end);
    }
  }

  static Future<AnimeFranchise?> franchiseForId(String franchiseId) async {
    if (franchiseId.isEmpty) return null;
    await initialize();
    final db = _database;
    if (!_available || db == null) return null;

    final primary = await _franchiseForIdIn(db, franchiseId);
    final fallbackDb = _fallbackDatabase;
    final fallback = fallbackDb == null
        ? null
        : await _franchiseForIdIn(fallbackDb, franchiseId);
    return _preferFallbackWhenMoreComplete(
      primary: primary,
      fallback: fallback,
    );
  }

  static Future<AnimeFranchise?> _fallbackFranchiseForMalId(
    Database fallbackDb,
    int malId,
  ) async {
    final fallbackFranchiseId = await _franchiseIdForMalIdIn(fallbackDb, malId);
    if (fallbackFranchiseId == null) return null;
    return _franchiseForIdIn(fallbackDb, fallbackFranchiseId);
  }

  static AnimeFranchise? _preferFallbackWhenMoreComplete({
    required AnimeFranchise? primary,
    required AnimeFranchise? fallback,
    int? malId,
  }) {
    if (primary == null) return fallback;
    if (fallback == null) return primary;
    if (malId != null &&
        !primary.isRuntimeVisibleMalId(malId) &&
        fallback.isRuntimeVisibleMalId(malId)) {
      return fallback;
    }
    if (primary.runtimeVisibleEntries.length <= 1 &&
        fallback.runtimeVisibleEntries.length >
            primary.runtimeVisibleEntries.length) {
      return fallback;
    }
    return primary;
  }

  static Future<AnimeFranchise?> _franchiseForIdIn(
    Database db,
    String franchiseId,
  ) async {
    final rows = await db.query(
      'franchises',
      columns: ['payloadJson'],
      where: 'franchiseId = ?',
      whereArgs: [franchiseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decodeFranchisePayload(franchiseId, rows.first['payloadJson']);
  }

  static AnimeFranchise? _decodeFranchisePayload(
    String franchiseId,
    Object? rawPayload,
  ) {
    if (rawPayload is! String || rawPayload.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is! Map<String, dynamic>) return null;
      final franchise = AnimeFranchise.fromJson(decoded);
      if (franchise.franchiseId.isEmpty || franchise.entries.isEmpty) {
        return null;
      }
      return franchise;
    } catch (error) {
      debugPrint(
        '[FranchiseAvailabilityDb] Invalid franchise payload '
        '$franchiseId: $error',
      );
      return null;
    }
  }

  @visibleForTesting
  static Future<void> debugSetDatabasePathForTesting(String path) async {
    await resetForRuntimeDatabaseUpdate();
    _database = await openDatabase(path, readOnly: true);
    _available = true;
    _initialized = true;
  }

  @visibleForTesting
  static Future<void> debugSetDatabasePathsForTesting({
    required String primaryPath,
    String? fallbackPath,
  }) async {
    await resetForRuntimeDatabaseUpdate();
    _database = await openDatabase(primaryPath, readOnly: true);
    if (fallbackPath != null) {
      _fallbackDatabase = await openDatabase(fallbackPath, readOnly: true);
    }
    _available = true;
    _initialized = true;
  }

  static Future<void> resetForRuntimeDatabaseUpdate() async {
    final db = _database;
    final fallbackDb = _fallbackDatabase;
    _database = null;
    _fallbackDatabase = null;
    _available = false;
    _initialized = false;
    _initializeFuture = null;
    await db?.close();
    await fallbackDb?.close();
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
          _fallbackDatabase = await _openBundledAssetDatabase();
          _available = true;
          return;
        } catch (error) {
          await db.close();
          debugPrint('[FranchiseAvailabilityDb] Invalid remote DB: $error');
        }
      }

      _database = await _openBundledAssetDatabase();
      _available = true;
    } catch (error) {
      await _useUnavailable(error);
    } finally {
      _initialized = true;
      _initializeFuture = null;
    }
  }

  static Future<Database> _openBundledAssetDatabase() async {
    final targetPath = await BundledDatabaseAssetService.prepare(
      assetPath: assetPath,
      databasePrefix: _databasePrefix,
    );
    if (targetPath == null) throw StateError('empty asset');

    final db = await openDatabase(targetPath, readOnly: true);
    try {
      await _validate(db);
      return db;
    } catch (_) {
      await db.close();
      final repairedPath = await BundledDatabaseAssetService.prepare(
        assetPath: assetPath,
        databasePrefix: _databasePrefix,
        forceRefresh: true,
      );
      if (repairedPath == null) throw StateError('empty asset');
      final freshDb = await openDatabase(repairedPath, readOnly: true);
      await _validate(freshDb);
      return freshDb;
    }
  }

  static Future<void> _validate(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
      "('franchises', 'mal_id_index', 'latest_mainline')",
    );
    if (rows.length < 3) {
      throw StateError('required tables are missing');
    }
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM franchises'),
    );
    if (count == null || count <= 0) {
      throw StateError('franchises table is empty');
    }
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
    debugPrint('[FranchiseAvailabilityDb] Unavailable: $reason');
    final db = _database;
    _database = null;
    _available = false;
    await db?.close();
  }
}
