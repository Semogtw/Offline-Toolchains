// ignore_for_file: discarded_futures, strict_raw_type
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:goanime_core/goanime_core.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../../errors/app_failures.dart';
import '../../utils/safe_network_log.dart';
import '../app_work_coordinator.dart';
import '../media/download_queue_coordinator.dart';
import '../notification_service.dart';
import '../user_sync_service.dart';
import 'download_models.dart';
import 'download_path_service.dart';
import 'download_resolver.dart';
import 'download_storage.dart';
import 'download_transfer_health_service.dart';
import 'hls/hls_queue_download_coordinator.dart';
import 'hls/hls_transfer_checkpoint.dart';
import 'hls/hls_transfer_models.dart';

part 'download_queue_manager_hls.dart';

typedef DownloadTransferSampleReporter =
    void Function(DownloadTransferSample sample);
typedef _DownloadTransferReporter =
    void Function(DownloadTransferOutcome outcome, {Object? error});

class DownloadResumePlan {
  final bool serverAcceptedResume;
  final bool appendToExistingFile;
  final int initialBytesDownloaded;
  final int totalBytes;
  final bool alreadyComplete;

  const DownloadResumePlan({
    required this.serverAcceptedResume,
    required this.appendToExistingFile,
    required this.initialBytesDownloaded,
    required this.totalBytes,
    this.alreadyComplete = false,
  });

  factory DownloadResumePlan.fromHttpResponse({
    required int resumeOffset,
    required int statusCode,
    required int? contentLength,
    required String? contentRange,
  }) {
    final knownContentLength = contentLength != null && contentLength >= 0
        ? contentLength
        : null;
    if (statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      if (resumeOffset <= 0 || contentRange == null) {
        throw const InvalidDownloadRangeFailure(
          'Range-not-satisfiable response is missing completion proof.',
        );
      }
      final match = RegExp(
        r'^bytes \*/(\d+)$',
        caseSensitive: false,
      ).firstMatch(contentRange.trim());
      final declaredTotal = match == null
          ? null
          : int.tryParse(match.group(1)!);
      if (declaredTotal == null ||
          declaredTotal <= 0 ||
          declaredTotal != resumeOffset) {
        throw const InvalidDownloadRangeFailure(
          'Range-not-satisfiable response does not match the local partial length.',
        );
      }
      return DownloadResumePlan(
        serverAcceptedResume: true,
        appendToExistingFile: false,
        initialBytesDownloaded: resumeOffset,
        totalBytes: declaredTotal,
        alreadyComplete: true,
      );
    }

    if (statusCode != HttpStatus.partialContent) {
      return DownloadResumePlan(
        serverAcceptedResume: false,
        appendToExistingFile: false,
        initialBytesDownloaded: 0,
        totalBytes: knownContentLength ?? 0,
      );
    }

    if (resumeOffset <= 0 || contentRange == null) {
      throw const InvalidDownloadRangeFailure(
        'Partial download response is missing a valid resume request or Content-Range.',
      );
    }
    final match = RegExp(
      r'^bytes (\d+)-(\d+)/(\d+|\*)$',
      caseSensitive: false,
    ).firstMatch(contentRange.trim());
    if (match == null) {
      throw const InvalidDownloadRangeFailure(
        'Partial download response has a malformed Content-Range.',
      );
    }

    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final totalText = match.group(3)!;
    final declaredTotal = totalText == '*' ? null : int.tryParse(totalText);
    if (declaredTotal == null) {
      throw const InvalidDownloadRangeFailure(
        'Partial download response is missing a known remote total.',
      );
    }
    if (start == null ||
        end == null ||
        start != resumeOffset ||
        end < start ||
        declaredTotal <= end) {
      throw const InvalidDownloadRangeFailure(
        'Partial download response does not match the requested byte offset.',
      );
    }

    final rangeLength = end - start + 1;
    if (knownContentLength != null && knownContentLength != rangeLength) {
      throw const InvalidDownloadRangeFailure(
        'Partial download response length does not match Content-Range.',
      );
    }

    return DownloadResumePlan(
      serverAcceptedResume: true,
      appendToExistingFile: true,
      initialBytesDownloaded: resumeOffset,
      totalBytes: declaredTotal,
    );
  }
}

class DownloadQueueManager {
  static const double _minimumCompletionProgress = 0.98;
  static const Duration _downloadStallTimeout = Duration(seconds: 12);

  final DownloadStorage _storage;
  final DownloadPathService _pathService;
  final DownloadResolver _resolver;
  final VoidCallback _onChanged;

