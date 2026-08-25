import 'package:flutter/foundation.dart';

import 'manga_account_sync_service.dart';
import 'manga_sync_local_store.dart';
import 'manga_sync_record.dart';

final class MangaSyncRecorder {
  MangaSyncRecorder({
    MangaSyncLocalStore? localStore,
    MangaAccountSyncService? accountSyncService,
  }) : _localStore = localStore ?? MangaSyncLocalStore(),
       _accountSyncService =
           accountSyncService ?? MangaAccountSyncService.instance;

  static final MangaSyncRecorder instance = MangaSyncRecorder();

  static const String defaultReaderModePreferenceKey = 'defaultReaderMode';

  final MangaSyncLocalStore _localStore;
  final MangaAccountSyncService _accountSyncService;

  Future<void> recordLibrary(String workId) async {
    await _recordFrom(() => _localStore.libraryRecord(workId));
  }

  Future<void> recordLibraryRemoved(String workId, DateTime removedAt) async {
    await _recordSafely(
      MangaSyncRecord(
        recordKey: MangaSyncRecordKeys.library(workId),
        kind: MangaSyncRecordKind.library,
        workId: workId,
        updatedAt: removedAt,
        tombstone: true,
        payload: const <String, dynamic>{},
      ),
    );
  }

  Future<void> recordProgress(String workId, String canonicalChapterId) async {
    await _recordFrom(
      () => _localStore.progressRecord(workId, canonicalChapterId),
    );
  }

  Future<void> recordReaderPreference(String workId) async {
    await _recordFrom(() => _localStore.readerPreferenceRecord(workId));
  }

  Future<void> recordReaderPreferenceRemoved(
    String workId,
    DateTime removedAt,
  ) async {
    await _recordSafely(
      MangaSyncRecord(
        recordKey: MangaSyncRecordKeys.readerPreference(workId),
        kind: MangaSyncRecordKind.readerPreference,
        workId: workId,
        updatedAt: removedAt,
        tombstone: true,
        payload: const <String, dynamic>{},
      ),
    );
  }

  Future<void> recordSourcePreference(String workId) async {
    await _recordFrom(() => _localStore.sourcePreferenceRecord(workId));
  }

  Future<void> recordDefaultReaderMode() async {
    await _recordFrom(
      () => _localStore.globalPreferenceRecord(defaultReaderModePreferenceKey),
    );
  }

  Future<void> _recordFrom(Future<MangaSyncRecord?> Function() loader) async {
    if (!_accountSyncService.isInitialized) return;
    try {
      final record = await loader();
      if (record != null) await _accountSyncService.record(record);
    } catch (error) {
      debugPrint(
        '[MangaSync] Local mutation kept; recorder failed (${error.runtimeType}).',
      );
    }
  }

  Future<void> _recordSafely(MangaSyncRecord record) async {
    if (!_accountSyncService.isInitialized) return;
    try {
      await _accountSyncService.record(record);
    } catch (error) {
      debugPrint(
        '[MangaSync] Local mutation kept; recorder failed (${error.runtimeType}).',
      );
    }
  }
}
