import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/firebase_sync_client.dart';
import 'package:goanime/services/manga/sync/manga_firebase_sync_client.dart';
import 'package:goanime/services/manga/sync/manga_sync_record.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const session = FirebaseAccountSession(
    uid: 'user-1',
    idToken: 'token',
    isAnonymous: false,
  );

  test(
    'writes Manga state into an isolated hashed Firestore namespace',
    () async {
      Uri? requestUrl;
      String? requestBody;
      final client = MangaFirebaseSyncClient(
        config: const FirebaseSyncConfig(apiKey: 'key', projectId: 'project'),
        httpClient: MockClient((request) async {
          requestUrl = request.url;
          requestBody = request.body;
          return http.Response('{}', 200);
        }),
      );
      final record = MangaSyncRecord(
        recordKey: 'progress:work/unsafe:chapter-1',
        kind: MangaSyncRecordKind.progress,
        workId: 'work/unsafe',
        canonicalChapterId: 'chapter-1',
        updatedAt: DateTime.utc(2026, 8, 24, 22),
        tombstone: false,
        payload: const <String, dynamic>{'completed': false, 'pageIndex': 8},
      );

      await client.saveRecord(session: session, record: record);

      expect(requestUrl!.path, contains('/users/user-1/mangaState/'));
      expect(requestUrl!.path, isNot(contains('work/unsafe')));
      expect(requestUrl!.pathSegments.last, startsWith('manga_'));
      expect(requestUrl!.pathSegments.last.length, 70);

      final fields =
          (jsonDecode(requestBody!) as Map<String, dynamic>)['fields']
              as Map<String, dynamic>;
      expect(fields['recordKey'], {'stringValue': record.recordKey});
      expect(fields['kind'], {'stringValue': 'progress'});
      expect(
        jsonDecode(
          (fields['payloadJson'] as Map<String, dynamic>)['stringValue']
              as String,
        ),
        containsPair('pageIndex', 8),
      );
    },
  );

  test(
    'decodes remote Manga records without widening Anime wire values',
    () async {
      final client = MangaFirebaseSyncClient(
        config: const FirebaseSyncConfig(apiKey: 'key', projectId: 'project'),
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'documents': <Map<String, dynamic>>[
                <String, dynamic>{
                  'fields': <String, dynamic>{
                    'recordKey': {'stringValue': 'library:work-1'},
                    'kind': {'stringValue': 'library'},
                    'workId': {'stringValue': 'work-1'},
                    'canonicalChapterId': {'nullValue': null},
                    'updatedAt': {'stringValue': '2026-08-25T01:00:00.000Z'},
                    'tombstone': {'booleanValue': false},
                    'payloadJson': {
                      'stringValue': jsonEncode(<String, dynamic>{
                        'status': 'reading',
                      }),
                    },
                  },
                },
              ],
            }),
            200,
          );
        }),
      );

      final records = await client.fetchRecords(session: session);

      expect(records, hasLength(1));
      expect(records.single.kind, MangaSyncRecordKind.library);
      expect(records.single.workId, 'work-1');
      expect(records.single.payload['status'], 'reading');
    },
  );
}