  final UserSyncService _syncService;
  final AppWorkCoordinator _workCoordinator;
  final NotificationService _notificationService;
  final DownloadTransferSampleReporter _onTransferHealthSample;
  final DownloadQueueCoordinator<String> _queueCoordinator;
  final HlsQueueDownloadCoordinator _hlsCoordinator;

  final Map<String, DownloadItem> _downloads = {};
  final Map<String, StreamSubscription> _activeDownloads = {};
  final Map<String, http.Client> _downloadClients = {};

  DownloadQueueManager({
    required DownloadStorage storage,
    required DownloadPathService pathService,
    required DownloadResolver resolver,
    required VoidCallback onChanged,
    UserSyncService? syncService,
    AppWorkCoordinator? workCoordinator,
    NotificationService? notificationService,
    DownloadTransferSampleReporter? onTransferHealthSample,
    HlsQueueDownloadCoordinator? hlsCoordinator,
  }) : _storage = storage,
       _pathService = pathService,
       _resolver = resolver,
       _onChanged = onChanged,
       _syncService = syncService ?? UserSyncService.instance,
       _workCoordinator = workCoordinator ?? AppWorkCoordinator.instance,
       _notificationService = notificationService ?? NotificationService(),
       _onTransferHealthSample =
           onTransferHealthSample ??
           DownloadTransferHealthService.instance.record,
       _queueCoordinator = DownloadQueueCoordinator<String>(
         policy: DownloadConcurrencyPolicy(maxConcurrent: 3),
       ),
       _hlsCoordinator =
           hlsCoordinator ??
           HlsQueueDownloadCoordinator(
             getDownloadDirectory: pathService.getDownloadDirectory,
             backend: Platform.isAndroid
                 ? SafHlsQueuePackageBackend(
                     getTreeUri: () async => pathService.customDownloadTreeUri,
                   )
                 : null,
           );

  List<DownloadItem> get downloads => _downloads.values.toList();

  List<DownloadItem> get activeDownloads => _downloads.values
      .where(
        (d) =>
            d.status == DownloadStatus.downloading ||
            d.status == DownloadStatus.queued ||
            d.status == DownloadStatus.paused ||
            d.status == DownloadStatus.failed,
      )
      .toList();

  List<DownloadItem> get completedDownloads => _downloads.values
      .where((d) => d.status == DownloadStatus.completed)
      .toList();

  int get maxConcurrentDownloads => _queueCoordinator.policy.maxConcurrent;

  set maxConcurrentDownloads(int value) {
    _queueCoordinator.updatePolicy(
      DownloadConcurrencyPolicy(maxConcurrent: value.clamp(1, 5)),
    );
    _onChanged();
  }

  int get activeDownloadCount => _queueCoordinator.activeCount;

  static bool isCompleteEnoughForSavedFile({
    required int savedBytes,
    required int totalBytes,
    required double currentProgress,
    bool requireExactKnownTotal = false,
  }) {
    if (requireExactKnownTotal && totalBytes > 0) {
      return savedBytes == totalBytes;
    }
    if (totalBytes <= 0) {
      return savedBytes > 0 || currentProgress >= _minimumCompletionProgress;
    }
    final finalProgress = savedBytes / totalBytes;
    return finalProgress >= _minimumCompletionProgress;
  }

  static double downloadProgress({
    required int bytesDownloaded,
    required int totalBytes,
  }) {
    if (totalBytes <= 0) {
      return 0;
    }
    return (bytesDownloaded / totalBytes).clamp(0.0, 1.0).toDouble();
  }

  static bool hasKnownTotalBytes(int totalBytes) => totalBytes > 0;

  Future<void> initialize() async {
    final downloads = await _storage.loadDownloads();
    _downloads.clear();

    for (var download in downloads) {
      _downloads[download.id] = download;

      // Reset downloading status to queued on app restart
      if (download.status == DownloadStatus.downloading) {
        _downloads[download.id] = download.copyWith(
          status: DownloadStatus.queued,
        );
      }
    }
    _onChanged();
    _processQueue();
  }

