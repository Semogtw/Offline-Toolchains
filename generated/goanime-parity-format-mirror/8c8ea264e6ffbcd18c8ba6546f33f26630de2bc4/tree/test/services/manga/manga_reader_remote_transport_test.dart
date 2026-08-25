import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/manga/manga_http_client.dart';
import 'package:goanime/services/manga/manga_provider_policy.dart';
import 'package:goanime/services/manga/manga_reader_remote_transport.dart';
import 'package:goanime/services/manga/manga_request_scheduler.dart';
import 'package:goanime/services/manga/manga_source_registry.dart';
import 'package:goanime_core/goanime_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_manga_source_provider.dart';

void main() {
  test(
    'decodes transformed pages before handing bytes to the reader',
    () async {
      const sourceId = 'ptbr.test';
      const policy = MangaProviderPolicy(
        sourceId: sourceId,
        minimumRequestSpacing: Duration.zero,
        allowedContentHosts: {'example.com'},
      );
      final httpTransport = MockClient((request) async {
        expect(request.headers['cookie'], 'session=ephemeral');
        return http.Response.bytes(const [0x94, 0xbd, 0x86, 0x6b, 0x00], 200);
      });
      final client = MangaHttpClient(policy: policy, client: httpTransport);
      final registry = MangaSourceRegistry(
        providers: [FakeMangaSourceProvider(sourceId: sourceId)],
        policies: const {sourceId: policy},
      );
      final scheduler = MangaRequestScheduler(
        policies: const {sourceId: policy},
      );
      final transport = MangaReaderRemoteTransport(
        registry: registry,
        scheduler: scheduler,
        clientForSource: (_) => client,
      );
      addTearDown(() {
        transport.dispose();
        scheduler.dispose();
        httpTransport.close();
      });

      final bytes = await transport.loadImagePage(
        sourceId: sourceId,
        ownerToken: Object(),
        request: MangaPageRequest(
          index: 0,
          uri: Uri.parse('https://example.com/page.webp'),
          transform: const MangaPageTransform.xorPrefix(
            key: 'key',
            prefixLength: 4,
          ),
          ephemeralHeaders: const {'Cookie': 'session=ephemeral'},
        ),
      );

      expect(bytes, [0xff, 0xd8, 0xff, 0x00, 0x00]);
    },
  );

  test(
    'coalesces identical in-flight image loads for the same owner',
    () async {
      const sourceId = 'ptbr.test';
      const policy = MangaProviderPolicy(
        sourceId: sourceId,
        maxConcurrent: 2,
        minimumRequestSpacing: Duration.zero,
        allowedContentHosts: {'example.com'},
      );
      final requestStarted = Completer<void>();
      final releaseRequest = Completer<void>();
      var requestCount = 0;
      final httpTransport = MockClient((request) async {
        requestCount++;
        if (!requestStarted.isCompleted) requestStarted.complete();
        await releaseRequest.future;
        return http.Response.bytes(const [1, 2, 3, 4], 200);
      });
      final client = MangaHttpClient(policy: policy, client: httpTransport);
      final registry = MangaSourceRegistry(
        providers: [FakeMangaSourceProvider(sourceId: sourceId)],
        policies: const {sourceId: policy},
      );
      final scheduler = MangaRequestScheduler(
        policies: const {sourceId: policy},
      );
      final transport = MangaReaderRemoteTransport(
        registry: registry,
        scheduler: scheduler,
        clientForSource: (_) => client,
      );
      addTearDown(() {
        if (!releaseRequest.isCompleted) releaseRequest.complete();
        transport.dispose();
        scheduler.dispose();
        httpTransport.close();
      });

      final ownerToken = Object();
      final pageRequest = MangaPageRequest(
        index: 0,
        uri: Uri.parse('https://example.com/page.webp'),
        headers: const {'Referer': 'https://example.com/reader'},
        ephemeralHeaders: const {'Cookie': 'session=ephemeral'},
        transform: const MangaPageTransform.xorPrefix(
          key: 'key',
          prefixLength: 4,
        ),
      );

      final first = transport.loadImagePage(
        sourceId: sourceId,
        request: pageRequest,
        ownerToken: ownerToken,
      );
      final second = transport.loadImagePage(
        sourceId: sourceId,
        request: pageRequest,
        ownerToken: ownerToken,
      );

      await requestStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(requestCount, 1);

      releaseRequest.complete();
      expect(await first, [1 ^ 0x6b, 2 ^ 0x65, 3 ^ 0x79, 4 ^ 0x6b]);
      expect(await second, [1 ^ 0x6b, 2 ^ 0x65, 3 ^ 0x79, 4 ^ 0x6b]);
      expect(requestCount, 1);
    },
  );
}
