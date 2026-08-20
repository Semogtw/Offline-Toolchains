import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/anime_metadata_cache_models.dart';
import 'anime_metadata_cache_service.dart';
import 'app_log_service.dart';

typedef AnimeMetadataBundledSeedLoader = Future<String> Function();
typedef AnimeMetadataBundledSeedDigestLoader = Future<String> Function();
typedef AnimeMetadataSeedWriter =
    Future<void> Function(
      List<AnimeMetadataCacheEntry> entries,
      String seedSource,
    );

class AnimeMetadataSeedService {
  AnimeMetadataSeedService({
    AnimeMetadataCacheService? cacheService,
    http.Client? httpClient,
    SharedPreferences? preferences,
    DateTime Function()? now,
    int? maxDecompressedBytesOverride,
    AnimeMetadataBundledSeedLoader? bundledSeedLoader,
    AnimeMetadataBundledSeedDigestLoader? bundledSeedDigestLoader,
    AnimeMetadataSeedWriter? seedWriter,
  }) : _cacheService = cacheService ?? AnimeMetadataCacheService(),
       _httpClient = httpClient ?? http.Client(),
       _preferences = preferences,
       _now = now ?? (() => DateTime.now().toUtc()),
       _maxDecompressedBytes =
           maxDecompressedBytesOverride ?? maxDecompressedBytes,
       _bundledSeedLoader =
           bundledSeedLoader ??
           (() => rootBundle.loadString(bundledSeedAssetPath)),
       _bundledSeedDigestLoader =
           bundledSeedDigestLoader ??
           (() => rootBundle.loadString(bundledSeedDigestAssetPath)),
       _seedWriter = seedWriter;

  static const String manifestUrl = String.fromEnvironment(
    'ANIME_METADATA_SEED_MANIFEST_URL',
    defaultValue: '',
  );
  static const String bundledSeedAssetPath =
      'assets/data/anime_metadata_seed.json';
  static const String bundledSeedDigestAssetPath =
      'assets/data/anime_metadata_seed.json.sha256';
  static const int maxManifestBytes = 512 * 1024;
  static const int maxCompressedBytes = 20 * 1024 * 1024;
  static const int maxDecompressedBytes = 128 * 1024 * 1024;
  static const Duration minImportInterval = Duration(hours: 24);
  static const Duration _maxFutureSkew = Duration(minutes: 5);
  static const Duration _manifestRequestTimeout = Duration(seconds: 15);
  static const Duration _manifestStreamTimeout = Duration(seconds: 15);
  static const Duration _assetRequestTimeout = Duration(seconds: 30);
  static const Duration _assetStreamTimeout = Duration(seconds: 30);
  static const String _lastImportAttemptKey =
      'anime_metadata_seed.last_import_attempt';
  static const String _bundledSeedGenerationKey =
      'anime_metadata_seed.bundled_generation';
  static const String _bundledSeedDigestKey =
      'anime_metadata_seed.bundled_digest';
  static const String _bundledSeedSentinelKey =
      'anime_metadata_seed.bundled_sentinel';
  static final RegExp _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');

  final AnimeMetadataCacheService _cacheService;
  final http.Client _httpClient;
  final SharedPreferences? _preferences;
  final DateTime Function() _now;
  final int _maxDecompressedBytes;
  final AnimeMetadataBundledSeedLoader _bundledSeedLoader;
  final AnimeMetadataBundledSeedDigestLoader _bundledSeedDigestLoader;
  final AnimeMetadataSeedWriter? _seedWriter;

  Future<AnimeMetadataSeedImportResult> importIfNeeded({
    String? manifestUrlOverride,
  }) async {
    final currentTime = _now().toUtc();
    final bundledImported = await _importBundledSeed(currentTime);
    final url = (manifestUrlOverride ?? manifestUrl).trim();

    if (url.isEmpty) {
      return bundledImported
          ? AnimeMetadataSeedImportResult.imported
          : AnimeMetadataSeedImportResult.disabled;
    }

    if (bundledImported) {
      unawaited(_importRemoteSeed(url, currentTime));
      return AnimeMetadataSeedImportResult.imported;
    }

    return _importRemoteSeed(url, currentTime);
  }

