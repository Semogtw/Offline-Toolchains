import 'dart:io';

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
    expect(await File('${database.path}.sha256').readAsString(), '$digest\n');
    expect(await databaseDigestSidecarMatches(database.path), isTrue);

    await database.writeAsBytes([...bytes, 7], flush: true);
    expect(await databaseDigestSidecarMatches(database.path), isFalse);
  });
}
