#!/usr/bin/env python3
from pathlib import Path
import argparse


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise SystemExit(f'{path}: expected exactly one target')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root

    helper = root / 'lib/services/bundled_database_asset_service.dart'
    helper.write_text("""import 'dart:io';

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
""", encoding='utf-8')

    franchise = root / 'lib/services/franchise_availability_database_service.dart'
    replace_once(franchise, "import 'dart:io';\n\nimport 'package:crypto/crypto.dart';\nimport 'package:flutter/foundation.dart';\nimport 'package:flutter/services.dart';\nimport 'package:path/path.dart' as p;\n", "import 'package:flutter/foundation.dart';\n")
    replace_once(franchise, "import '../models/anime_franchise_models.dart';\nimport 'runtime_database_update_service.dart';", "import '../models/anime_franchise_models.dart';\nimport 'bundled_database_asset_service.dart';\nimport 'runtime_database_update_service.dart';")
    start = franchise.read_text(encoding='utf-8')
    old = """  static Future<Database> _openBundledAssetDatabase() async {
    final data = await rootBundle.load(assetPath);
    if (data.lengthInBytes == 0) {
      throw StateError('empty asset');
    }

    final databasesPath = await getDatabasesPath();
    final targetPath = p.join(databasesPath, _databaseNameForAsset(data));
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);

    if (!await targetFile.exists()) {
      await targetFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }

    final db = await openDatabase(targetPath, readOnly: true);
    try {
      await _validate(db);
    } catch (_) {
      await db.close();
      await targetFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      final freshDb = await openDatabase(targetPath, readOnly: true);
      await _validate(freshDb);
      return freshDb;
    }
    return db;
  }
"""
    new = """  static Future<Database> _openBundledAssetDatabase() async {
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
"""
    if start.count(old) != 1:
      raise SystemExit(f'{franchise}: expected bundled open target')
    start = start.replace(old, new, 1)
    marker = """  static String _databaseNameForAsset(ByteData data) {
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final digest = sha256.convert(bytes).toString().substring(0, 12);
    return '${_databasePrefix}_$digest.db';
  }
"""
    if start.count(marker) != 1:
      raise SystemExit(f'{franchise}: expected database name helper')
    franchise.write_text(start.replace(marker, '', 1), encoding='utf-8')

    images = root / 'lib/services/anime_image_cache_service.dart'
    replace_once(images, "import 'package:crypto/crypto.dart';\nimport 'package:flutter/foundation.dart';\nimport 'package:flutter/services.dart';\n", "import 'package:flutter/foundation.dart';\n")
    replace_once(images, "import '../models/anime_image_cache_models.dart';\n", "import '../models/anime_image_cache_models.dart';\nimport 'bundled_database_asset_service.dart';\n")
    replace_once(images, """      final targetPath = await _targetPathForDatabaseAsset(databasesPath);
      final targetFile = File(targetPath);
      await targetFile.parent.create(recursive: true);
      if (!await targetFile.exists()) {
        try {
          final data = await rootBundle.load(assetPath);
          if (data.lengthInBytes > 0) {
            await targetFile.writeAsBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              flush: true,
            );
          }
        } on FlutterError {
          // Missing asset is allowed; the app keeps using fallback URLs.
        }
      }
      _database = await openDatabase(targetPath);
""", """      final targetPath = await _targetPathForDatabaseAsset(databasesPath);
      _database = await openDatabase(targetPath);
""")
    replace_once(images, """  Future<String> _targetPathForDatabaseAsset(String databasesPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      if (data.lengthInBytes > 0) {
        return p.join(databasesPath, _databaseNameForAsset(data));
      }
    } on FlutterError {
      // Missing asset is allowed; the app keeps using fallback URLs.
    }
    return p.join(databasesPath, '${_databasePrefix}_runtime.db');
  }

  String _databaseNameForAsset(ByteData data) {
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final digest = sha256.convert(bytes).toString().substring(0, 12);
    return '${_databasePrefix}_$digest.db';
  }
""", """  Future<String> _targetPathForDatabaseAsset(String databasesPath) async {
    final preparedPath = await BundledDatabaseAssetService.prepare(
      assetPath: assetPath,
      databasePrefix: _databasePrefix,
      allowMissingAsset: true,
    );
    return preparedPath ?? p.join(databasesPath, '${_databasePrefix}_runtime.db');
  }
""")


if __name__ == '__main__':
    main()
