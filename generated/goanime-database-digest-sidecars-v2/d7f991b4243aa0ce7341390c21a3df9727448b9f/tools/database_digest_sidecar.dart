import 'dart:io';

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
  await staging.writeAsString('$resolvedDigest\n', flush: true);
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
