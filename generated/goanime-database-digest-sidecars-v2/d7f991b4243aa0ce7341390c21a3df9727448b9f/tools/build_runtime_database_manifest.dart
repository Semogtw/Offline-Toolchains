import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:goanime/models/runtime_database_manifest_models.dart';

import 'database_digest_sidecar.dart';

const _defaultOutputPath =
    'dist/runtime_database_cache/runtime_database_manifest.json';
const _defaultCopyDir = 'dist/runtime_database_cache';

Future<void> main(List<String> args) async {
  final options = RuntimeDatabaseManifestOptions.fromArgs(args);
  final manifest = await buildRuntimeDatabaseManifest(options);
  await writeRuntimeDatabaseManifest(manifest, options.outputPath);
  stdout.writeln(
    'Runtime database manifest generated: ${options.outputPath} '
    '(${manifest.assets.length} asset(s)).',
  );
}

class RuntimeDatabaseManifestOptions {
  const RuntimeDatabaseManifestOptions({
    required this.outputPath,
    required this.publicBaseUrl,
    required this.assets,
    required this.copyAssets,
    required this.copyDir,
  });

  final String outputPath;
  final String publicBaseUrl;
  final List<RuntimeDatabaseInputAsset> assets;
  final bool copyAssets;
  final String copyDir;

  factory RuntimeDatabaseManifestOptions.fromArgs(List<String> args) {
    var outputPath = _defaultOutputPath;
    var publicBaseUrl = runtimeDatabasePublicBaseUrlFromEnvironment(
      Platform.environment,
    );
    final copyAssets = !args.contains('--no-copy-assets');
    var copyDir = _defaultCopyDir;
    final assets = <RuntimeDatabaseInputAsset>[
      const RuntimeDatabaseInputAsset(
        databaseId: 'franchise_availability',
        path: 'assets/data/franchise_availability.db',
        schemaVersion: 1,
        displayName: 'Franchise availability',
      ),
      const RuntimeDatabaseInputAsset(
        databaseId: 'title_availability',
        path: 'assets/data/title_availability.db',
        schemaVersion: 1,
        displayName: 'Title availability',
      ),
    ];

    for (final arg in args) {
      if (arg.startsWith('--output=')) {
        outputPath = arg.substring('--output='.length);
      } else if (arg.startsWith('--public-base-url=')) {
        publicBaseUrl = arg.substring('--public-base-url='.length);
      } else if (arg.startsWith('--copy-dir=')) {
        copyDir = arg.substring('--copy-dir='.length);
      }
    }

    return RuntimeDatabaseManifestOptions(
      outputPath: outputPath,
      publicBaseUrl: publicBaseUrl,
      assets: assets,
      copyAssets: copyAssets,
      copyDir: copyDir,
    );
  }
}

String runtimeDatabasePublicBaseUrlFromEnvironment(
  Map<String, String> environment,
) {
  final configured = environment['RUNTIME_DATABASE_PUBLIC_BASE_URL']?.trim();
  if (configured != null && configured.isNotEmpty) return configured;

  final updateManifestUrl = environment['UPDATE_MANIFEST_URL']?.trim() ?? '';
  const updateSuffix = '/update.json';
  if (updateManifestUrl.endsWith(updateSuffix)) {
    return updateManifestUrl.substring(
      0,
      updateManifestUrl.length - updateSuffix.length,
    );
  }
  return '';
}

class RuntimeDatabaseInputAsset {
  const RuntimeDatabaseInputAsset({
    required this.databaseId,
    required this.path,
    required this.schemaVersion,
    required this.displayName,
  });

  final String databaseId;
  final String path;
  final int schemaVersion;
  final String displayName;
}

Future<RuntimeDatabaseManifest> buildRuntimeDatabaseManifest(
  RuntimeDatabaseManifestOptions options,
) async {
  final baseUrl = options.publicBaseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final outputDir = Directory(options.copyDir);
  if (options.copyAssets) await outputDir.create(recursive: true);

  final assets = <RuntimeDatabaseAsset>[];
  for (final input in options.assets) {
    final source = File(input.path);
    if (!await source.exists()) {
      throw StateError('Missing runtime database asset: ${input.path}');
    }
    final bytes = await source.readAsBytes();
    final digest = sha256.convert(bytes).toString();
    await writeDatabaseDigestSidecar(input.path, digest: digest);
    final outputName = '${input.databaseId}.db';
    if (options.copyAssets) {
      await File(
        '${outputDir.path}/$outputName',
      ).writeAsBytes(bytes, flush: true);
    }
    assets.add(
      RuntimeDatabaseAsset(
        databaseId: input.databaseId,
        displayName: input.displayName,
        url: baseUrl.isEmpty ? outputName : '$baseUrl/$outputName',
        sha256: digest,
        sizeBytes: bytes.length,
        schemaVersion: input.schemaVersion,
      ),
    );
  }

  return RuntimeDatabaseManifest(
    schemaVersion: RuntimeDatabaseManifest.currentSchemaVersion,
    generatedAt: DateTime.now().toUtc(),
    assets: assets,
  );
}

Future<void> writeRuntimeDatabaseManifest(
  RuntimeDatabaseManifest manifest,
  String outputPath,
) async {
  final file = File(outputPath);
  await file.parent.create(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  final content = '${encoder.convert(manifest.toJson())}\n';
  RuntimeDatabaseManifest.fromJson(jsonDecode(content));
  await file.writeAsString(content, flush: true);
}
