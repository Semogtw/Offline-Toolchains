import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/franchise_availability_database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../tools/build_franchise_runtime_artifacts.dart' as builder;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    if (databaseFactoryOrNull == null) {
      databaseFactory = databaseFactoryFfi;
    }
  });

  tearDown(() async {
    await FranchiseAvailabilityDatabaseService.debugResetForTesting();
  });

  test(
    'consulta franquias por MAL IDs em lote sem duplicar resultados',
    () async {
      final dbPath = await _buildDatabase();
      await FranchiseAvailabilityDatabaseService.debugSetDatabasePathForTesting(
        dbPath,
      );

      final franchises =
          await FranchiseAvailabilityDatabaseService.franchisesForMalIds([
            2,
            1,
            2,
            0,
            -1,
            999,
          ]);

      expect(franchises.keys, containsAll(<int>[1, 2]));
      expect(franchises.length, 2);
      expect(franchises[1]?.franchiseId, 'mal_franchise_1');
      expect(franchises[2]?.franchiseId, 'mal_franchise_1');
      expect(franchises.containsKey(999), isFalse);
    },
  );
}

Future<String> _buildDatabase() async {
  final dir = await Directory.systemTemp.createTemp('franchise_db_batch_');
  addTearDown(() async {
    await FranchiseAvailabilityDatabaseService.debugResetForTesting();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });

  final input = File('${dir.path}/franchise_availability_map.json');
  final dbPath = '${dir.path}/franchise_availability.db';
  await input.writeAsString(jsonEncode(_payload()));
  final result = await builder.buildFranchiseRuntimeArtifacts(
    builder.FranchiseRuntimeArtifactOptions(
      inputPath: input.path,
      buildSqlite: false,
    ),
  );
  await builder.buildFranchiseSqliteDatabase(result.sourcePayload, dbPath);
  return dbPath;
}

Map<String, dynamic> _payload() {
  return {
    'schemaVersion': 1,
    'generatedAt': '2026-05-19T00:00:00Z',
    'franchises': [
      {
        'franchiseId': 'mal_franchise_1',
        'canonicalMalId': 1,
        'displayTitle': 'Test Franchise',
        'coverImage': '',
        'entries': [
          _entry(1, sortIndex: 0, isCanonical: true),
          _entry(2, sortIndex: 1, relationType: 'Sequel'),
        ],
        'graphNodes': [
          {'malId': 1},
          {'malId': 2},
        ],
        'graphEdges': [
          {'sourceMalId': 1, 'targetMalId': 2, 'relationType': 'Sequel'},
        ],
        'savedAt': '2026-05-19T00:00:00Z',
        'expiresAt': '2026-06-01T00:00:00Z',
        'schemaVersion': 1,
        'isStale': false,
      },
    ],
    'index': [
      {'malId': 1, 'franchiseId': 'mal_franchise_1'},
      {'malId': 2, 'franchiseId': 'mal_franchise_1'},
    ],
    'latestMainlineMalIdByFranchiseId': {'mal_franchise_1': 2},
  };
}

Map<String, dynamic> _entry(
  int malId, {
  required int sortIndex,
  String relationType = 'Self',
  bool isCanonical = false,
}) {
  return {
    'malId': malId,
    'anime': {
      'mal_id': malId,
      'title': 'Anime $malId',
      'year': 2020 + sortIndex,
      'type': 'TV',
    },
    'relationType': relationType,
    'kind': 'tv',
    'group': 'mainline',
    'isAvailable': true,
    'isMainline': true,
    'label': 'Temporada ${sortIndex + 1}',
    'sortIndex': sortIndex,
    'isCanonical': isCanonical,
  };
}
