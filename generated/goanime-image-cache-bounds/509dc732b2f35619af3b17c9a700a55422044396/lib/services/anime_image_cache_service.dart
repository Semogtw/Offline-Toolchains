// ignore_for_file: unawaited_futures
// Existing callbacks/fixtures still rely on implicit async or dynamic JSON shapes; keep new strict rules enabled elsewhere.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/anime_image_cache_models.dart';
import 'bundled_database_asset_service.dart';

class AnimeImageCacheService {
  static const String assetPath = 'assets/data/franchise_availability.db';
  static const String _databasePrefix = 'franchise_availability_asset';
  static const int _lookupCacheMaxEntries = 256;

  static final AnimeImageCacheService instance = AnimeImageCacheService._();

  AnimeImageCacheService._();

  Database? _database;
  Future<void>? _initializeFuture;
  bool _initialized = false;
  bool _available = false;

  final Map<int, AnimeImageCacheEntry> _debugAnimeImages = {};
  final Map<String, FranchiseImageCacheEntry> _debugFranchiseImages = {};
  final Map<int, Future<AnimeImageCacheEntry?>> _animeImageLookups = {};
  final Map<String, Future<FranchiseImageCacheEntry?>> _franchiseImageLookups =
      {};
  final Map<String, Future<String?>> _bestImageLookups = {};
  bool _debugOverride = false;

  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializeFuture ??= _load();
  }

  Future<AnimeImageCacheEntry?> imageForMalId(int malId) async {
    if (malId <= 0) return null;
    if (_debugOverride) return _debugAnimeImages[malId];
    return _boundedLookup(
      _animeImageLookups,
      malId,
      () => _loadImageForMalId(malId),
    );
  }

  Future<AnimeImageCacheEntry?> _loadImageForMalId(int malId) async {
    final db = await _openDatabase();
    if (db == null || !await _hasTable(db, 'anime_images')) return null;
    final rows = await db.query(
      'anime_images',
      where: 'malId = ?',
      whereArgs: [malId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AnimeImageCacheEntry.fromMap(rows.single);
  }

  Future<FranchiseImageCacheEntry?> imageForFranchiseId(
    String franchiseId,
  ) async {
    if (franchiseId.isEmpty) return null;
    if (_debugOverride) return _debugFranchiseImages[franchiseId];
    return _boundedLookup(
      _franchiseImageLookups,
      franchiseId,
      () => _loadImageForFranchiseId(franchiseId),
    );
  }

  Future<FranchiseImageCacheEntry?> _loadImageForFranchiseId(
    String franchiseId,
  ) async {
    final db = await _openDatabase();
    if (db == null || !await _hasTable(db, 'franchise_images')) return null;
    final rows = await db.query(
      'franchise_images',
      where: 'franchiseId = ?',
      whereArgs: [franchiseId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FranchiseImageCacheEntry.fromMap(rows.single);
  }

  Future<String?> bestImageUrlForAnime({
    required int malId,
    String? franchiseId,
    String? fallbackImageUrl,
    bool preferLarge = true,
  }) async {
    final key =
        '$malId|${franchiseId ?? ''}|${fallbackImageUrl ?? ''}|'
        '${preferLarge ? 1 : 0}';
    if (!_debugOverride) {
      return _boundedLookup(
        _bestImageLookups,
        key,
        () => _resolveBestImageUrlForAnime(
          malId: malId,
          franchiseId: franchiseId,
          fallbackImageUrl: fallbackImageUrl,
          preferLarge: preferLarge,
        ),
      );
    }
    return _resolveBestImageUrlForAnime(
      malId: malId,
      franchiseId: franchiseId,
      fallbackImageUrl: fallbackImageUrl,
      preferLarge: preferLarge,
    );
  }

  Future<String?> bestBannerUrlForAnime({
    required int malId,
    String? franchiseId,
    String? fallbackImageUrl,
    bool allowPosterFallback = true,
  }) async {
    final key =
        'banner|$malId|${franchiseId ?? ''}|${fallbackImageUrl ?? ''}|'
        '${allowPosterFallback ? 1 : 0}';
    if (!_debugOverride) {
      return _boundedLookup(
        _bestImageLookups,
        key,
        () => _resolveBestBannerUrlForAnime(
          malId: malId,
          franchiseId: franchiseId,
          fallbackImageUrl: fallbackImageUrl,
          allowPosterFallback: allowPosterFallback,
        ),
      );
    }
    return _resolveBestBannerUrlForAnime(
      malId: malId,
      franchiseId: franchiseId,
      fallbackImageUrl: fallbackImageUrl,
      allowPosterFallback: allowPosterFallback,
    );
  }

  Future<String?> _resolveBestImageUrlForAnime({
    required int malId,
    String? franchiseId,
    String? fallbackImageUrl,
    bool preferLarge = true,
  }) async {
    final animeImage = await imageForMalId(malId);
    if (animeImage != null) {
      final preferred = preferLarge
          ? animeImage.largeImageUrl
          : animeImage.imageUrl;
      final secondary = preferLarge
          ? animeImage.imageUrl
          : animeImage.largeImageUrl;
      final value =
          _cleanUrl(preferred) ??
          _cleanUrl(secondary) ??
          _cleanUrl(animeImage.bannerImageUrl);
      if (value != null) return value;
    }

    if (franchiseId != null && franchiseId.isNotEmpty) {
      final franchiseImage = await imageForFranchiseId(franchiseId);
      final value =
          _cleanUrl(franchiseImage?.coverImage) ??
          _cleanUrl(franchiseImage?.bannerImage);
      if (value != null) return value;
    }

    return _cleanUrl(fallbackImageUrl);
  }

  Future<String?> _resolveBestBannerUrlForAnime({
    required int malId,
    String? franchiseId,
    String? fallbackImageUrl,
    required bool allowPosterFallback,
  }) async {
    final animeImage = await imageForMalId(malId);
    final franchiseImage = franchiseId == null || franchiseId.isEmpty
        ? null
        : await imageForFranchiseId(franchiseId);

    final banner =
        _cleanUrl(animeImage?.bannerImageUrl) ??
        _cleanUrl(franchiseImage?.bannerImage);
    if (banner != null) return banner;
    if (!allowPosterFallback) return _cleanUrl(fallbackImageUrl);

    return _cleanUrl(animeImage?.largeImageUrl) ??
        _cleanUrl(animeImage?.imageUrl) ??
        _cleanUrl(franchiseImage?.coverImage) ??
        _cleanUrl(fallbackImageUrl);
  }

  Future<void> upsertAnimeImage(AnimeImageCacheEntry entry) async {
    if (entry.malId <= 0) return;
    if (_debugOverride) {
      _debugAnimeImages[entry.malId] = entry;
      return;
    }
    final db = await _openDatabase(createIfMissing: true);
    if (db == null) return;
    await _ensureImageSchema(db);
    await db.insert(
      'anime_images',
      _cleanAnimeMap(entry.toMap()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _animeImageLookups.remove(entry.malId);
    _bestImageLookups.clear();
  }

  Future<void> upsertFranchiseImage(FranchiseImageCacheEntry entry) async {
    if (entry.franchiseId.isEmpty || entry.canonicalMalId <= 0) return;
    if (_debugOverride) {
      _debugFranchiseImages[entry.franchiseId] = entry;
      return;
    }
    final db = await _openDatabase(createIfMissing: true);
    if (db == null) return;
    await _ensureImageSchema(db);
    await db.insert(
      'franchise_images',
      _cleanFranchiseMap(entry.toMap()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _franchiseImageLookups.remove(entry.franchiseId);
    _bestImageLookups.clear();
  }

  Future<T> _boundedLookup<K, T>(
    Map<K, Future<T>> cache,
    K key,
    Future<T> Function() loader,
  ) {
    final cached = cache.remove(key);
    if (cached != null) {
      cache[key] = cached;
      return cached;
    }

    final future = loader();
    cache[key] = future;
    while (cache.length > _lookupCacheMaxEntries) {
      cache.remove(cache.keys.first);
    }
    return future;
  }

  @visibleForTesting
  int get debugAnimeImageLookupCount => _animeImageLookups.length;

  @visibleForTesting
  int get debugFranchiseImageLookupCount => _franchiseImageLookups.length;

  @visibleForTesting
  int get debugBestImageLookupCount => _bestImageLookups.length;

  @visibleForTesting
  Future<void> debugSetDatabasePathForTesting(String path) async {
    await debugResetForTesting();
    _database = await openDatabase(path);
    _available = true;
    _initialized = true;
  }

  @visibleForTesting
  void debugSetEntriesForTesting({
    Iterable<AnimeImageCacheEntry> animeImages = const [],
    Iterable<FranchiseImageCacheEntry> franchiseImages = const [],
  }) {
    _debugAnimeImages
      ..clear()
      ..addEntries(animeImages.map((entry) => MapEntry(entry.malId, entry)));
    _debugFranchiseImages
      ..clear()
      ..addEntries(
        franchiseImages.map((entry) => MapEntry(entry.franchiseId, entry)),
      );
    _debugOverride = true;
    _initialized = true;
    _animeImageLookups.clear();
    _franchiseImageLookups.clear();
    _bestImageLookups.clear();
  }

  @visibleForTesting
  Future<void> debugResetForTesting() async {
    final db = _database;
    _database = null;
    _initializeFuture = null;
    _initialized = false;
    _available = false;
    _debugOverride = false;
    _debugAnimeImages.clear();
    _debugFranchiseImages.clear();
    _animeImageLookups.clear();
    _franchiseImageLookups.clear();
    _bestImageLookups.clear();
    await db?.close();
  }

  Future<Database?> _openDatabase({bool createIfMissing = false}) async {
    if (!_initialized) await initialize();
    if (_available && _database != null) return _database;
    if (!createIfMissing) return null;

    try {
      final databasesPath = await getDatabasesPath();
      final targetPath = await _targetPathForDatabaseAsset(databasesPath);
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      _database = await openDatabase(targetPath);
      _available = true;
      _initialized = true;
      await _ensureImageSchema(_database!);
      return _database;
    } catch (error) {
      debugPrint('[AnimeImageCache] unavailable: $error');
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final databasesPath = await getDatabasesPath();
      final targetPath = await _targetPathForDatabaseAsset(databasesPath);
      _database = await openDatabase(targetPath);
      _available = true;
      await _ensureImageSchema(_database!);
    } catch (error) {
      debugPrint('[AnimeImageCache] unavailable: $error');
      _available = false;
      await _database?.close();
      _database = null;
    } finally {
      _initialized = true;
      _initializeFuture = null;
    }
  }

  Future<String> _targetPathForDatabaseAsset(String databasesPath) async {
    final preparedPath = await BundledDatabaseAssetService.prepare(
      assetPath: assetPath,
      databasePrefix: _databasePrefix,
      allowMissingAsset: true,
    );
    return preparedPath ??
        p.join(databasesPath, '${_databasePrefix}_runtime.db');
  }

  Future<void> _ensureImageSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS anime_images (
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
CREATE TABLE IF NOT EXISTS franchise_images (
  franchiseId TEXT PRIMARY KEY,
  canonicalMalId INTEGER NOT NULL,
  coverImage TEXT,
  bannerImage TEXT,
  source TEXT NOT NULL DEFAULT 'franchise_cache',
  cachedAt TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_anime_images_mal_id '
      'ON anime_images(malId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_franchise_images_canonical_mal_id '
      'ON franchise_images(canonicalMalId)',
    );
  }

  Future<bool> _hasTable(Database db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tableName],
    );
    return rows.isNotEmpty;
  }

  Map<String, Object?> _cleanAnimeMap(Map<String, Object?> map) {
    return {
      ...map,
      'imageUrl': _cleanUrl(map['imageUrl']?.toString()),
      'largeImageUrl': _cleanUrl(map['largeImageUrl']?.toString()),
      'bannerImageUrl': _cleanUrl(map['bannerImageUrl']?.toString()),
    };
  }

  Map<String, Object?> _cleanFranchiseMap(Map<String, Object?> map) {
    return {
      ...map,
      'coverImage': _cleanUrl(map['coverImage']?.toString()),
      'bannerImage': _cleanUrl(map['bannerImage']?.toString()),
    };
  }

  String? _cleanUrl(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final lower = text.toLowerCase();
    if (lower.startsWith('data:') ||
        lower.contains(';base64') ||
        lower.contains('base64,')) {
      return null;
    }
    return text;
  }
}