  Future<String> addDownload({
    required String animeId,
    required String animeName,
    required String episodeNumber,
    required String episodeTitle,
    required String videoUrl,
    required String thumbnailUrl,
    DownloadQuality quality = DownloadQuality.auto,
  }) async {
    if (Platform.isAndroid && _pathService.customDownloadTreeUri == null) {
      throw Exception('Escolha uma pasta de download nas configurações.');
    }

    final id = '${animeId}_$episodeNumber';

    if (_downloads.containsKey(id)) {
      final existing = _downloads[id]!;
      if (existing.status == DownloadStatus.completed) {
        throw Exception('Episode already downloaded');
      }
      if (existing.status == DownloadStatus.downloading ||
          existing.status == DownloadStatus.queued) {
        throw Exception('Episode is already in download queue');
      }
      await deleteDownload(id);
    }

    final download = DownloadItem(
      id: id,
      animeId: animeId,
      animeName: animeName,
      episodeNumber: episodeNumber,
      episodeTitle: episodeTitle,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      quality: quality,
    );

    _downloads[id] = download;
    await _saveDownload(download);
    await _syncService.recordSettings({
      'lastDownloadId': download.id,
      'lastDownloadAnimeId': download.animeId,
      'lastDownloadEpisode': download.episodeNumber,
      'downloadUpdatedAt': DateTime.now().toIso8601String(),
    });

    _onChanged();
    _processQueue();

    return id;
  }

  Future<List<String>> addBatchDownloads({
    required String animeId,
    required String animeName,
    required List<Map<String, String>> episodes,
    required String thumbnailUrl,
    DownloadQuality quality = DownloadQuality.auto,
  }) async {
    final futures = episodes.map((episode) async {
      try {
        return await addDownload(
          animeId: animeId,
          animeName: animeName,
          episodeNumber: episode['number']!,
          episodeTitle: episode['title'] ?? 'Episode ${episode['number']}',
          videoUrl: episode['url']!,
          thumbnailUrl: thumbnailUrl,
          quality: quality,
        );
      } catch (e) {
        debugPrint('Failed to add episode ${episode['number']}: $e');
        return null;
      }
    });

    final results = await Future.wait(futures);
    return results.whereType<String>().toList();
  }

  Future<List<String>> addUnifiedBatchDownloads({
    required String animeId,
    required String animeName,
    required List<UnifiedDownloadRequest> episodes,
    DownloadQuality quality = DownloadQuality.auto,
  }) async {
    final ids = <String>[];
    for (final episode in episodes) {
      try {
        final id = await addDownload(
          animeId: animeId,
          animeName: animeName,
          episodeNumber: episode.episodeNumber.toString(),
          episodeTitle: episode.episodeTitle,
          videoUrl: episode.videoUrl,
          thumbnailUrl: episode.thumbnailUrl,
          quality: quality,
        );
        ids.add(id);
      } catch (e) {
        debugPrint(
          'Failed to add unified episode ${episode.episodeNumber}: $e',
        );
      }
    }
    return ids;
  }

