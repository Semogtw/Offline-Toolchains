import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../../firebase_sync_client.dart';
import 'manga_sync_record.dart';

final class MangaFirebaseSyncClient {
  MangaFirebaseSyncClient({
    FirebaseSyncConfig config = FirebaseSyncConfig.fromEnvironment,
    http.Client? httpClient,
  }) : _config = config,
       _httpClient = httpClient ?? http.Client();

  final FirebaseSyncConfig _config;
  final http.Client _httpClient;

  bool get isConfigured => _config.isConfigured;

  Future<void> saveRecord({
    required FirebaseAccountSession session,
    required MangaSyncRecord record,
  }) async {
    if (!isConfigured || session.uid.isEmpty || session.idToken.isEmpty) {
      return;
    }

    final response = await _httpClient.patch(
      _documentUri(session.uid, _documentId(record.recordKey)),
      headers: _headers(session),
      body: jsonEncode(<String, dynamic>{
        'fields': <String, dynamic>{
          'recordKey': _stringValue(record.recordKey),
          'kind': _stringValue(record.kind.name),
          'workId': _nullableStringValue(record.workId),
          'canonicalChapterId': _nullableStringValue(record.canonicalChapterId),
          'updatedAt': _stringValue(record.updatedAt.toIso8601String()),
          'tombstone': <String, dynamic>{'booleanValue': record.tombstone},
          // Keep the domain payload as JSON text. The generic Firebase client
          // intentionally only handles scalar/array values, and keeping this
          // opaque prevents Manga metadata from widening Anime's wire contract.
          'payloadJson': _stringValue(jsonEncode(record.payload)),
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirebaseSyncException(
        'Firestore Manga sync failed.',
        authExpired: _isAuthError(response.statusCode),
      );
    }
  }

  Future<List<MangaSyncRecord>> fetchRecords({
    required FirebaseAccountSession session,
  }) async {
    if (!isConfigured || session.uid.isEmpty || session.idToken.isEmpty) {
      return const <MangaSyncRecord>[];
    }

    final response = await _httpClient.get(
      _collectionUri(session.uid),
      headers: _headers(session),
    );
    if (response.statusCode == 404) return const <MangaSyncRecord>[];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirebaseSyncException(
        'Firestore Manga fetch failed.',
        authExpired: _isAuthError(response.statusCode),
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const <MangaSyncRecord>[];
    final documents = decoded['documents'];
    if (documents is! List) return const <MangaSyncRecord>[];

    final records = <MangaSyncRecord>[];
    for (final document in documents.whereType<Map>()) {
      final fields = document['fields'];
      if (fields is! Map) continue;
      final record = _recordFromFields(Map<String, dynamic>.from(fields));
      if (record != null) records.add(record);
    }
    return List<MangaSyncRecord>.unmodifiable(records);
  }

  MangaSyncRecord? _recordFromFields(Map<String, dynamic> fields) {
    try {
      final recordKey = _readString(fields['recordKey']);
      final kindName = _readString(fields['kind']);
      final updatedAt = DateTime.tryParse(_readString(fields['updatedAt']));
      final payloadRaw = _readString(fields['payloadJson']);
      if (recordKey.isEmpty || kindName.isEmpty || updatedAt == null) {
        return null;
      }

      MangaSyncRecordKind? kind;
      for (final candidate in MangaSyncRecordKind.values) {
        if (candidate.name == kindName) {
          kind = candidate;
          break;
        }
      }
      if (kind == null) return null;

      final payloadDecoded = payloadRaw.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(payloadRaw);
      if (payloadDecoded is! Map) return null;
      return MangaSyncRecord(
        recordKey: recordKey,
        kind: kind,
        workId: _readNullableString(fields['workId']),
        canonicalChapterId: _readNullableString(fields['canonicalChapterId']),
        updatedAt: updatedAt,
        tombstone: _readBool(fields['tombstone']),
        payload: Map<String, dynamic>.from(payloadDecoded),
      );
    } catch (_) {
      // User-state documents are treated fail-closed. A malformed remote
      // document must not break the rest of the account restore.
      return null;
    }
  }

  Uri _documentUri(String uid, String docId) {
    return Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/${_config.projectId}/databases/(default)/documents/users/$uid/mangaState/$docId',
    );
  }

  Uri _collectionUri(String uid) {
    return Uri.https(
      'firestore.googleapis.com',
      '/v1/projects/${_config.projectId}/databases/(default)/documents/users/$uid/mangaState',
    );
  }

  Map<String, String> _headers(FirebaseAccountSession session) {
    return <String, String>{
      'authorization': 'Bearer ${session.idToken}',
      'content-type': 'application/json',
    };
  }

  static String _documentId(String recordKey) {
    final digest = sha256.convert(utf8.encode(recordKey)).toString();
    return 'manga_$digest';
  }

  static Map<String, dynamic> _stringValue(String value) => <String, dynamic>{
    'stringValue': value,
  };

  static Map<String, dynamic> _nullableStringValue(String? value) {
    if (value == null || value.isEmpty) {
      return <String, dynamic>{'nullValue': null};
    }
    return _stringValue(value);
  }

  static String _readString(Object? encoded) {
    if (encoded is! Map) return '';
    return encoded['stringValue']?.toString() ?? '';
  }

  static String? _readNullableString(Object? encoded) {
    if (encoded is! Map || encoded.containsKey('nullValue')) return null;
    final value = encoded['stringValue']?.toString();
    return value == null || value.isEmpty ? null : value;
  }

  static bool _readBool(Object? encoded) {
    if (encoded is! Map) return false;
    return encoded['booleanValue'] == true;
  }

  static bool _isAuthError(int statusCode) =>
      statusCode == 401 || statusCode == 403;
}
