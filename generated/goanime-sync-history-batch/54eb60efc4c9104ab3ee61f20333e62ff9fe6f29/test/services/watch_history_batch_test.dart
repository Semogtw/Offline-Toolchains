import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/models/history_anime.dart';
import 'package:goanime/services/watch_history_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    if (databaseFactoryOrNull == null) databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'watched_episodes_marked': ['3', 'bad', '1', '3', '-2'],
    });
    await WatchHistoryService.debugResetDatabase();
  });

  tearDown(() async {
    await WatchHistoryService.debugResetDatabase();
  });

  test(
    'batch watched markers reuse history fallback and normalize prefs',
    () async {
      final service = WatchHistoryService();
      final history = <HistoryAnime>[
        _history('marked', episode: 9, progress: 0.2),
        _history('fallback', episode: 7, progress: 0.9),
        _history('partial', episode: 2, progress: 0.5),
      ];

      final result = await service.getWatchedEpisodeNumbersForHistory(history);

      expect(result['marked'], {1, 3});
      expect(result['fallback'], {7});
      expect(result['partial'], isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('watched_episodes_marked'), ['1', '3']);
      expect(prefs.getStringList('watched_episodes_fallback'), ['7']);
      expect(prefs.getStringList('watched_episodes_partial'), isNull);
    },
  );
}

HistoryAnime _history(
  String animeId, {
  required int episode,
  required double progress,
}) {
  return HistoryAnime(
    animeId: animeId,
    title: animeId,
    coverImage: '',
    watchedAt: '2026-08-19T00:00:00Z',
    updatedAt: '2026-08-19T00:00:00Z',
    lastEpisode: 'Episode $episode',
    episodeNumber: episode,
    progress: progress,
  );
}
