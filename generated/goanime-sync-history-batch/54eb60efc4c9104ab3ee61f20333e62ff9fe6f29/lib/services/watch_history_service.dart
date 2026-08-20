import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/history_anime.dart';
import '../models/user_anime_state.dart';
import 'user_sync_service.dart';
import 'watchlist_service.dart';

typedef WatchHistorySyncWriter = Future<void> Function(UserAnimeState state);

class WatchHistoryService {
  static Database? _database;
  static Future<Database>? _databaseOpenFuture;
  static WatchHistorySyncWriter? _debugSyncWriter;
  static const String tableName = 'watch_history';
  static const String _watchedEpisodesPrefix = 'watched_episodes_';
  static const double watchedProgressThreshold = 0.85;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final openFuture = _databaseOpenFuture ??= _initDatabase();
    try {
      final database = await openFuture;
      _database = database;
      return database;
    } catch (_) {
      if (identical(_databaseOpenFuture, openFuture)) {
        _databaseOpenFuture = null;
      }
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'watch_history.db');

    return openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            animeId TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            coverImage TEXT NOT NULL,
            watchedAt TEXT NOT NULL,
            lastEpisode TEXT NOT NULL,
            episodeNumber INTEGER,
            progress REAL,
            positionSeconds INTEGER,
            durationSeconds INTEGER,
            isDubMode INTEGER,
            updatedAt TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _addColumnIfMissing(db, 'episodeNumber INTEGER');
          await _addColumnIfMissing(db, 'progress REAL');
        }
        if (oldVersion < 3) {
          await _addColumnIfMissing(db, 'positionSeconds INTEGER');
          await _addColumnIfMissing(db, 'durationSeconds INTEGER');
          await _addColumnIfMissing(db, 'isDubMode INTEGER');
          await _addColumnIfMissing(db, 'updatedAt TEXT');
          await db.execute(
            'UPDATE $tableName SET updatedAt = watchedAt WHERE updatedAt IS NULL',
          );
        }
      },
    );
  }

  static Future<void> _addColumnIfMissing(
    Database db,
    String declaration,
  ) async {
    final columnName = declaration.split(' ').first;
    final columns = await db.rawQuery('PRAGMA table_info($tableName)');
    final exists = columns.any((column) => column['name'] == columnName);
    if (!exists) {
      await db.execute('ALTER TABLE $tableName ADD COLUMN $declaration');
    }
  }

  @visibleForTesting
  static void debugSetSyncWriterForTesting(WatchHistorySyncWriter? writer) {
    _debugSyncWriter = writer;
  }

  @visibleForTesting
  static Future<void> debugResetDatabase() async {
    _databaseOpenFuture = null;
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<bool> addToHistory(HistoryAnime anime) async {
    late final UserAnimeState syncState;
    try {
      final db = await database;
      var stored = false;
      await db.transaction((txn) async {
        final existingRows = await txn.query(
          tableName,
          where: 'animeId = ?',
          whereArgs: [anime.animeId],
          limit: 1,
        );
        final existing = existingRows.isEmpty
            ? null
            : HistoryAnime.fromMap(existingRows.first);
        if (_isOlderThanExisting(anime, existing)) {
          return;
        }
        await txn.insert(
          tableName,
          anime.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        stored = true;
      });
      if (!stored) {
        if (_isEpisodeWatchedProgress(anime.progress)) {
          await _rememberWatchedEpisode(anime.animeId, anime.episodeNumber);
        }
        return true;
      }
      if (_isEpisodeWatchedProgress(anime.progress)) {
        await _rememberWatchedEpisode(anime.animeId, anime.episodeNumber);
      }
      final watchedEpisodes = await getWatchedEpisodeNumbers(anime.animeId);
      final isSaved = await WatchlistService().isInWatchlist(anime.animeId);
      syncState = UserAnimeState.fromHistory(
        anime,
        watchedEpisodes: watchedEpisodes,
        markCurrentEpisodeWatched: _isEpisodeWatchedProgress(anime.progress),
      ).copyWith(saved: isSaved);
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to store local history (${error.runtimeType}).',
      );
      return false;
    }

    await _recordAnimeStateBestEffort(syncState);
    return true;
  }

  static bool _isOlderThanExisting(
    HistoryAnime incoming,
    HistoryAnime? existing,
  ) {
    if (existing == null) return false;
    final incomingUpdatedAt = DateTime.tryParse(
      incoming.updatedAt ?? incoming.watchedAt,
    );
    final existingUpdatedAt = DateTime.tryParse(
      existing.updatedAt ?? existing.watchedAt,
    );
    if (incomingUpdatedAt == null || existingUpdatedAt == null) {
      return false;
    }
    return incomingUpdatedAt.isBefore(existingUpdatedAt);
  }

  Future<bool> removeFromHistory(String animeId) async {
    try {
      final db = await database;
      await db.delete(tableName, where: 'animeId = ?', whereArgs: [animeId]);
      await _clearWatchedEpisodes(animeId);
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to remove local history (${error.runtimeType}).',
      );
      return false;
    }

    await _recordAnimeStateBestEffort(
      UserAnimeState.playbackTombstone(animeId),
    );
    return true;
  }

  Future<void> _recordAnimeStateBestEffort(UserAnimeState state) async {
    try {
      final writer =
          _debugSyncWriter ?? UserSyncService.instance.recordAnimeState;
      await writer(state);
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to enqueue sync (${error.runtimeType}).',
      );
    }
  }

  Future<List<HistoryAnime>> getHistory() async {
    try {
      final db = await database;
      final result = await db.query(tableName, orderBy: 'updatedAt DESC');
      return result.map(HistoryAnime.fromMap).toList();
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to read history (${error.runtimeType}).',
      );
      return [];
    }
  }

  Future<HistoryAnime?> getAnimeHistory(String animeId) async {
    try {
      final db = await database;
      final result = await db.query(
        tableName,
        where: 'animeId = ?',
        whereArgs: [animeId],
        limit: 1,
      );
      if (result.isEmpty) return null;
      return HistoryAnime.fromMap(result.first);
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to read anime history (${error.runtimeType}).',
      );
      return null;
    }
  }

  Future<Set<int>> getWatchedEpisodeNumbers(String animeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _watchedEpisodesKey(animeId);
      final values = prefs.getStringList(key) ?? const <String>[];
      final episodes = _parseWatchedEpisodeValues(values);
      final normalizedValues = _encodeWatchedEpisodeValues(episodes);
      if (!listEquals(values, normalizedValues)) {
        if (normalizedValues.isEmpty) {
          await prefs.remove(key);
        } else {
          await prefs.setStringList(key, normalizedValues);
        }
      }
      if (episodes.isNotEmpty) return episodes;

      final history = await getAnimeHistory(animeId);
      final episodeNumber = history?.episodeNumber;
      if (episodeNumber == null || episodeNumber <= 0) return {};
      if (!_isEpisodeWatchedProgress(history?.progress)) return {};

      await _rememberWatchedEpisode(animeId, episodeNumber);
      return {episodeNumber};
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to read watched episodes '
        '(${error.runtimeType}).',
      );
      return {};
    }
  }

  Future<Map<String, Set<int>>> getWatchedEpisodeNumbersForHistory(
    Iterable<HistoryAnime> history,
  ) async {
    final historyByAnimeId = <String, HistoryAnime>{
      for (final anime in history)
        if (anime.animeId.isNotEmpty) anime.animeId: anime,
    };
    if (historyByAnimeId.isEmpty) return const <String, Set<int>>{};

    try {
      final prefs = await SharedPreferences.getInstance();
      final result = <String, Set<int>>{};
      for (final entry in historyByAnimeId.entries) {
        final animeId = entry.key;
        final anime = entry.value;
        final key = _watchedEpisodesKey(animeId);
        final values = prefs.getStringList(key) ?? const <String>[];
        final episodes = _parseWatchedEpisodeValues(values);
        var normalizedValues = _encodeWatchedEpisodeValues(episodes);

        if (episodes.isEmpty) {
          final episodeNumber = anime.episodeNumber;
          if (episodeNumber != null &&
              episodeNumber > 0 &&
              _isEpisodeWatchedProgress(anime.progress)) {
            episodes.add(episodeNumber);
            normalizedValues = _encodeWatchedEpisodeValues(episodes);
          }
        }

        if (!listEquals(values, normalizedValues)) {
          if (normalizedValues.isEmpty) {
            await prefs.remove(key);
          } else {
            await prefs.setStringList(key, normalizedValues);
          }
        }
        result[animeId] = episodes;
      }
      return result;
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to read watched episodes in batch '
        '(${error.runtimeType}).',
      );
      return {for (final animeId in historyByAnimeId.keys) animeId: <int>{}};
    }
  }

  Future<List<HistoryAnime>> getContinueWatching({int limit = 10}) async {
    try {
      final db = await database;
      final result = await db.query(
        tableName,
        where: 'progress IS NULL OR progress < ?',
        whereArgs: [0.95],
        orderBy: 'updatedAt DESC',
        limit: limit,
      );
      return result.map(HistoryAnime.fromMap).toList();
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to read continue watching '
        '(${error.runtimeType}).',
      );
      return [];
    }
  }

  Future<bool> updatePlaybackProgress({
    required String animeId,
    required String title,
    required String coverImage,
    required int episodeNumber,
    required double progress,
    required int positionSeconds,
    required int durationSeconds,
    required bool isDubMode,
  }) {
    final now = DateTime.now().toIso8601String();
    return addToHistory(
      HistoryAnime(
        animeId: animeId,
        title: title,
        coverImage: coverImage,
        watchedAt: now,
        updatedAt: now,
        lastEpisode: 'Episódio $episodeNumber',
        episodeNumber: episodeNumber,
        progress: progress,
        positionSeconds: positionSeconds,
        durationSeconds: durationSeconds,
        isDubMode: isDubMode,
      ),
    );
  }

  Future<void> applySyncedState(UserAnimeState state) async {
    if (state.playbackDeletedAt != null) {
      await applySyncedDelete(state.animeId);
      return;
    }
    if (!state.hasPlayback) return;

    final db = await database;
    final syncedEpisode =
        state.episodeNumber ??
        state.watchedEpisode ??
        (state.watchedEpisodes.isEmpty ? null : state.watchedEpisodes.last);
    final anime = HistoryAnime(
      animeId: state.animeId,
      title: state.title,
      coverImage: state.coverImage,
      watchedAt: state.updatedAt.toIso8601String(),
      updatedAt: state.updatedAt.toIso8601String(),
      lastEpisode: state.lastEpisode ?? 'Episódio ${syncedEpisode ?? ''}',
      episodeNumber: syncedEpisode,
      progress: state.progress,
      positionSeconds: state.positionSeconds,
      durationSeconds: state.durationSeconds,
      isDubMode: state.isDubMode,
    );
    await db.insert(
      tableName,
      anime.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    final syncedWatchedEpisodes = [
      ...state.watchedEpisodes,
      if (_isEpisodeWatchedProgress(state.progress)) ?syncedEpisode,
    ];
    await _rememberWatchedEpisodes(state.animeId, syncedWatchedEpisodes);
  }

  Future<void> applySyncedDelete(String animeId) async {
    final db = await database;
    await db.delete(tableName, where: 'animeId = ?', whereArgs: [animeId]);
    await _clearWatchedEpisodes(animeId);
  }

  Future<bool> clearHistory() async {
    late final List<String> removedAnimeIds;
    try {
      final db = await database;
      final rows = await db.query(tableName, columns: ['animeId']);
      removedAnimeIds = rows
          .map((row) => row['animeId']?.toString() ?? '')
          .where((animeId) => animeId.isNotEmpty)
          .toList(growable: false);
      await db.delete(tableName);
      await _clearAllWatchedEpisodes();
    } catch (error) {
      debugPrint(
        '[WatchHistory] Failed to clear local history (${error.runtimeType}).',
      );
      return false;
    }

    for (final animeId in removedAnimeIds) {
      await _recordAnimeStateBestEffort(
        UserAnimeState.playbackTombstone(animeId),
      );
    }
    return true;
  }

  Future<void> _rememberWatchedEpisode(
    String animeId,
    int? episodeNumber,
  ) async {
    if (episodeNumber == null || episodeNumber <= 0) return;
    await _rememberWatchedEpisodes(animeId, [episodeNumber]);
  }

  Future<void> _rememberWatchedEpisodes(
    String animeId,
    Iterable<int> episodeNumbers,
  ) async {
    final newEpisodes = episodeNumbers
        .where((episodeNumber) => episodeNumber > 0)
        .toSet();
    if (newEpisodes.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _watchedEpisodesKey(animeId);
    final currentValues = prefs.getStringList(key) ?? const <String>[];
    final episodes = {
      ..._parseWatchedEpisodeValues(currentValues),
      ...newEpisodes,
    };
    final normalizedValues = _encodeWatchedEpisodeValues(episodes);
    if (!listEquals(currentValues, normalizedValues)) {
      await prefs.setStringList(key, normalizedValues);
    }
  }

  Future<void> _clearWatchedEpisodes(String animeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_watchedEpisodesKey(animeId));
  }

  Future<void> _clearAllWatchedEpisodes() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_watchedEpisodesPrefix))
        .toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  static Set<int> _parseWatchedEpisodeValues(Iterable<String> values) {
    return values
        .map(int.tryParse)
        .whereType<int>()
        .where((episode) => episode > 0)
        .toSet();
  }

  static List<String> _encodeWatchedEpisodeValues(Iterable<int> episodes) {
    final normalized = episodes.where((episode) => episode > 0).toSet().toList()
      ..sort();
    return normalized.map((episode) => episode.toString()).toList();
  }

  static String _watchedEpisodesKey(String animeId) {
    return '$_watchedEpisodesPrefix$animeId';
  }

  static bool _isEpisodeWatchedProgress(double? progress) {
    return progress == null || progress >= watchedProgressThreshold;
  }
}