  Future<bool> _importBundledSeed(DateTime currentTime) async {
    try {
      final preferences = _preferences ?? await SharedPreferences.getInstance();
      final bundledDigest = await _readBundledSeedDigest();
      if (_seedWriter == null &&
          bundledDigest != null &&
          preferences.getString(_bundledSeedDigestKey) == bundledDigest) {
        final sentinelKey = preferences.getString(_bundledSeedSentinelKey);
        if (sentinelKey != null && sentinelKey.isNotEmpty) {
          final sentinel = await _cacheService.getByCacheKey(
            sentinelKey,
            allowExpired: true,
          );
          if (sentinel != null) return false;
        }
      }

      final payload = AnimeMetadataSeedPayload.fromJson(
        jsonDecode(await _bundledSeedLoader()),
      );
      if (!payload.isCompatible ||
          payload.entries.isEmpty ||
          payload.generatedAt.toUtc().isAfter(
            currentTime.add(_maxFutureSkew),
          ) ||
          !_hasUniqueCacheKeys(payload.entries) ||
          !_entriesMatchPublicationTime(
            payload.entries,
            payload.generatedAt.toUtc(),
          )) {
        return false;
      }

      final generation = payload.generatedAt.toUtc().toIso8601String();
      if (_seedWriter == null &&
          preferences.getString(_bundledSeedGenerationKey) == generation) {
        final sentinelKey = payload.entries.first.cacheKey;
        final sentinel = await _cacheService.getByCacheKey(
          sentinelKey,
          allowExpired: true,
        );
        if (sentinel != null) {
          if (bundledDigest != null) {
            await preferences.setString(_bundledSeedDigestKey, bundledDigest);
          }
          await preferences.setString(_bundledSeedSentinelKey, sentinelKey);
          return false;
        }
      }

      await _writeEntries(payload.entries, 'bundled-seed');
      await preferences.setString(_bundledSeedGenerationKey, generation);
      if (bundledDigest != null) {
        await preferences.setString(_bundledSeedDigestKey, bundledDigest);
      }
      await preferences.setString(
        _bundledSeedSentinelKey,
        payload.entries.first.cacheKey,
      );
      return true;
    } catch (error) {
      await AppLogService.warning(
        'anime-metadata-seed',
        'Bundled seed import failed: $error',
      );
      return false;
    }
  }

  Future<String?> _readBundledSeedDigest() async {
    try {
      final digest = (await _bundledSeedDigestLoader()).trim().toLowerCase();
      return _sha256Pattern.hasMatch(digest) ? digest : null;
    } catch (_) {
      return null;
    }
  }

  Future<AnimeMetadataSeedImportResult> _importRemoteSeed(
    String url,
    DateTime currentTime,
  ) async {
    final prefs = _preferences ?? await SharedPreferences.getInstance();
    final lastAttempt = DateTime.tryParse(
      prefs.getString(_lastImportAttemptKey) ?? '',
    )?.toUtc();
    if (lastAttempt != null) {
      final elapsed = currentTime.difference(lastAttempt);
      if (!elapsed.isNegative && elapsed < minImportInterval) {
        return AnimeMetadataSeedImportResult.skippedRecentAttempt;
      }
    }

    await prefs.setString(_lastImportAttemptKey, currentTime.toIso8601String());

    try {
      final manifestResponse = await _send(
        url,
        timeout: _manifestRequestTimeout,
      );
      if (manifestResponse.statusCode != 200) {
        await AppLogService.warning(
          'anime-metadata-seed',
          'Manifest request failed with ${manifestResponse.statusCode}',
        );
        return AnimeMetadataSeedImportResult.manifestRequestFailed;
      }

      final manifestBytes = await _readManifestBytes(manifestResponse);
      final manifest = AnimeMetadataSeedManifest.fromJson(
        jsonDecode(utf8.decode(manifestBytes)),
      );
      if (manifest == null ||
          !manifest.isCompatible ||
          manifest.generatedAt.toUtc().isAfter(
            currentTime.add(_maxFutureSkew),
          ) ||
          !_isSupportedRemoteUrl(manifest.asset.url)) {
        return AnimeMetadataSeedImportResult.incompatibleManifest;
      }
      if (!manifest.expiresAt.toUtc().isAfter(currentTime)) {
        return AnimeMetadataSeedImportResult.expiredManifest;
      }
      if (manifest.asset.sizeBytes <= 0 ||
          manifest.asset.sizeBytes > maxCompressedBytes) {
        return AnimeMetadataSeedImportResult.assetTooLarge;
      }
      if (!_sha256Pattern.hasMatch(manifest.asset.sha256)) {
        return AnimeMetadataSeedImportResult.incompatibleManifest;
      }

      final assetResponse = await _send(
        manifest.asset.url,
        timeout: _assetRequestTimeout,
      );
      if (assetResponse.statusCode != 200) {
        return AnimeMetadataSeedImportResult.assetRequestFailed;
      }

      final compressed = await _readAssetBytes(
        assetResponse,
        expectedBytes: manifest.asset.sizeBytes,
      );
      final actualSha = sha256.convert(compressed).toString();
      if (actualSha.toLowerCase() != manifest.asset.sha256.toLowerCase()) {
        return AnimeMetadataSeedImportResult.checksumMismatch;
      }

      final decodedBytes = await _decodeGzipBounded(compressed);
      final payload = AnimeMetadataSeedPayload.fromJson(
        jsonDecode(utf8.decode(decodedBytes)),
      );
      if (!payload.isCompatible ||
          payload.generatedAt.toUtc() != manifest.generatedAt.toUtc() ||
          !_hasUniqueCacheKeys(payload.entries) ||
          !_entriesMatchPublicationTime(
            payload.entries,
            manifest.generatedAt.toUtc(),
          )) {
        return AnimeMetadataSeedImportResult.incompatiblePayload;
      }
      if (payload.entries.isEmpty) {
        return AnimeMetadataSeedImportResult.emptyPayload;
      }

      await _writeEntries(
        payload.entries,
        _publicSeedSource(manifest.asset.url),
      );
      return AnimeMetadataSeedImportResult.imported;
    } on _SeedAssetTooLarge {
      return AnimeMetadataSeedImportResult.assetTooLarge;
    } on _SeedAssetSizeMismatch {
      return AnimeMetadataSeedImportResult.assetSizeMismatch;
    } on _SeedPayloadTooLarge {
      return AnimeMetadataSeedImportResult.payloadTooLarge;
    } catch (error, stack) {
      await AppLogService.error('anime-metadata-seed', error, stack);
      return AnimeMetadataSeedImportResult.failed;
    }
  }

