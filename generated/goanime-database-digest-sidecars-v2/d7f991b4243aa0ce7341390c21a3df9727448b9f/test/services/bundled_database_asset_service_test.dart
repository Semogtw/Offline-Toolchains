import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/bundled_database_asset_service.dart';

void main() {
  tearDown(BundledDatabaseAssetService.debugResetForTesting);

  test(
    'sidecar skips loading the large database when cached copy exists',
    () async {
      final dir = await Directory.systemTemp.createTemp('bundled_db_sidecar_');
      addTearDown(() => dir.delete(recursive: true));
      final databaseBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final digest = sha256.convert(databaseBytes).toString();
      final bundle = _CountingAssetBundle({
        'fixture.db': databaseBytes,
        'fixture.db.sha256': Uint8List.fromList(utf8.encode('$digest\n')),
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
    },
  );

  test(
    'invalid sidecar falls back to hashing and copying database asset',
    () async {
      final dir = await Directory.systemTemp.createTemp('bundled_db_fallback_');
      addTearDown(() => dir.delete(recursive: true));
      final databaseBytes = Uint8List.fromList([7, 8, 9]);
      final digest = sha256.convert(databaseBytes).toString();
      final bundle = _CountingAssetBundle({
        'fixture.db': databaseBytes,
        'fixture.db.sha256': Uint8List.fromList(utf8.encode('invalid\n')),
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
    },
  );
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
