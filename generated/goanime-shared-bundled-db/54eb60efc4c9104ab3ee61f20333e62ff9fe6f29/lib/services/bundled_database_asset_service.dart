import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class BundledDatabaseAssetService {
  static final Map<String, Future<String?>> _preparedPaths = {};

  static Future<String?> prepare({
    required String assetPath,
    required String databasePrefix,
    bool allowMissingAsset = false,
    bool forceRefresh = false,
  }) {
    final key = '$assetPath|$databasePrefix';
    if (forceRefresh) {
      final future = _prepare(
        assetPath: assetPath,
        databasePrefix: databasePrefix,
        allowMissingAsset: allowMissingAsset,
        forceRefresh: true,
      );
      _preparedPaths[key] = future;
      return future;
    }
    return _preparedPaths.putIfAbsent(
      key,
      () => _prepare(
        assetPath: assetPath,
        databasePrefix: databasePrefix,
        allowMissingAsset: allowMissingAsset,
        forceRefresh: false,
      ),
    );
  }

  static Future<String?> _prepare({
    required String assetPath,
    required String databasePrefix,
    required bool allowMissingAsset,
    required bool forceRefresh,
  }) async {
    ByteData data;
    try {
      data = await rootBundle.load(assetPath);
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
    final digest = sha256.convert(bytes).toString().substring(0, 12);
    final databasesPath = await getDatabasesPath();
    final targetPath = p.join(databasesPath, '${databasePrefix}_$digest.db');
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

  @visibleForTesting
  static void debugResetForTesting() {
    _preparedPaths.clear();
  }
}
