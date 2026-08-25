import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:goanime_core/goanime_core.dart';

import 'manga_http_client.dart';
import 'manga_page_transform.dart';
import 'manga_request_scheduler.dart';
import 'manga_source_registry.dart';

abstract interface class MangaReaderRemoteAssetTransport {
  Future<Uint8List> loadImagePage({
    required String sourceId,
    required MangaPageRequest request,
    required Object ownerToken,
  });

  Future<File> materializePdf({
    required String sourceId,
    required Uri uri,
    required Map<String, String> headers,
    required Directory directory,
    required Object ownerToken,
  });

  void cancelOwner(Object ownerToken);
  void dispose();
}

typedef MangaReaderHttpClientFactory =
    MangaHttpClient Function(String sourceId);

final class MangaReaderRemoteTransport
    implements MangaReaderRemoteAssetTransport {
  MangaReaderRemoteTransport({
    required MangaSourceRegistry registry,
    required MangaRequestScheduler scheduler,
    required MangaReaderHttpClientFactory clientForSource,
    this.maxImageBytes = 64 * 1024 * 1024,
    this.maxPdfBytes = 512 * 1024 * 1024,
  }) : _registry = registry,
       _scheduler = scheduler,
       _clientForSource = clientForSource,
       assert(maxImageBytes > 0),
       assert(maxPdfBytes > 0);

  final MangaSourceRegistry _registry;
  final MangaRequestScheduler _scheduler;
  final MangaReaderHttpClientFactory _clientForSource;
  final int maxImageBytes;
  final int maxPdfBytes;
  final Map<Object, Set<MangaRequestCancellationToken>> _tokensByOwner =
      Map<Object, Set<MangaRequestCancellationToken>>.identity();
  final Map<Object, Map<_ImagePageFlightKey, Future<Uint8List>>>
  _imageFlightsByOwner =
      Map<Object, Map<_ImagePageFlightKey, Future<Uint8List>>>.identity();
  bool _disposed = false;

  @override
  Future<Uint8List> loadImagePage({
    required String sourceId,
    required MangaPageRequest request,
    required Object ownerToken,
  }) {
    _ensureOpen();
    _validateUri(sourceId, request.uri);

    final key = _ImagePageFlightKey.fromRequest(sourceId, request);
    final ownerFlights = _imageFlightsByOwner.putIfAbsent(
      ownerToken,
      () => <_ImagePageFlightKey, Future<Uint8List>>{},
    );
    final existing = ownerFlights[key];
    if (existing != null) return existing;

    late final Future<Uint8List> flight;
    flight =
        _withToken(
          ownerToken,
          (token) => _scheduler.schedule<Uint8List>(
            sourceId: sourceId,
            priority: MangaRequestPriority.currentPage,
            ownerToken: ownerToken,
            operation: () async {
              final bytes = BytesBuilder(copy: false);
              await _clientForSource(sourceId).streamGet(
                request.uri,
                headers: request.transportHeaders,
                maxBytes: maxImageBytes,
                cancellationToken: token,
                onChunk: bytes.add,
              );
              token.throwIfCancelled();
              return Uint8List.fromList(
                decodeMangaPageBytes(request.transform, bytes.takeBytes()),
              );
            },
          ),
        ).whenComplete(() {
          final currentOwnerFlights = _imageFlightsByOwner[ownerToken];
          if (!identical(currentOwnerFlights?[key], flight)) return;
          currentOwnerFlights!.remove(key);
          if (currentOwnerFlights.isEmpty) {
            _imageFlightsByOwner.remove(ownerToken);
          }
        });
    ownerFlights[key] = flight;
    return flight;
  }

  @override
  Future<File> materializePdf({
    required String sourceId,
    required Uri uri,
    required Map<String, String> headers,
    required Directory directory,
    required Object ownerToken,
  }) async {
    _ensureOpen();
    _validateUri(sourceId, uri);
    await directory.create(recursive: true);

    final partial = File(
      '${directory.path}${Platform.pathSeparator}chapter.pdf.partial',
    );
    final completed = File(
      '${directory.path}${Platform.pathSeparator}chapter.pdf',
    );
    if (await partial.exists()) await partial.delete();
    if (await completed.exists()) await completed.delete();

    try {
      return await _withToken(
        ownerToken,
        (token) => _scheduler.schedule<File>(
          sourceId: sourceId,
          priority: MangaRequestPriority.currentPage,
          ownerToken: ownerToken,
          operation: () async {
            final sink = partial.openWrite();
            try {
              await _clientForSource(sourceId).streamGet(
                uri,
                headers: headers,
                maxBytes: maxPdfBytes,
                cancellationToken: token,
                onChunk: sink.add,
              );
              token.throwIfCancelled();
              await sink.flush();
            } finally {
              await sink.close();
            }
            token.throwIfCancelled();
            return partial.rename(completed.path);
          },
        ),
      );
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      if (await completed.exists()) await completed.delete();
      rethrow;
    }
  }

  Future<T> _withToken<T>(
    Object ownerToken,
    Future<T> Function(MangaRequestCancellationToken token) operation,
  ) async {
    final token = MangaRequestCancellationToken();
    final ownerTokens = _tokensByOwner.putIfAbsent(
      ownerToken,
      () => <MangaRequestCancellationToken>{},
    );
    ownerTokens.add(token);
    try {
      return await operation(token);
    } finally {
      ownerTokens.remove(token);
      if (ownerTokens.isEmpty) _tokensByOwner.remove(ownerToken);
    }
  }

  void _validateUri(String sourceId, Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw StateError('Unsupported manga reader URI scheme.');
    }
    if (uri.host.isEmpty) {
      throw StateError('Manga reader URI has no host.');
    }
    final policy = _registry.policyFor(sourceId);
    final allowedHosts = policy.allowedContentHosts
        .map((host) => host.toLowerCase())
        .toSet();
    if (allowedHosts.isNotEmpty &&
        !allowedHosts.contains(uri.host.toLowerCase())) {
      throw StateError('Manga reader content host is not approved.');
    }
  }

  @override
  void cancelOwner(Object ownerToken) {
    if (_disposed) return;
    _imageFlightsByOwner.remove(ownerToken);
    final tokens = _tokensByOwner.remove(ownerToken);
    if (tokens != null) {
      for (final token in tokens) {
        token.cancel();
      }
    }
    _scheduler.cancelOwner(ownerToken);
  }

  @override
  void dispose() {
    if (_disposed) return;
    for (final tokens in _tokensByOwner.values) {
      for (final token in tokens) {
        token.cancel();
      }
    }
    _tokensByOwner.clear();
    _imageFlightsByOwner.clear();
    _disposed = true;
  }

  void _ensureOpen() {
    if (_disposed) {
      throw StateError('Manga reader transport is disposed.');
    }
  }
}