  Future<void> _writeEntries(
    List<AnimeMetadataCacheEntry> entries,
    String seedSource,
  ) async {
    final writer = _seedWriter;
    if (writer != null) {
      await writer(entries, seedSource);
      return;
    }
    await _cacheService.upsertEntries(entries, seedSource: seedSource);
  }

  Future<http.StreamedResponse> _send(String url, {required Duration timeout}) {
    return _httpClient
        .send(http.Request('GET', Uri.parse(url)))
        .timeout(timeout);
  }

  Future<List<int>> _readManifestBytes(http.StreamedResponse response) async {
    final declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > maxManifestBytes) {
      throw const FormatException('metadata seed manifest is too large');
    }

    final bytes = BytesBuilder(copy: false);
    var totalBytes = 0;
    await for (final chunk in response.stream.timeout(_manifestStreamTimeout)) {
      totalBytes += chunk.length;
      if (totalBytes > maxManifestBytes) {
        throw const FormatException('metadata seed manifest is too large');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<List<int>> _readAssetBytes(
    http.StreamedResponse response, {
    required int expectedBytes,
  }) async {
    final declaredLength = response.contentLength;
    if (declaredLength != null) {
      if (declaredLength > maxCompressedBytes ||
          declaredLength > expectedBytes) {
        throw const _SeedAssetTooLarge();
      }
      if (declaredLength != expectedBytes) {
        throw const _SeedAssetSizeMismatch();
      }
    }

    final bytes = BytesBuilder(copy: false);
    var totalBytes = 0;
    await for (final chunk in response.stream.timeout(_assetStreamTimeout)) {
      totalBytes += chunk.length;
      if (totalBytes > maxCompressedBytes || totalBytes > expectedBytes) {
        throw const _SeedAssetTooLarge();
      }
      bytes.add(chunk);
    }
    if (totalBytes != expectedBytes) {
      throw const _SeedAssetSizeMismatch();
    }
    return bytes.takeBytes();
  }

  Future<List<int>> _decodeGzipBounded(List<int> compressed) async {
    final decoded = BytesBuilder(copy: false);
    var totalBytes = 0;
    final stream = GZipCodec().decoder.bind(Stream.value(compressed));
    await for (final chunk in stream) {
      totalBytes += chunk.length;
      if (totalBytes > _maxDecompressedBytes) {
        throw const _SeedPayloadTooLarge();
      }
      decoded.add(chunk);
    }
    return decoded.takeBytes();
  }

  static bool _hasUniqueCacheKeys(List<AnimeMetadataCacheEntry> entries) {
    final cacheKeys = <String>{};
    for (final entry in entries) {
      if (!cacheKeys.add(entry.cacheKey)) return false;
    }
    return true;
  }

  static bool _entriesMatchPublicationTime(
    List<AnimeMetadataCacheEntry> entries,
    DateTime generatedAt,
  ) {
    final latestAllowed = generatedAt.add(_maxFutureSkew);
    return entries.every(
      (entry) => !entry.updatedAt.toUtc().isAfter(latestAllowed),
    );
  }

  static bool _isSupportedRemoteUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  static String _publicSeedSource(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) {
      return 'remote-seed';
    }
    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path.isEmpty ? '/' : uri.path,
    ).toString();
  }
}

enum AnimeMetadataSeedImportResult {
  disabled,
  skippedRecentAttempt,
  manifestRequestFailed,
  incompatibleManifest,
  expiredManifest,
  assetRequestFailed,
  assetTooLarge,
  assetSizeMismatch,
  checksumMismatch,
  payloadTooLarge,
  incompatiblePayload,
  emptyPayload,
  imported,
  failed,
}

final class _SeedAssetTooLarge implements Exception {
  const _SeedAssetTooLarge();
}

final class _SeedAssetSizeMismatch implements Exception {
  const _SeedAssetSizeMismatch();
}

final class _SeedPayloadTooLarge implements Exception {
  const _SeedPayloadTooLarge();
}
