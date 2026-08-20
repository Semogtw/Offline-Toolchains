import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class BundledDatabaseAssetService {
  static final Map<String, Future<String?>> _preparedPaths = {};
  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  static Future<String?> prepare({
    required String assetPath,
    required String databasePrefix,
    String? digestAssetPath,
    bool allowMissingAsset = false,
    bool forceRefresh = false,
    AssetBundle? assetBundle,
    String? databasesPathOverride,
  }) {
    final bundle = assetBundle ?? rootBundle;
    final key = [
      assetPath,
      databasePrefix,
      digestAssetPath ?? '',
      identityHashCode(bundle).toString(),
      databasesPathOverride ?? '',
    ].join('|');
    if (forceRefresh) {
      final future = _prepare(
        assetPath: assetPath,
        databasePrefix: databasePrefix,
        digestAssetPath: digestAssetPath,
        allowMissingAsset: allowMissingAsset,
        forceRefresh: true,
        bundle: bundle,
        databasesPathOverride: databasesPathOverride,
      );
      _preparedPaths[key] = future;
      return future;
    }
    return _preparedPaths.putIfAbsent(
      key,
      () => _prepare(
        assetPath: assetPath,
        databasePrefix: databasePrefix,
        digestAssetPath: digestAssetPath,
        allowMissingAsset: allowMissingAsset,
        forceRefresh: false,
        bundle: bundle,
        databasesPathOverride: databasesPathOverride,
      ),
    );
  }

  static Future<String?> _prepare({
    required String assetPath,
    required String databasePrefix,
    required String? digestAssetPath,
    required bool allowMissingAsset,
    required bool forceRefresh,
    required AssetBundle bundle,
    required String? databasesPathOverride,
  }) async {
    final databasesPath = databasesPathOverride ?? await getDatabasesPath();
    final sidecarDigest = await _readDigest(bundle, digestAssetPath);
    if (sidecarDigest != null) {
      final sidecarPath = p.join(
        databasesPath,
        '${databasePrefix}_${sidecarDigest.substring(0, 12)}.db',
      );
      if (!forceRefresh && await File(sidecarPath).exists()) {
        return sidecarPath;
      }
    }

    ByteData data;
    try {
      data = await bundle.load(assetPath);
    } on FlutterError {
      if (allowMissingAsset) return null;
      rethrow;
    }
    if (data.lengthInBytes == 0) {
      if (allowMissingAsset) return null;
      throw StateError('empty bundled database asset: $assetPath');
    }

    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final actualDigest = sha256.convert(bytes).toString();
    if (sidecarDigest != null && sidecarDigest != actualDigest) {
      debugPrint(
        '[BundledDatabaseAsset] Digest sidecar mismatch for $assetPath; '
        'using the database content digest.',
      );
    }
    final targetPath = p.join(
      databasesPath,
      '${databasePrefix}_${actualDigest.substring(0, 12)}.db',
    );
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);

    if (forceRefresh || !await targetFile.exists()) {
      final stagingFile = File('$targetPath.tmp');
      if (await stagingFile.exists()) await stagingFile.delete();
      await stagingFile.writeAsBytes(bytes, flush: true);
      if (await targetFile.exists()) await targetFile.delete();
      await stagingFile.rename(targetPath);
    }
    return targetPath;
  }

  static Future<String?> _readDigest(
    AssetBundle bundle,
    String? digestAssetPath,
  ) async {
    if (digestAssetPath == null || digestAssetPath.isEmpty) return null;
    try {
      final raw = await bundle.loadString(digestAssetPath, cache: false);
      final digest = raw.trim().toLowerCase();
      return _sha256Pattern.hasMatch(digest) ? digest : null;
    } on FlutterError {
      return null;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void debugResetForTesting() {
    _preparedPaths.clear();
  }
}
