part of 'download_queue_manager.dart';

extension _DownloadQueueManagerHttp on DownloadQueueManager {
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
      final fileTarget = await DownloadDirectFileTarget.prepare(
        pathService: _pathService,
        animeName: download.animeName,
        episodeNumber: download.episodeNumber,
        existingFilePath: download.filePath,
      );
      filePath = fileTarget.filePath;
      final usesScopedAndroidDirectory = fileTarget.usesScopedAndroidDirectory;
      debugPrint('[Download] Saving to: ${describeDownloadPath(filePath)}');

      var current = _downloads[id];
      if (current == null) return;
      current = current.copyWith(filePath: filePath);
      _downloads[id] = current;
      await _saveDownload(current);

      client = http.Client();
      _downloadClients[id] = client;

      final measuredResumeOffset = fileTarget.measuredResumeOffset;
      final resumeValidator = _normalizedResumeValidator(
        download.resumeValidator,
      );
      final resumeOffset = resumeValidator == null ? 0 : measuredResumeOffset;
      if (!_downloads.containsKey(id)) return;

      debugPrint('[Download] Starting stream for $id...');
      final request = http.Request('GET', Uri.parse(resolvedSource.url));
      request.headers.addAll(resolvedSource.headers);
      // Content-Length, Range offsets and persisted bytes must describe the
      // same representation. Prevent transparent content decoding from
      // changing the byte count used for completion and resume validation.
      request.headers[HttpHeaders.acceptEncodingHeader] = 'identity';
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

      final contentEncoding = response
          .headers[HttpHeaders.contentEncodingHeader]
          ?.trim();
      if (contentEncoding != null &&
          contentEncoding.isNotEmpty &&
          contentEncoding.toLowerCase() != 'identity') {
        throw const InvalidDownloadRangeFailure(
          'Direct download response used content encoding incompatible with byte-accurate storage.',
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
        DownloadQueueManager._downloadStallTimeout,
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

        final progress = DownloadCompletionPolicy.progress(
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
      debugPrint('[Download] File saved to: ${describeDownloadPath(filePath)}');
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

      if (!DownloadCompletionPolicy.isCompleteEnoughForSavedFile(
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
          '[Download] Deleted partial file after error: ${describeDownloadPath(filePath)}',
        );
      }
      rethrow;
    } finally {
      client?.close();
    }
  }
}

bool _shouldPreserveDirectPartial(DownloadItem? download, Object error) {
  if (download?.downloadKind != DownloadKind.directFile) return false;
  return error is InvalidDownloadRangeFailure ||
      error is IncompleteDownloadFailure ||
      error is InvalidDownloadValidatorFailure ||
      error is TimeoutException ||
      error is SocketException ||
      error is http.ClientException ||
      error is DownloadHttpStatusFailure;
}
