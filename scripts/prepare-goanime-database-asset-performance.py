#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def read_text(path: Path) -> str:
    with path.open("r", encoding="utf-8", newline="") as stream:
        return stream.read()


def write_text(path: Path, text: str) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        stream.write(text)


def replace_once(path: Path, old: str, new: str) -> None:
    text = read_text(path)
    newline = "\r\n" if "\r\n" in text else "\n"
    old = old.replace("\n", newline)
    new = new.replace("\n", newline)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one replacement target, found {count}")
    write_text(path, text.replace(old, new, 1))


def create_exact(path: Path, content: str) -> None:
    if path.exists():
        current = read_text(path).replace("\r\n", "\n")
        if current == content:
            return
        raise SystemExit(f"{path}: refusing to overwrite unexpected existing file")
    path.parent.mkdir(parents=True, exist_ok=True)
    write_text(path, content)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def apply(root: Path) -> None:
    helper = root / "lib/services/bundled_database_asset_service.dart"
    create_exact(
        helper,
        (
            "import 'dart:io';\n"
            "\n"
            "import 'package:crypto/crypto.dart';\n"
            "import 'package:flutter/foundation.dart';\n"
            "import 'package:flutter/services.dart';\n"
            "import 'package:path/path.dart' as p;\n"
            "import 'package:sqflite/sqflite.dart';\n"
            "\n"
            "class BundledDatabaseAssetCopy {\n"
            "  static final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}\\$');\n"
            "\n"
            "  final String assetPath;\n"
            "  final String databasePrefix;\n"
            "  final String digest;\n"
            "  final File file;\n"
            "  final AssetBundle _assetBundle;\n"
            "\n"
            "  BundledDatabaseAssetCopy._({\n"
            "    required this.assetPath,\n"
            "    required this.databasePrefix,\n"
            "    required this.digest,\n"
            "    required this.file,\n"
            "    required AssetBundle assetBundle,\n"
            "  }) : _assetBundle = assetBundle;\n"
            "\n"
            "  static Future<BundledDatabaseAssetCopy> prepare({\n"
            "    required String assetPath,\n"
            "    required String databasePrefix,\n"
            "    AssetBundle? assetBundle,\n"
            "    String? databaseDirectory,\n"
            "  }) async {\n"
            "    final bundle = assetBundle ?? rootBundle;\n"
            "    final digest = (await bundle.loadString('\\$assetPath.sha256'))\n"
            "        .trim()\n"
            "        .toLowerCase();\n"
            "    if (!_sha256Pattern.hasMatch(digest)) {\n"
            "      throw FormatException('Invalid bundled database SHA-256: \\$assetPath');\n"
            "    }\n"
            "\n"
            "    final databasesPath = databaseDirectory ?? await getDatabasesPath();\n"
            "    final targetFile = File(\n"
            "      p.join(\n"
            "        databasesPath,\n"
            "        '\\${databasePrefix}_\\${digest.substring(0, 12)}.db',\n"
            "      ),\n"
            "    );\n"
            "    final copy = BundledDatabaseAssetCopy._(\n"
            "      assetPath: assetPath,\n"
            "      databasePrefix: databasePrefix,\n"
            "      digest: digest,\n"
            "      file: targetFile,\n"
            "      assetBundle: bundle,\n"
            "    );\n"
            "    await targetFile.parent.create(recursive: true);\n"
            "    if (!await targetFile.exists()) {\n"
            "      await copy.restore();\n"
            "    }\n"
            "    return copy;\n"
            "  }\n"
            "\n"
            "  Future<void> restore() async {\n"
            "    final data = await _assetBundle.load(assetPath);\n"
            "    if (data.lengthInBytes == 0) {\n"
            "      throw StateError('empty bundled database asset: \\$assetPath');\n"
            "    }\n"
            "    final bytes = data.buffer.asUint8List(\n"
            "      data.offsetInBytes,\n"
            "      data.lengthInBytes,\n"
            "    );\n"
            "    final actualDigest = sha256.convert(bytes).toString();\n"
            "    if (actualDigest != digest) {\n"
            "      throw StateError('bundled database digest mismatch: \\$assetPath');\n"
            "    }\n"
            "\n"
            "    final tempFile = File('\\${file.path}.tmp');\n"
            "    await tempFile.writeAsBytes(bytes, flush: true);\n"
            "    if (await file.exists()) await file.delete();\n"
            "    await tempFile.rename(file.path);\n"
            "  }\n"
            "\n"
            "  Future<void> cleanupStaleCopies() async {\n"
            "    if (!await file.parent.exists()) return;\n"
            "    await for (final entity in file.parent.list(followLinks: false)) {\n"
            "      if (entity is! File || entity.path == file.path) continue;\n"
            "      final name = p.basename(entity.path);\n"
            "      if (!name.startsWith('\\${databasePrefix}_') ||\n"
            "          !name.endsWith('.db')) {\n"
            "        continue;\n"
            "      }\n"
            "      try {\n"
            "        await entity.delete();\n"
            "      } on FileSystemException catch (error) {\n"
            "        debugPrint('[BundledDatabaseAsset] Stale copy cleanup failed: \\$error');\n"
            "      }\n"
            "    }\n"
            "  }\n"
            "}\n"
        ),
    )

    title = root / "lib/services/title_availability_database_service.dart"
    replace_once(
        title,
        (
            "import 'dart:io';\n"
            "\n"
            "import 'package:crypto/crypto.dart';\n"
            "import 'package:flutter/foundation.dart';\n"
            "import 'package:flutter/services.dart';\n"
            "import 'package:goanime_core/goanime_core.dart';\n"
            "import 'package:path/path.dart' as p;\n"
            "import 'package:sqflite/sqflite.dart';\n"
            "\n"
            "import 'availability_service.dart';\n"
            "import 'runtime_database_update_service.dart';"
        ),
        (
            "import 'package:flutter/foundation.dart';\n"
            "import 'package:goanime_core/goanime_core.dart';\n"
            "import 'package:sqflite/sqflite.dart';\n"
            "\n"
            "import 'availability_service.dart';\n"
            "import 'bundled_database_asset_service.dart';\n"
            "import 'runtime_database_update_service.dart';"
        ),
    )
    replace_once(
        title,
        (
            "      final data = await rootBundle.load(assetPath);\n"
            "      if (data.lengthInBytes == 0) {\n"
            "        await _useUnavailable('empty asset');\n"
            "        return;\n"
            "      }\n"
            "\n"
            "      final databasesPath = await getDatabasesPath();\n"
            "      final targetPath = p.join(databasesPath, _databaseNameForAsset(data));\n"
            "      final targetFile = File(targetPath);\n"
            "      await targetFile.parent.create(recursive: true);\n"
            "\n"
            "      if (!await targetFile.exists()) {\n"
            "        await targetFile.writeAsBytes(\n"
            "          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),\n"
            "          flush: true,\n"
            "        );\n"
            "      }\n"
            "\n"
            "      final db = await openDatabase(targetPath, readOnly: true);\n"
            "      try {\n"
            "        await _validate(db);\n"
            "      } catch (_) {\n"
            "        await db.close();\n"
            "        await targetFile.writeAsBytes(\n"
            "          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),\n"
            "          flush: true,\n"
            "        );\n"
            "        final freshDb = await openDatabase(targetPath, readOnly: true);\n"
            "        await _validate(freshDb);\n"
            "        _database = freshDb;\n"
            "        _available = true;\n"
            "        return;\n"
            "      }\n"
            "      _database = db;\n"
            "      _available = true;"
        ),
        (
            "      final bundledCopy = await BundledDatabaseAssetCopy.prepare(\n"
            "        assetPath: assetPath,\n"
            "        databasePrefix: _databasePrefix,\n"
            "      );\n"
            "      final targetPath = bundledCopy.file.path;\n"
            "      var db = await openDatabase(targetPath, readOnly: true);\n"
            "      try {\n"
            "        await _validate(db);\n"
            "      } catch (_) {\n"
            "        await db.close();\n"
            "        await bundledCopy.restore();\n"
            "        db = await openDatabase(targetPath, readOnly: true);\n"
            "        await _validate(db);\n"
            "      }\n"
            "      await bundledCopy.cleanupStaleCopies();\n"
            "      _database = db;\n"
            "      _available = true;"
        ),
    )
    old_title_tail = (
        "\n  static String _databaseNameForAsset(ByteData data) {\n"
        "    final bytes = data.buffer.asUint8List(\n"
        "      data.offsetInBytes,\n"
        "      data.lengthInBytes,\n"
        "    );\n"
        "    final digest = sha256.convert(bytes).toString().substring(0, 12);\n"
        "    return '\\${_databasePrefix}_\\$digest.db';\n"
        "  }\n"
    )
    replace_once(title, old_title_tail, "\n")

    franchise = root / "lib/services/franchise_availability_database_service.dart"
    replace_once(
        franchise,
        (
            "import 'dart:convert';\n"
            "import 'dart:io';\n"
            "\n"
            "import 'package:crypto/crypto.dart';\n"
            "import 'package:flutter/foundation.dart';\n"
            "import 'package:flutter/services.dart';\n"
            "import 'package:path/path.dart' as p;\n"
            "import 'package:sqflite/sqflite.dart';\n"
            "\n"
            "import '../models/anime_franchise_models.dart';\n"
            "import 'runtime_database_update_service.dart';"
        ),
        (
            "import 'dart:convert';\n"
            "\n"
            "import 'package:flutter/foundation.dart';\n"
            "import 'package:sqflite/sqflite.dart';\n"
            "\n"
            "import '../models/anime_franchise_models.dart';\n"
            "import 'bundled_database_asset_service.dart';\n"
            "import 'runtime_database_update_service.dart';"
        ),
    )
    replace_once(
        franchise,
        (
            "  static Future<Database> _openBundledAssetDatabase() async {\n"
            "    final data = await rootBundle.load(assetPath);\n"
            "    if (data.lengthInBytes == 0) {\n"
            "      throw StateError('empty asset');\n"
            "    }\n"
            "\n"
            "    final databasesPath = await getDatabasesPath();\n"
            "    final targetPath = p.join(databasesPath, _databaseNameForAsset(data));\n"
            "    final targetFile = File(targetPath);\n"
            "    await targetFile.parent.create(recursive: true);\n"
            "\n"
            "    if (!await targetFile.exists()) {\n"
            "      await targetFile.writeAsBytes(\n"
            "        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),\n"
            "        flush: true,\n"
            "      );\n"
            "    }\n"
            "\n"
            "    final db = await openDatabase(targetPath, readOnly: true);\n"
            "    try {\n"
            "      await _validate(db);\n"
            "    } catch (_) {\n"
            "      await db.close();\n"
            "      await targetFile.writeAsBytes(\n"
            "        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),\n"
            "        flush: true,\n"
            "      );\n"
            "      final freshDb = await openDatabase(targetPath, readOnly: true);\n"
            "      await _validate(freshDb);\n"
            "      return freshDb;\n"
            "    }\n"
            "    return db;\n"
            "  }"
        ),
        (
            "  static Future<Database> _openBundledAssetDatabase() async {\n"
            "    final bundledCopy = await BundledDatabaseAssetCopy.prepare(\n"
            "      assetPath: assetPath,\n"
            "      databasePrefix: _databasePrefix,\n"
            "    );\n"
            "    final targetPath = bundledCopy.file.path;\n"
            "    var db = await openDatabase(targetPath, readOnly: true);\n"
            "    try {\n"
            "      await _validate(db);\n"
            "    } catch (_) {\n"
            "      await db.close();\n"
            "      await bundledCopy.restore();\n"
            "      db = await openDatabase(targetPath, readOnly: true);\n"
            "      await _validate(db);\n"
            "    }\n"
            "    await bundledCopy.cleanupStaleCopies();\n"
            "    return db;\n"
            "  }"
        ),
    )
    old_franchise_tail = (
        "\n  static String _databaseNameForAsset(ByteData data) {\n"
        "    final bytes = data.buffer.asUint8List(\n"
        "      data.offsetInBytes,\n"
        "      data.lengthInBytes,\n"
        "    );\n"
        "    final digest = sha256.convert(bytes).toString().substring(0, 12);\n"
        "    return '\\${_databasePrefix}_\\$digest.db';\n"
        "  }\n"
    )
    replace_once(franchise, old_franchise_tail, "\n")

    digest_tool = root / "tools/runtime_asset_digest.dart"
    create_exact(
        digest_tool,
        (
            "import 'dart:io';\n"
            "\n"
            "import 'package:crypto/crypto.dart';\n"
            "\n"
            "Future<String> writeRuntimeAssetDigest(String databasePath) async {\n"
            "  final database = File(databasePath);\n"
            "  if (!await database.exists()) {\n"
            "    throw StateError('Runtime database does not exist: \\$databasePath');\n"
            "  }\n"
            "  final digest = (await sha256.bind(database.openRead()).first).toString();\n"
            "  await File('\\$databasePath.sha256').writeAsString(\n"
            "    '\\$digest\\n',\n"
            "    flush: true,\n"
            "  );\n"
            "  return digest;\n"
            "}\n"
        ),
    )

    franchise_tool = root / "tools/build_franchise_runtime_artifacts.dart"
    replace_once(
        franchise_tool,
        "import 'package:sqflite_common_ffi/sqflite_ffi.dart';",
        (
            "import 'package:sqflite_common_ffi/sqflite_ffi.dart';\n"
            "\n"
            "import 'runtime_asset_digest.dart';"
        ),
    )
    replace_once(
        franchise_tool,
        (
            "  } finally {\n"
            "    await db.close();\n"
            "  }\n"
            "}\n"
            "\n"
            "Future<void> _createSchema(Database db) async {"
        ),
        (
            "  } finally {\n"
            "    await db.close();\n"
            "  }\n"
            "  if (!isMemory) {\n"
            "    await writeRuntimeAssetDigest(databasePath);\n"
            "  }\n"
            "}\n"
            "\n"
            "Future<void> _createSchema(Database db) async {"
        ),
    )

    title_tool = root / "tools/build_title_availability_database.dart"
    replace_once(
        title_tool,
        "import 'package:sqflite_common_ffi/sqflite_ffi.dart';",
        (
            "import 'package:sqflite_common_ffi/sqflite_ffi.dart';\n"
            "\n"
            "import 'runtime_asset_digest.dart';"
        ),
    )
    replace_once(
        title_tool,
        (
            "  } finally {\n"
            "    await db.close();\n"
            "  }\n"
            "}\n"
            "\n"
            "Future<void> _createSchema(Database db) async {"
        ),
        (
            "  } finally {\n"
            "    await db.close();\n"
            "  }\n"
            "  if (!isMemory) {\n"
            "    await writeRuntimeAssetDigest(databasePath);\n"
            "  }\n"
            "}\n"
            "\n"
            "Future<void> _createSchema(Database db) async {"
        ),
    )

    pubspec = root / "pubspec.yaml"
    replace_once(
        pubspec,
        (
            "    - assets/data/franchise_availability.db\n"
            "    - assets/data/title_availability.db"
        ),
        (
            "    - assets/data/franchise_availability.db\n"
            "    - assets/data/franchise_availability.db.sha256\n"
            "    - assets/data/title_availability.db\n"
            "    - assets/data/title_availability.db.sha256"
        ),
    )

    franchise_test = root / "test/tools/build_franchise_runtime_artifacts_test.dart"
    replace_once(
        franchise_test,
        "import 'package:flutter_test/flutter_test.dart';",
        (
            "import 'package:crypto/crypto.dart';\n"
            "import 'package:flutter_test/flutter_test.dart';"
        ),
    )
    replace_once(
        franchise_test,
        "      await builder.buildFranchiseSqliteDatabase(result.sourcePayload, dbPath);",
        (
            "      await builder.buildFranchiseSqliteDatabase(result.sourcePayload, dbPath);\n"
            "\n"
            "      final digestFile = File('\\$dbPath.sha256');\n"
            "      expect(await digestFile.exists(), isTrue);\n"
            "      expect(\n"
            "        (await digestFile.readAsString()).trim(),\n"
            "        sha256.convert(await File(dbPath).readAsBytes()).toString(),\n"
            "      );"
        ),
    )

    title_test = root / "test/tools/build_title_availability_database_test.dart"
    replace_once(
        title_test,
        "import 'package:flutter_test/flutter_test.dart';",
        (
            "import 'package:crypto/crypto.dart';\n"
            "import 'package:flutter_test/flutter_test.dart';"
        ),
    )
    replace_once(
        title_test,
        "    await builder.buildTitleAvailabilityDatabase(payload, outputPath);",
        (
            "    await builder.buildTitleAvailabilityDatabase(payload, outputPath);\n"
            "\n"
            "    final digestFile = File('\\$outputPath.sha256');\n"
            "    expect(await digestFile.exists(), isTrue);\n"
            "    expect(\n"
            "      (await digestFile.readAsString()).trim(),\n"
            "      sha256.convert(await File(outputPath).readAsBytes()).toString(),\n"
            "    );"
        ),
    )

    helper_test = root / "test/services/bundled_database_asset_service_test.dart"
    create_exact(
        helper_test,
        (
            "import 'dart:convert';\n"
            "import 'dart:io';\n"
            "import 'dart:typed_data';\n"
            "\n"
            "import 'package:crypto/crypto.dart';\n"
            "import 'package:flutter/services.dart';\n"
            "import 'package:flutter_test/flutter_test.dart';\n"
            "import 'package:goanime/services/bundled_database_asset_service.dart';\n"
            "\n"
            "void main() {\n"
            "  test('reuses existing hashed database without loading the large asset', () async {\n"
            "    final directory = await Directory.systemTemp.createTemp('bundled_db_asset_');\n"
            "    addTearDown(() => directory.delete(recursive: true));\n"
            "    final bytes = Uint8List.fromList(utf8.encode('database payload'));\n"
            "    final digest = sha256.convert(bytes).toString();\n"
            "    final bundle = _CountingAssetBundle(\n"
            "      assetPath: 'assets/data/test.db',\n"
            "      digest: digest,\n"
            "      databaseBytes: bytes,\n"
            "    );\n"
            "    final existing = File(\n"
            "      '\\${directory.path}/test_asset_\\${digest.substring(0, 12)}.db',\n"
            "    );\n"
            "    await existing.writeAsBytes(bytes);\n"
            "\n"
            "    final copy = await BundledDatabaseAssetCopy.prepare(\n"
            "      assetPath: 'assets/data/test.db',\n"
            "      databasePrefix: 'test_asset',\n"
            "      assetBundle: bundle,\n"
            "      databaseDirectory: directory.path,\n"
            "    );\n"
            "\n"
            "    expect(copy.file.path, existing.path);\n"
            "    expect(bundle.databaseLoads, 0);\n"
            "  });\n"
            "\n"
            "  test('loads and verifies the database only when the copy is missing', () async {\n"
            "    final directory = await Directory.systemTemp.createTemp('bundled_db_asset_');\n"
            "    addTearDown(() => directory.delete(recursive: true));\n"
            "    final bytes = Uint8List.fromList(utf8.encode('database payload'));\n"
            "    final digest = sha256.convert(bytes).toString();\n"
            "    final bundle = _CountingAssetBundle(\n"
            "      assetPath: 'assets/data/test.db',\n"
            "      digest: digest,\n"
            "      databaseBytes: bytes,\n"
            "    );\n"
            "\n"
            "    final copy = await BundledDatabaseAssetCopy.prepare(\n"
            "      assetPath: 'assets/data/test.db',\n"
            "      databasePrefix: 'test_asset',\n"
            "      assetBundle: bundle,\n"
            "      databaseDirectory: directory.path,\n"
            "    );\n"
            "\n"
            "    expect(bundle.databaseLoads, 1);\n"
            "    expect(await copy.file.readAsBytes(), bytes);\n"
            "  });\n"
            "\n"
            "  test('removes stale hash-named copies after the current copy is ready', () async {\n"
            "    final directory = await Directory.systemTemp.createTemp('bundled_db_asset_');\n"
            "    addTearDown(() => directory.delete(recursive: true));\n"
            "    final bytes = Uint8List.fromList(utf8.encode('database payload'));\n"
            "    final digest = sha256.convert(bytes).toString();\n"
            "    final bundle = _CountingAssetBundle(\n"
            "      assetPath: 'assets/data/test.db',\n"
            "      digest: digest,\n"
            "      databaseBytes: bytes,\n"
            "    );\n"
            "    final stale = File('\\${directory.path}/test_asset_deadbeefdead.db');\n"
            "    await stale.writeAsBytes(const [1, 2, 3]);\n"
            "\n"
            "    final copy = await BundledDatabaseAssetCopy.prepare(\n"
            "      assetPath: 'assets/data/test.db',\n"
            "      databasePrefix: 'test_asset',\n"
            "      assetBundle: bundle,\n"
            "      databaseDirectory: directory.path,\n"
            "    );\n"
            "    await copy.cleanupStaleCopies();\n"
            "\n"
            "    expect(await copy.file.exists(), isTrue);\n"
            "    expect(await stale.exists(), isFalse);\n"
            "  });\n"
            "}\n"
            "\n"
            "class _CountingAssetBundle extends CachingAssetBundle {\n"
            "  final String assetPath;\n"
            "  final String digest;\n"
            "  final Uint8List databaseBytes;\n"
            "  int databaseLoads = 0;\n"
            "\n"
            "  _CountingAssetBundle({\n"
            "    required this.assetPath,\n"
            "    required this.digest,\n"
            "    required this.databaseBytes,\n"
            "  });\n"
            "\n"
            "  @override\n"
            "  Future<ByteData> load(String key) async {\n"
            "    if (key == assetPath) {\n"
            "      databaseLoads++;\n"
            "      return ByteData.sublistView(databaseBytes);\n"
            "    }\n"
            "    if (key == '\\$assetPath.sha256') {\n"
            "      return ByteData.sublistView(\n"
            "        Uint8List.fromList(utf8.encode('\\$digest\\n')),\n"
            "      );\n"
            "    }\n"
            "    throw FlutterError('Unexpected asset: \\$key');\n"
            "  }\n"
            "}\n"
        ),
    )

    for relative in (
        "assets/data/franchise_availability.db",
        "assets/data/title_availability.db",
    ):
        database = root / relative
        digest_path = root / f"{relative}.sha256"
        create_exact(digest_path, f"{sha256_file(database)}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    apply(args.root.resolve())


if __name__ == "__main__":
    main()
