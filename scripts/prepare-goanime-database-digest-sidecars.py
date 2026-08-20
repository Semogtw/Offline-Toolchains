#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    newline = '\r\n' if '\r\n' in text else '\n'
    old = old.replace('\n', newline)
    new = new.replace('\n', newline)
    if text.count(old) != 1:
        raise SystemExit(f'{path}: expected exactly one target')
    path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='')


def add_digest_argument(path: Path, expected_count: int = 1) -> None:
    text = path.read_text(encoding='utf-8')
    newline = '\r\n' if '\r\n' in text else '\n'
    old = f'      databasePrefix: _databasePrefix,{newline}'
    new = (
        f'      databasePrefix: _databasePrefix,{newline}'
        f'      digestAssetPath: digestAssetPath,{newline}'
    )
    if text.count(old) != expected_count:
        raise SystemExit(
            f'{path}: expected {expected_count} bundled database prepare target(s), '
            f'found {text.count(old)}'
        )
    path.write_text(text.replace(old, new), encoding='utf-8', newline='')


def write_sidecar(database: Path) -> None:
    digest = hashlib.sha256(database.read_bytes()).hexdigest()
    Path(f'{database}.sha256').write_text(f'{digest}\n', encoding='utf-8')


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
""", encoding='utf-8')

    tool_helper = root / 'tools/database_digest_sidecar.dart'
    tool_helper.write_text("""import 'dart:io';

import 'package:crypto/crypto.dart';

Future<String> computeDatabaseSha256(String databasePath) async {
  final file = File(databasePath);
  if (!await file.exists()) {
    throw StateError('Missing database file: $databasePath');
  }
  return (await sha256.bind(file.openRead()).first).toString();
}

Future<String> writeDatabaseDigestSidecar(
  String databasePath, {
  String? digest,
}) async {
  final resolvedDigest = digest ?? await computeDatabaseSha256(databasePath);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(resolvedDigest)) {
    throw FormatException('Invalid SHA-256 digest for $databasePath');
  }

  final target = File('$databasePath.sha256');
  final staging = File('${target.path}.tmp');
  await target.parent.create(recursive: true);
  if (await staging.exists()) await staging.delete();
  await staging.writeAsString('$resolvedDigest\\n', flush: true);
  if (await target.exists()) await target.delete();
  await staging.rename(target.path);
  return resolvedDigest;
}

