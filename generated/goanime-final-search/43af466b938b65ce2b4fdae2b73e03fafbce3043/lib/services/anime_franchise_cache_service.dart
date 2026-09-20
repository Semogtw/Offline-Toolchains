import 'package:goanime_core/goanime_core.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/anime_franchise_models.dart';
import 'app_log_service.dart';

class AnimeFranchiseCacheService {
  static const String databaseName = 'anime_franchise_cache.db';
  static const String cacheTableName = 'anime_franchise_cache';
  static const String indexTableName = 'anime_franchise_index';
  static const int databaseVersion = 1;
  static const Duration expiredRetention = Duration(days: 30);
  static const Duration _maxFutureSkew = Duration(minutes: 5);
  static const int maxStoredErrorChars = 2000;
  static const String _truncatedErrorSuffix = '...<truncated>';

  static Database? _database;
  static Future<Database>? _databaseOpenFuture;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final openFuture = _databaseOpenFuture ??= _initDatabase();
    try {
      final db = await openFuture;
      _database = db;
      return db;
    } catch (_) {
      if (identical(_databaseOpenFuture, openFuture)) {
        _databaseOpenFuture = null;
      }
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, databaseName);

    return openDatabase(
      path,
      version: databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $cacheTableName (
            franchiseId TEXT PRIMARY KEY,
            canonicalMalId INTEGER NOT NULL,
            displayTitle TEXT NOT NULL,
            coverImage TEXT NOT NULL,
            bannerImage TEXT,
            payloadJson TEXT NOT NULL,
            savedAt TEXT NOT NULL,
            expiresAt TEXT NOT NULL,
            schemaVersion INTEGER NOT NULL,
            lastError TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE $indexTableName (
            malId INTEGER PRIMARY KEY,
            franchiseId TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<AnimeFranchise?> getFreshByMalId(int malId) async {
    final franchise = await getByMalId(malId);
    if (franchise == null || franchise.isExpired) return null;
    return franchise;
  }

  Future<AnimeFranchise?> getStaleByMalId(int malId) {
    return getByMalId(malId, allowExpired: true);
  }

  Future<AnimeFranchise?> getByMalId(
    int malId, {
    bool allowExpired = false,
  }) async {
    if (malId <= 0) return null;
    final franchises = await getByMalIds([malId], allowExpired: allowExpired);
    return franchises[malId];
  }

  Future<Map<int, AnimeFranchise>> getByMalIds(
    Iterable<int> malIds, {
    bool allowExpired = false,
  }) async {
    final ids = malIds.where((id) => id > 0).toSet().toList(growable: false);
    if (ids.isEmpty) return const <int, AnimeFranchise>{};

    final db = await database;
    final staleCutoff = DateTime.now().toUtc().subtract(expiredRetention);
    final parsedByFranchiseId = <String, AnimeFranchise?>{};
    final franchises = <int, AnimeFranchise>{};
    const batchSize = 400;

    for (var offset = 0; offset < ids.length; offset += batchSize) {
      final end = offset + batchSize < ids.length
          ? offset + batchSize
          : ids.length;
      final chunk = ids.sublist(offset, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      final rows = await db.rawQuery(
        'SELECT i.malId AS indexedMalId, c.* '
        'FROM $indexTableName i '
        'INNER JOIN $cacheTableName c ON c.franchiseId = i.franchiseId '
        'WHERE i.malId IN ($placeholders)',
        chunk,
      );

      for (final row in rows) {
        final malId = _asInt(row['indexedMalId']);
        final franchiseId = row['franchiseId']?.toString();
        if (malId == null || franchiseId == null || franchiseId.isEmpty) {
          continue;
        }

        final franchise = parsedByFranchiseId.putIfAbsent(
          franchiseId,
          () => _franchiseFromRow(row),
        );
        if (franchise == null) continue;
        final isExpired = franchise.isExpired;
        if (!allowExpired && isExpired) continue;
        if (allowExpired &&
            isExpired &&
            !franchise.expiresAt.toUtc().isAfter(staleCutoff)) {
          continue;
        }
        franchises[malId] = franchise.copyWith(isStale: isExpired);
      }
    }
    return franchises;
  }

  Future<AnimeFranchise?> getByFranchiseId(
    String franchiseId, {
    bool allowExpired = false,
  }) async {
    if (franchiseId.trim().isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      cacheTableName,
      where: 'franchiseId = ?',
      whereArgs: [franchiseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final franchise = _franchiseFromRow(rows.first);
    if (franchise == null) return null;

    final isExpired = franchise.isExpired;
    if (!allowExpired && isExpired) return null;
    if (allowExpired && isExpired) {
      final staleCutoff = DateTime.now().toUtc().subtract(expiredRetention);
      if (!franchise.expiresAt.toUtc().isAfter(staleCutoff)) return null;
    }
    return franchise.copyWith(isStale: isExpired);
  }

  Future<void> save(AnimeFranchise franchise) async {
    final db = await database;
    final now = DateTime.now().toUtc();
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        cacheTableName,
        columns: const ['savedAt'],
        where: 'franchiseId = ?',
        whereArgs: [franchise.franchiseId],
        limit: 1,
      );
      if (existingRows.isNotEmpty) {
        final existingSavedAt = DateTime.tryParse(
          existingRows.first['savedAt']?.toString() ?? '',
        )?.toUtc();
        if (existingSavedAt != null &&
            !existingSavedAt.isAfter(now.add(_maxFutureSkew)) &&
            existingSavedAt.isAfter(franchise.savedAt.toUtc())) {
          return;
        }
      }

      await txn.insert(cacheTableName, {
        'franchiseId': franchise.franchiseId,
        'canonicalMalId': franchise.canonicalMalId,
        'displayTitle': franchise.displayTitle,
        'coverImage': franchise.coverImage,
        'bannerImage': franchise.bannerImage,
        'payloadJson': jsonEncode(franchise.toJson()),
        'savedAt': franchise.savedAt.toUtc().toIso8601String(),
        'expiresAt': franchise.expiresAt.toUtc().toIso8601String(),
        'schemaVersion': franchise.schemaVersion,
        'lastError': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete(
        indexTableName,
        where: 'franchiseId = ?',
        whereArgs: [franchise.franchiseId],
      );
      final indexUpdatedAt = now.toIso8601String();
      for (final entry in franchise.entries) {
        await txn.insert(indexTableName, {
          'malId': entry.malId,
          'franchiseId': franchise.franchiseId,
          'updatedAt': indexUpdatedAt,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> recordError({
    required String franchiseId,
    required Object error,
  }) async {
    final db = await database;
    await db.update(
      cacheTableName,
      {'lastError': _sanitizeStoredError(error.toString())},
      where: 'franchiseId = ?',
      whereArgs: [franchiseId],
    );
  }

  AnimeFranchise? _franchiseFromRow(Map<String, Object?> row) {
    try {
      final rowSchemaVersion = _asInt(row['schemaVersion']);
      if (rowSchemaVersion != AnimeFranchise.currentSchemaVersion) return null;

      final payloadJson = row['payloadJson'];
      if (payloadJson is! String || payloadJson.isEmpty) return null;
      final franchise = AnimeFranchise.fromJson(
        jsonMap(jsonDecode(payloadJson)) ?? const {},
      );
      if (franchise.schemaVersion != AnimeFranchise.currentSchemaVersion) {
        return null;
      }
      return franchise;
    } catch (error) {
      debugPrint('[AnimeFranchiseCache] Invalid payload: $error');
      return null;
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static String _sanitizeStoredError(String error) {
    final sanitized = AppLogService.sanitize(error);
    if (sanitized.length <= maxStoredErrorChars) return sanitized;

    final prefixLength = maxStoredErrorChars - _truncatedErrorSuffix.length;
    return '${sanitized.substring(0, prefixLength)}$_truncatedErrorSuffix';
  }

  @visibleForTesting
  static Future<void> debugResetDatabase() async {
    final openFuture = _databaseOpenFuture;
    _databaseOpenFuture = null;
    final db = _database;
    _database = null;
    if (db != null) {
      await db.close();
    } else if (openFuture != null) {
      try {
        final openingDatabase = await openFuture;
        await openingDatabase.close();
      } catch (_) {
        // A failed open has no database handle to close.
      }
    }
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, databaseName);
    await deleteDatabase(path);
  }
}