  void _processQueue() {
    final queuedDownloads =
        _downloads.values
            .where((d) => d.status == DownloadStatus.queued)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (final download in queuedDownloads) {
      if (_queueCoordinator.isKnown(download.id)) continue;
      final future = _queueCoordinator.enqueue<void>(
        key: download.id,
        operation: (_) => _startDownload(download.id),
      );
      unawaited(
        future.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {
            if (error is MediaDownloadQueueCancelledException) return;
            debugPrint(
              '[Download] Queue execution failed for ${download.id}: $error',
            );
          },
        ),
      );
    }
  }

  Future<void> _startDownload(String id) async {
    final download = _downloads[id];
    if (download == null || download.status != DownloadStatus.queued) return;

    _workCoordinator.setDownloadActive(true);
    _downloads[id] = download.copyWith(
      status: DownloadStatus.downloading,
      clearError: true,
      clearCompletedAt: true,
    );
    await _saveDownload(_downloads[id]!);
    _onChanged();

    try {
      final isAllAnimeEpisode =
          !download.videoUrl.startsWith('http') &&
          int.tryParse(download.videoUrl) != null;

      if (!isAllAnimeEpisode) {
        final Uri uri;
        try {
          uri = Uri.parse(download.videoUrl);
          if (!uri.hasScheme ||
              (uri.scheme != 'http' && uri.scheme != 'https')) {
            throw Exception('Invalid URL format');
          }
          if (uri.host.isEmpty) {
            throw Exception('Invalid URL format');
          }
        } catch (e) {
          if (e.toString().contains('Invalid URL format')) {
            rethrow;
          }
          throw Exception(
            'Invalid video URL: ${SafeNetworkLog.url(download.videoUrl)}',
          );
        }
      }

      await _downloadHttp(id);
    } catch (e) {
      debugPrint('Download error for $id: $e');
      final currentDownload = _downloads[id];
      if (currentDownload == null) {
        // Deleted. Do not update its state in memory or database, and do not perform file cleanup.
        return;
      }
      if (currentDownload.status == DownloadStatus.paused ||
          currentDownload.status == DownloadStatus.cancelled) {
        // Do not overwrite the status to failed and do not save it to DB.
        return;
      }
      _downloads[id] = currentDownload.copyWith(
        status: DownloadStatus.failed,
        error: e.toString(),
      );
      await _saveDownload(_downloads[id]!);

      final failedDownload = _downloads[id];
      final filePath = failedDownload?.filePath;
      if (filePath != null &&
          !_shouldPreserveDirectPartial(failedDownload, e)) {
        await _deleteDownloadFile(filePath);
        debugPrint(
          '[Download] Deleted partial file after error: ${_describeDownloadPath(filePath)}',
        );
      }
    } finally {
      // The shared coordinator still counts this operation as active until
      // _startDownload returns. More than one means another transfer remains.
      _workCoordinator.setDownloadActive(_queueCoordinator.activeCount > 1);
      _activeDownloads.remove(id);
      _downloadClients.remove(id);
      _onChanged();
    }
  }

  Future<void> _downloadHttp(String id) async {
    final download = _downloads[id];
    if (download == null) return;

    debugPrint('[Download] Starting download for $id');
    debugPrint(
      '[Download] Episode URL: ${SafeNetworkLog.url(download.videoUrl)}',
    );
    debugPrint('[Download] Anime ID: ${download.animeId}');

    late final ResolvedDownloadSource resolvedSource;
    try {
      debugPrint('[Download] Resolving video URL...');
      resolvedSource = await _resolver.resolveDownloadSource(download);
      debugPrint(
        '[Download] Resolved video URL: ${SafeNetworkLog.url(resolvedSource.url)}',
      );
    } catch (e) {
      debugPrint(
        SafeNetworkLog.sanitize('[Download] Failed to resolve video URL: $e'),
      );
      if (e.toString().contains('HLS') || e.toString().contains('streaming')) {
        rethrow;
      }
      throw Exception('Failed to get video URL: $e');
    }

    final transferStopwatch = Stopwatch()..start();
    var resumeOutcome = DownloadResumeOutcome.notAttempted;
    var healthReported = false;
    void reportTransfer(DownloadTransferOutcome outcome, {Object? error}) {
      if (healthReported) return;
      healthReported = true;
      _reportTransferHealth(
        DownloadTransferSample(
          source: resolvedSource.source,
          outcome: outcome,
          resumeOutcome: resumeOutcome,
          elapsed: transferStopwatch.elapsed,
          errorType: error?.runtimeType.toString(),
        ),
      );
    }

    if (resolvedSource.downloadKind == DownloadKind.hlsPackage) {
      await _downloadHls(id, download, resolvedSource, reportTransfer);
      return;
    }

    String? filePath;
    http.Client? client;
    IOSink? sink;
    int? scopedHandle;

    try {
      final safeAnimeName = _sanitizeFileName(download.animeName);
      final safeEpisodeNumber = _sanitizeFileName(download.episodeNumber);
      final fileName = 'Episode_$safeEpisodeNumber.mp4';
      final usesScopedAndroidDirectory =
          _pathService.usesScopedAndroidDirectory;

      final existingFilePath = download.filePath;
      final canResumeLocalFile =
          !usesScopedAndroidDirectory &&
          existingFilePath != null &&
          await File(existingFilePath).exists();
      final scopedResumeOffset =
          usesScopedAndroidDirectory &&
              existingFilePath != null &&
              DownloadPathService.isScopedDocumentUri(existingFilePath)
          ? await _pathService.getDownloadFileLength(existingFilePath)
          : 0;
      final canResumeScopedFile = scopedResumeOffset > 0;

      if (canResumeLocalFile) {
        filePath = existingFilePath;
      } else if (canResumeScopedFile) {
        filePath = existingFilePath!;
      } else if (usesScopedAndroidDirectory) {
        filePath = await _pathService.createScopedDownloadFile(
          safeAnimeName,
          fileName,
        );
      } else {
        final downloadDir = await _pathService.getDownloadDirectory();
        final animeDir = Directory(path.join(downloadDir.path, safeAnimeName));
        await animeDir.create(recursive: true);
        filePath = path.join(animeDir.path, fileName);
      }
      debugPrint('[Download] Saving to: ${_describeDownloadPath(filePath)}');

      var current = _downloads[id];
      if (current == null) return;
      current = current.copyWith(filePath: filePath);
      _downloads[id] = current;
      await _saveDownload(current);

      client = http.Client();
      _downloadClients[id] = client;

      final measuredResumeOffset = canResumeLocalFile
          ? await File(filePath).length()
          : scopedResumeOffset;
      final resumeValidator = _normalizedResumeValidator(
        download.resumeValidator,
      );
      final resumeOffset = resumeValidator == null ? 0 : measuredResumeOffset;
      if (!_downloads.containsKey(id)) return;

      debugPrint('[Download] Starting stream for $id...');
      final request = http.Request('GET', Uri.parse(resolvedSource.url));
      request.headers.addAll(resolvedSource.headers);
      if (resumeOffset > 0) {
        request.headers[HttpHeaders.rangeHeader] = 'bytes=$resumeOffset-';
        request.headers[HttpHeaders.ifRangeHeader] = resumeValidator!;
        debugPrint('[Download] Resuming local file from byte $resumeOffset');
      }
      final response = await client.send(request);
      if (!_downloads.containsKey(id)) return;

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent &&
          response.statusCode != HttpStatus.requestedRangeNotSatisfiable) {
        throw DownloadHttpStatusFailure(
          response.statusCode,
          'Failed to download: ${response.statusCode}',
        );
      }

      if (resumeOffset > 0 &&
          resumeValidator != null &&
          response.statusCode != HttpStatus.ok) {
        _validateResponseResumeValidator(
          expected: resumeValidator,
          headers: response.headers,
        );
      }
      final resumePlan = DownloadResumePlan.fromHttpResponse(
        resumeOffset: resumeOffset,
        statusCode: response.statusCode,
        contentLength: response.contentLength,
        contentRange: response.headers[HttpHeaders.contentRangeHeader],
      );
      final responseValidator = _responseResumeValidator(response.headers);
      var responseDownload = _downloads[id];
      if (responseDownload == null) return;
      if (response.statusCode == HttpStatus.ok) {
        responseDownload = responseDownload.copyWith(
          resumeValidator: responseValidator,
          clearResumeValidator: responseValidator == null,
        );
        _downloads[id] = responseDownload;
        await _saveDownload(responseDownload);
      }
      if (resumeOffset > 0) {
        resumeOutcome = resumePlan.serverAcceptedResume
            ? DownloadResumeOutcome.accepted
            : DownloadResumeOutcome.restarted;
      }
      final totalBytes = resumePlan.totalBytes;
      debugPrint(
        '[Download] Total size: $totalBytes bytes (${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB)',
      );

      if (resumePlan.alreadyComplete) {
        final savedBytes = await _pathService.getDownloadFileLength(filePath);
        if (savedBytes != totalBytes) {
          throw const InvalidDownloadRangeFailure(
            'Saved partial length changed before completion could be committed.',
          );
        }
        final currentDownload = _downloads[id];
        if (currentDownload == null) return;
        if (currentDownload.status == DownloadStatus.cancelled) {
          reportTransfer(DownloadTransferOutcome.cancelled);
          return;
        }
        if (currentDownload.status == DownloadStatus.paused) {
          reportTransfer(DownloadTransferOutcome.paused);
          return;
        }
        final completedDownload = currentDownload.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          bytesDownloaded: savedBytes,
          totalBytes: totalBytes,
          filePath: filePath,
          completedAt: DateTime.now(),
        );
        _downloads[id] = completedDownload;
        await _saveDownload(completedDownload);
        reportTransfer(DownloadTransferOutcome.success);
        await _notificationService.showDownloadComplete(
          id: _getNotificationId(id),
          title: completedDownload.animeName,
        );
        _onChanged();
        return;
      }

      sink = usesScopedAndroidDirectory
          ? null
          : File(filePath).openWrite(
              mode: resumePlan.appendToExistingFile
                  ? FileMode.append
                  : FileMode.write,
            );
      scopedHandle = usesScopedAndroidDirectory
          ? await _pathService.openScopedDownloadFile(
              filePath,
              append: resumePlan.appendToExistingFile,
            )
          : null;
      if (!_downloads.containsKey(id)) return;

      final scopedWriteBuffer = usesScopedAndroidDirectory
          ? BytesBuilder(copy: false)
          : null;
      int bytesDownloaded = resumePlan.initialBytesDownloaded;
      int lastNotificationBytes = bytesDownloaded;
      int lastSaveBytes = bytesDownloaded;
      const notificationInterval = 256 * 1024;
      const saveInterval = 1024 * 1024;

      await for (var chunk in response.stream.timeout(
        _downloadStallTimeout,
        onTimeout: (sink) {
          debugPrint('[Download] Stream timed out for $id');
          sink.addError(TimeoutException('Stream timed out'));
        },
      )) {
        final d = _downloads[id];
        if (d == null) {
          await _closeDownloadOutput(sink, scopedHandle);
          await _deleteDownloadFile(filePath);
          await _notificationService.cancelNotification(_getNotificationId(id));
          return;
        }
        if (d.status == DownloadStatus.cancelled) {
          reportTransfer(DownloadTransferOutcome.cancelled);
          await _closeDownloadOutput(sink, scopedHandle);
          await _deleteDownloadFile(filePath);
          await _notificationService.cancelNotification(_getNotificationId(id));
          return;
        }

        if (d.status == DownloadStatus.paused) {
          reportTransfer(DownloadTransferOutcome.paused);
          await _closeDownloadOutput(sink, scopedHandle);
          return;
        }

        if (resumePlan.appendToExistingFile &&
            totalBytes > 0 &&
            bytesDownloaded + chunk.length > totalBytes) {
          throw const InvalidDownloadRangeFailure(
            'Partial response body exceeds the declared remote total.',
          );
        }

        if (usesScopedAndroidDirectory) {
          scopedWriteBuffer!.add(chunk);
          if (scopedWriteBuffer.length >= notificationInterval) {
            await _pathService.writeScopedDownloadChunk(
              scopedHandle!,
              scopedWriteBuffer.takeBytes(),
            );
          }
        } else {
          sink!.add(chunk);
        }
        bytesDownloaded += chunk.length;

        final progress = downloadProgress(
          bytesDownloaded: bytesDownloaded,
          totalBytes: totalBytes,
        );
        final updatedItem = d.copyWith(
          progress: progress,
          bytesDownloaded: bytesDownloaded,
          totalBytes: totalBytes,
        );
        _downloads[id] = updatedItem;

        if (bytesDownloaded - lastNotificationBytes >= notificationInterval) {
          lastNotificationBytes = bytesDownloaded;
          _onChanged();
        }

        final shouldSave = totalBytes > 0
            ? (totalBytes >= 100 &&
                  (bytesDownloaded - lastSaveBytes) >= (totalBytes ~/ 100))
            : ((bytesDownloaded - lastSaveBytes) >= saveInterval);

        if (shouldSave) {
          lastSaveBytes = bytesDownloaded;
          debugPrint(
            '[Download] Progress: ${(progress * 100).toStringAsFixed(1)}% (${(bytesDownloaded / 1024 / 1024).toStringAsFixed(2)} MB)',
          );
          await _saveDownload(updatedItem);

          await _notificationService.updateDownloadProgress(
            id: _getNotificationId(id),
            title: updatedItem.animeName,
            progress: bytesDownloaded,
            total: totalBytes > 0 ? totalBytes : bytesDownloaded,
          );
        }
      }

      if (scopedWriteBuffer != null && scopedWriteBuffer.isNotEmpty) {
        await _pathService.writeScopedDownloadChunk(
          scopedHandle!,
          scopedWriteBuffer.takeBytes(),
        );
      }
      await _closeDownloadOutput(sink, scopedHandle);

      if (!_downloads.containsKey(id)) return;

      final savedBytes = await _pathService.getDownloadFileLength(filePath);
      debugPrint('[Download] Download completed: $id');
      debugPrint(
        '[Download] File saved to: ${_describeDownloadPath(filePath)}',
      );
      debugPrint('[Download] Saved size: $savedBytes bytes');

      final currentDownload = _downloads[id];
      if (currentDownload == null) return;
      if (currentDownload.status == DownloadStatus.cancelled) {
        reportTransfer(DownloadTransferOutcome.cancelled);
        return;
      }
      if (currentDownload.status == DownloadStatus.paused) {
        reportTransfer(DownloadTransferOutcome.paused);
        return;
      }

      if (!isCompleteEnoughForSavedFile(
            savedBytes: savedBytes,
            totalBytes: totalBytes,
            currentProgress: currentDownload.progress,
            requireExactKnownTotal: resumePlan.serverAcceptedResume,
          ) &&
          currentDownload.status != DownloadStatus.cancelled) {
        throw IncompleteDownloadFailure(
          'Download stream finished before the declared total '
          '(${(currentDownload.progress * 100).toStringAsFixed(1)}%).',
        );
      }

      final completedDownload = currentDownload.copyWith(
        status: DownloadStatus.completed,
        progress: 1.0,
        bytesDownloaded: savedBytes > 0 ? savedBytes : bytesDownloaded,
        totalBytes: savedBytes > 0 ? savedBytes : currentDownload.totalBytes,
        filePath: filePath,
        completedAt: DateTime.now(),
      );
      _downloads[id] = completedDownload;
      await _saveDownload(completedDownload);

      reportTransfer(DownloadTransferOutcome.success);
      await _notificationService.showDownloadComplete(
        id: _getNotificationId(id),
        title: completedDownload.animeName,
      );
      _onChanged();
    } catch (e) {
      final currentStatus = _downloads[id]?.status;
      if (currentStatus == DownloadStatus.paused) {
        reportTransfer(DownloadTransferOutcome.paused);
      } else if (currentStatus == DownloadStatus.cancelled) {
        reportTransfer(DownloadTransferOutcome.cancelled);
      } else {
        reportTransfer(
          DownloadTransferHealthService.classifyError(e),
          error: e,
        );
      }

      await _closeDownloadOutput(sink, scopedHandle);
      await _notificationService.cancelNotification(_getNotificationId(id));

      if (filePath != null &&
          !_shouldPreserveDirectPartial(_downloads[id], e) &&
          _downloads.containsKey(id) &&
          _downloads[id]!.status != DownloadStatus.completed &&
          _downloads[id]!.status != DownloadStatus.paused) {
        await _deleteDownloadFile(filePath);
        debugPrint(
          '[Download] Deleted partial file after error: ${_describeDownloadPath(filePath)}',
        );
      }
      rethrow;
    } finally {
      client?.close();
    }
  }

  Future<void> pauseDownload(String id) async {
    final download = _downloads[id];
    if (download == null || download.status != DownloadStatus.downloading) {
      return;
    }
    _downloads[id] = download.copyWith(status: DownloadStatus.paused);
    _hlsCoordinator.pause(id);
    _downloadClients[id]?.close();
    await _saveDownload(_downloads[id]!);
    _onChanged();
  }

  Future<void> resumeDownload(String id) async {
    final download = _downloads[id];
    if (download == null || download.status != DownloadStatus.paused) return;
    _downloads[id] = download.copyWith(status: DownloadStatus.queued);
    await _saveDownload(_downloads[id]!);
    _onChanged();
    _processQueue();
  }

  Future<void> cancelDownload(String id) async {
    final download = _downloads[id];
    if (download == null) return;
    _queueCoordinator.cancel(id);
    final hlsWasActive = _hlsCoordinator.cancel(id);
    var cancelled = download.copyWith(status: DownloadStatus.cancelled);
    _downloadClients[id]?.close();
    if (download.downloadKind == DownloadKind.hlsPackage && !hlsWasActive) {
      await _cleanupHlsPackage(download);
      cancelled = cancelled.copyWith(
        clearPackageRootPath: true,
        clearPackageEntryPath: true,
        clearCheckpointPath: true,
        clearPackageFormatVersion: true,
      );
    }
    _downloads[id] = cancelled;
    await _saveDownload(cancelled);
    if (download.filePath != null) {
      await _deleteDownloadFile(download.filePath!);
    }
    _onChanged();
  }

  Future<void> retryDownload(String id) async {
    final download = _downloads[id];
    if (download == null || download.status != DownloadStatus.failed) return;
    if (download.downloadKind == DownloadKind.hlsPackage) {
      await _cleanupHlsPackage(download);
    }

    var partialBytes = 0;
    final existingFilePath = download.downloadKind == DownloadKind.directFile
        ? download.filePath
        : null;
    if (existingFilePath != null) {
      try {
        partialBytes = await _pathService.getDownloadFileLength(
          existingFilePath,
        );
      } catch (_) {
        partialBytes = 0;
      }
    }
    final canResumePartial = existingFilePath != null && partialBytes > 0;
    final retryTotalBytes = canResumePartial ? download.totalBytes : 0;

    _downloads[id] = download.copyWith(
      status: DownloadStatus.queued,
      progress: canResumePartial
          ? downloadProgress(
              bytesDownloaded: partialBytes,
              totalBytes: retryTotalBytes,
            )
          : 0,
      bytesDownloaded: canResumePartial ? partialBytes : 0,
      totalBytes: retryTotalBytes,
      filePath: canResumePartial ? existingFilePath : null,
      downloadKind: DownloadKind.directFile,
      clearFilePath: !canResumePartial,
      clearResumeValidator: !canResumePartial,
      clearError: true,
      clearCompletedAt: true,
      clearPackageRootPath: true,
      clearPackageEntryPath: true,
      clearCheckpointPath: true,
      clearPackageFormatVersion: true,
    );
    await _saveDownload(_downloads[id]!);
    _onChanged();
    _processQueue();
  }

  Future<void> deleteDownload(String id) async {
    final download = _downloads[id];
    if (download == null) return;
    _queueCoordinator.cancel(id);
    final wasDownloading = download.status == DownloadStatus.downloading;
    if (wasDownloading) {
      await cancelDownload(id);
    }
    final current = _downloads[id] ?? download;
    if (!wasDownloading && current.downloadKind == DownloadKind.hlsPackage) {
      await _cleanupHlsPackage(current);
    }
    if (current.filePath != null) {
      await _deleteDownloadFile(current.filePath!);
    }
    await _storage.deleteDownload(id);
    _downloads.remove(id);
    _onChanged();
  }

  Future<void> clearCompleted() async {
    final completed = _downloads.values
        .where((d) => d.status == DownloadStatus.completed)
        .toList();
    await Future.wait(completed.map((d) => deleteDownload(d.id)));
  }

  Future<void> deleteDownloadsOlderThan(int days) async {
    final now = DateTime.now();
    final threshold = now.subtract(Duration(days: days));
    final oldDownloads = _downloads.values.where((d) {
      return d.status == DownloadStatus.completed &&
          d.completedAt != null &&
          d.completedAt!.isBefore(threshold);
    }).toList();
    await Future.wait(oldDownloads.map((d) => deleteDownload(d.id)));
  }

  Future<void> clearFailedDownloads() async {
    final failed = _downloads.values
        .where(
          (d) =>
              d.status == DownloadStatus.failed ||
              d.status == DownloadStatus.cancelled,
        )
        .toList();
    await Future.wait(failed.map((d) => deleteDownload(d.id)));
  }

  DownloadItem? getDownload(String id) => _downloads[id];

  List<DownloadItem> getAnimeDownloads(String animeId) {
    return _downloads.values.where((d) => d.animeId == animeId).toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
  }

  static String? _normalizedResumeValidator(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (!trimmed.startsWith('W/') &&
        trimmed.length >= 2 &&
        trimmed.startsWith('"') &&
        trimmed.endsWith('"')) {
      return trimmed;
    }
    try {
      return HttpDate.format(HttpDate.parse(trimmed).toUtc());
    } on FormatException {
      return null;
    } on HttpException {
      return null;
    }
  }

  static String? _responseResumeValidator(Map<String, String> headers) {
    final etag = _normalizedResumeValidator(headers[HttpHeaders.etagHeader]);
    if (etag != null && etag.startsWith('"')) return etag;
    return _normalizedResumeValidator(headers[HttpHeaders.lastModifiedHeader]);
  }

  static void _validateResponseResumeValidator({
    required String expected,
    required Map<String, String> headers,
  }) {
    final isEtag = expected.startsWith('"');
    final headerName = isEtag
        ? HttpHeaders.etagHeader
        : HttpHeaders.lastModifiedHeader;
    final rawObserved = headers[headerName];
    if (rawObserved == null) return;
    final observed = _normalizedResumeValidator(rawObserved);
    if (observed != expected) {
      throw const InvalidDownloadValidatorFailure(
        'Partial response validator does not match the saved entity.',
      );
    }
  }

  static bool _shouldPreserveDirectPartial(
    DownloadItem? download,
    Object error,
  ) {
    if (download?.downloadKind != DownloadKind.directFile) return false;
    return error is InvalidDownloadRangeFailure ||
        error is IncompleteDownloadFailure ||
        error is InvalidDownloadValidatorFailure ||
        error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException ||
        error is DownloadHttpStatusFailure;
  }

  Future<void> _saveDownload(DownloadItem download) async =>
      await _storage.saveDownload(download);

  Future<void> _closeDownloadOutput(IOSink? sink, int? scopedHandle) async {
    if (sink != null) {
      await sink.flush();
      await sink.close();
    } else if (scopedHandle != null) {
      await _pathService.closeScopedDownloadFile(scopedHandle);
    }
  }

  Future<void> _deleteDownloadFile(String filePath) async =>
      await _pathService.deleteDownloadFile(filePath);

  String _describeDownloadPath(String filePath) {
    final fileName = path.basename(filePath.replaceAll('\\', '/'));
    if (DownloadPathService.isScopedDocumentUri(filePath)) {
      return 'scoped-document:$fileName';
    }
    return fileName;
  }

  String _sanitizeFileName(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  void _reportTransferHealth(DownloadTransferSample sample) {
    try {
      _onTransferHealthSample(sample);
    } catch (_) {
      // Health reporting is best-effort and must never change downloads.
    }
  }

  void dispose() {
    _queueCoordinator.dispose();
    for (var client in _downloadClients.values) {
      client.close();
    }
    _downloadClients.clear();
    _activeDownloads.clear();
    _hlsCoordinator.dispose();
  }

  int _getNotificationId(String id) => id.hashCode.abs() % 100000;
}