final class _ImagePageFlightKey {
  const _ImagePageFlightKey({
    required this.sourceId,
    required this.pageIndex,
    required this.uri,
    required this.requestFingerprint,
  });

  factory _ImagePageFlightKey.fromRequest(
    String sourceId,
    MangaPageRequest request,
  ) {
    return _ImagePageFlightKey(
      sourceId: sourceId,
      pageIndex: request.index,
      uri: request.uri,
      requestFingerprint: _fingerprintRequestMetadata(request),
    );
  }

  final String sourceId;
  final int pageIndex;
  final Uri uri;
  final String requestFingerprint;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ImagePageFlightKey &&
            sourceId == other.sourceId &&
            pageIndex == other.pageIndex &&
            uri == other.uri &&
            requestFingerprint == other.requestFingerprint;
  }

  @override
  int get hashCode => Object.hash(sourceId, pageIndex, uri, requestFingerprint);

  static String _fingerprintRequestMetadata(MangaPageRequest request) {
    final headers = request.transportHeaders;
    final headerKeys = headers.keys.toList(growable: false)..sort();
    final transform = request.transform;
    final payload = <Object?>[
      for (final key in headerKeys) <Object?>[key, headers[key]],
      transform?.kind.name,
      transform?.key,
      transform?.prefixLength,
    ];
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }
}
