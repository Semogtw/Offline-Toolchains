import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/l10n/app_localizations.dart';
import 'package:goanime/models/watchlist_anime.dart';
import 'package:goanime/screens/watchlist_screen.dart';
import 'package:goanime/services/watchlist_service.dart';
import 'package:goanime/theme/goanime_theme_tokens.dart';
import 'package:goanime/widgets/load_failure_panel.dart';

void main() {
  testWidgets(
    'refresh keeps watchlist snapshot visible and exposes retry on failure',
    (tester) async {
      final refresh = Completer<List<WatchlistAnime>>();
      final service = _RefreshWatchlistService(refresh);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [GoAnimeThemeTokens.fromCurrentStyle()]),
          locale: const Locale('en', 'US'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: WatchlistScreen(watchlistService: service),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Stable Anime'), findsOneWidget);

      final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final refreshFuture = indicator.onRefresh();
      await tester.pump();

      expect(find.text('Stable Anime'), findsOneWidget);

      refresh.completeError(StateError('refresh failed'));
      await refreshFuture;
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Stable Anime'), findsOneWidget);
      expect(find.byType(LoadFailurePanel), findsOneWidget);
      expect(
        tester.widget<LoadFailurePanel>(find.byType(LoadFailurePanel)).compact,
        isTrue,
      );
    },
  );
}

final class _RefreshWatchlistService extends WatchlistService {
  _RefreshWatchlistService(this.refresh);

  final Completer<List<WatchlistAnime>> refresh;
  int calls = 0;

  @override
  Future<List<WatchlistAnime>> getWatchlist() {
    calls += 1;
    if (calls == 1) {
      return Future<List<WatchlistAnime>>.value([
        WatchlistAnime(
          animeId: '1',
          title: 'Stable Anime',
          coverImage: '',
          myAnimeListUrl: 'https://myanimelist.net/anime/1',
          addedAt: DateTime.utc(2026, 8, 24),
        ),
      ]);
    }
    return refresh.future;
  }
}