Future<bool> databaseDigestSidecarMatches(String databasePath) async {
  final sidecar = File('$databasePath.sha256');
  if (!await sidecar.exists()) return false;
  final expected = (await sidecar.readAsString()).trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) return false;
  return expected == await computeDatabaseSha256(databasePath);
}
""", encoding='utf-8')

    franchise = root / 'lib/services/franchise_availability_database_service.dart'
    replace_once(
        franchise,
        "  static const String assetPath = 'assets/data/franchise_availability.db';\n",
        "  static const String assetPath = 'assets/data/franchise_availability.db';\n"
        "  static const String digestAssetPath =\n"
        "      'assets/data/franchise_availability.db.sha256';\n",
    )
    add_digest_argument(franchise, expected_count=2)

    images = root / 'lib/services/anime_image_cache_service.dart'
    replace_once(
        images,
        "  static const String assetPath = 'assets/data/franchise_availability.db';\n",
        "  static const String assetPath = 'assets/data/franchise_availability.db';\n"
        "  static const String digestAssetPath =\n"
        "      'assets/data/franchise_availability.db.sha256';\n",
    )
    add_digest_argument(images, expected_count=1)

    title = root / 'lib/services/title_availability_database_service.dart'
    replace_once(
        title,
        "import 'dart:io';\n\n"
        "import 'package:crypto/crypto.dart';\n"
        "import 'package:flutter/foundation.dart';\n"
        "import 'package:flutter/services.dart';\n"
        "import 'package:goanime_core/goanime_core.dart';\n"
        "import 'package:path/path.dart' as p;\n",
        "import 'package:flutter/foundation.dart';\n"
        "import 'package:goanime_core/goanime_core.dart';\n",
    )
    replace_once(
        title,
        "import 'availability_service.dart';\n"
        "import 'runtime_database_update_service.dart';\n",
        "import 'availability_service.dart';\n"
        "import 'bundled_database_asset_service.dart';\n"
        "import 'runtime_database_update_service.dart';\n",
    )
    replace_once(
        title,
        "  static const String assetPath = 'assets/data/title_availability.db';\n",
        "  static const String assetPath = 'assets/data/title_availability.db';\n"
        "  static const String digestAssetPath =\n"
        "      'assets/data/title_availability.db.sha256';\n",
    )
    text = title.read_text(encoding='utf-8')
    start_marker = '      final data = await rootBundle.load(assetPath);'
    end_marker = '      _database = db;\n      _available = true;\n'
    if text.count(start_marker) != 1:
        raise SystemExit(f'{title}: bundled load start not found')
    start = text.index(start_marker)
    end_start = text.index(end_marker, start)
    end = end_start + len(end_marker)
    replacement = """      final targetPath = await BundledDatabaseAssetService.prepare(
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
"""
    text = text[:start] + replacement + text[end:]
    old_helper = """  static String _databaseNameForAsset(ByteData data) {
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final digest = sha256.convert(bytes).toString().substring(0, 12);
    return '${_databasePrefix}_$digest.db';
  }
"""
    if text.count(old_helper) != 1:
        raise SystemExit(f'{title}: old database name helper not found')
    title.write_text(text.replace(old_helper, '', 1), encoding='utf-8')

    pubspec = root / 'pubspec.yaml'
    replace_once(
        pubspec,
        "    - assets/data/franchise_availability.db\n"
        "    - assets/data/title_availability.db\n",
        "    - assets/data/franchise_availability.db\n"
        "    - assets/data/franchise_availability.db.sha256\n"
        "    - assets/data/title_availability.db\n"
        "    - assets/data/title_availability.db.sha256\n",
    )

    franchise_builder = root / 'tools/build_franchise_runtime_artifacts.dart'
    replace_once(
        franchise_builder,
        "import 'package:sqflite_common_ffi/sqflite_ffi.dart';\n",
        "import 'package:sqflite_common_ffi/sqflite_ffi.dart';\n\n"
        "import 'database_digest_sidecar.dart';\n",
    )
    replace_once(
        franchise_builder,
        "  } finally {\n    await db.close();\n  }\n}\n\nFuture<void> _createSchema",
        "  } finally {\n    await db.close();\n  }\n"
        "  if (!isMemory) {\n"
        "    await writeDatabaseDigestSidecar(databasePath);\n"
        "  }\n"
        "}\n\nFuture<void> _createSchema",
    )

    title_builder = root / 'tools/build_title_availability_database.dart'
    replace_once(
        title_builder,
        "import 'package:sqflite_common_ffi/sqflite_ffi.dart';\n",
        "import 'package:sqflite_common_ffi/sqflite_ffi.dart';\n\n"
        "import 'database_digest_sidecar.dart';\n",
    )
    replace_once(
        title_builder,
        "  } finally {\n    await db.close();\n  }\n}\n\nFuture<void> _createSchema",
        "  } finally {\n    await db.close();\n  }\n"
        "  if (!isMemory) {\n"
        "    await writeDatabaseDigestSidecar(databasePath);\n"
        "  }\n"
        "}\n\nFuture<void> _createSchema",
    )

    manifest = root / 'tools/build_runtime_database_manifest.dart'
    replace_once(
        manifest,
        "import 'package:goanime/models/runtime_database_manifest_models.dart';\n",
        "import 'package:goanime/models/runtime_database_manifest_models.dart';\n\n"
        "import 'database_digest_sidecar.dart';\n",
    )
    replace_once(
        manifest,
        "    final digest = sha256.convert(bytes).toString();\n"
        "    final outputName = '${input.databaseId}.db';\n",
        "    final digest = sha256.convert(bytes).toString();\n"
        "    await writeDatabaseDigestSidecar(input.path, digest: digest);\n"
        "    final outputName = '${input.databaseId}.db';\n",
    )

    service_test = root / 'test/services/bundled_database_asset_service_test.dart'
    service_test.write_text("""import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/bundled_database_asset_service.dart';

void main() {
  tearDown(BundledDatabaseAssetService.debugResetForTesting);

  test('sidecar skips loading the large database when cached copy exists', () async {
    final dir = await Directory.systemTemp.createTemp('bundled_db_sidecar_');
    addTearDown(() => dir.delete(recursive: true));
    final databaseBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
    final digest = sha256.convert(databaseBytes).toString();
    final bundle = _CountingAssetBundle({
      'fixture.db': databaseBytes,
      'fixture.db.sha256': Uint8List.fromList(utf8.encode('$digest\\n')),
    });
    final expected = File(
      '${dir.path}/fixture_${digest.substring(0, 12)}.db',
    );
    await expected.writeAsBytes([9], flush: true);

    final path = await BundledDatabaseAssetService.prepare(
      assetPath: 'fixture.db',
      digestAssetPath: 'fixture.db.sha256',
      databasePrefix: 'fixture',
      assetBundle: bundle,
      databasesPathOverride: dir.path,
    );

    expect(path, expected.path);
    expect(bundle.loads['fixture.db.sha256'], 1);
    expect(bundle.loads['fixture.db'], isNull);
  });

  test('invalid sidecar falls back to hashing and copying database asset', () async {
    final dir = await Directory.systemTemp.createTemp('bundled_db_fallback_');
    addTearDown(() => dir.delete(recursive: true));
    final databaseBytes = Uint8List.fromList([7, 8, 9]);
    final digest = sha256.convert(databaseBytes).toString();
    final bundle = _CountingAssetBundle({
      'fixture.db': databaseBytes,
      'fixture.db.sha256': Uint8List.fromList(utf8.encode('invalid\\n')),
    });

    final path = await BundledDatabaseAssetService.prepare(
      assetPath: 'fixture.db',
      digestAssetPath: 'fixture.db.sha256',
      databasePrefix: 'fixture',
      assetBundle: bundle,
      databasesPathOverride: dir.path,
    );

    expect(path, '${dir.path}/fixture_${digest.substring(0, 12)}.db');
    expect(bundle.loads['fixture.db'], 1);
    expect(await File(path!).readAsBytes(), databaseBytes);
  });
}

class _CountingAssetBundle extends CachingAssetBundle {
  _CountingAssetBundle(this.assets);

  final Map<String, Uint8List> assets;
  final Map<String, int> loads = {};

  @override
  Future<ByteData> load(String key) async {
    loads.update(key, (value) => value + 1, ifAbsent: () => 1);
    final bytes = assets[key];
    if (bytes == null) throw FlutterError('Missing asset: $key');
    return ByteData.sublistView(bytes);
  }
}
""", encoding='utf-8')

    tool_test = root / 'test/tools/database_digest_sidecar_test.dart'
    tool_test.write_text("""import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tools/database_digest_sidecar.dart';

void main() {
  test('writes and validates SHA-256 database sidecar', () async {
    final dir = await Directory.systemTemp.createTemp('database_sidecar_');
    addTearDown(() => dir.delete(recursive: true));
    final database = File('${dir.path}/fixture.db');
    final bytes = [1, 2, 3, 4, 5, 6];
    await database.writeAsBytes(bytes, flush: true);

    final digest = await writeDatabaseDigestSidecar(database.path);

    expect(digest, sha256.convert(bytes).toString());
    expect(await File('${database.path}.sha256').readAsString(), '$digest\\n');
    expect(await databaseDigestSidecarMatches(database.path), isTrue);

    await database.writeAsBytes([...bytes, 7], flush: true);
    expect(await databaseDigestSidecarMatches(database.path), isFalse);
  });
}
""", encoding='utf-8')

    for name in ('franchise_availability.db', 'title_availability.db'):
        database = root / 'assets/data' / name
        if not database.exists():
            raise SystemExit(f'Missing database asset: {database}')
        write_sidecar(database)


if __name__ == '__main__':
    main()
