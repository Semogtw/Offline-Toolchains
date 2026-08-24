import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/l10n/app_localizations.dart';
import 'package:goanime/models/jikan_models.dart';
import 'package:goanime/screens/home_screen.dart';
import 'package:goanime/services/jikan_service.dart';
import 'package:goanime/theme/goanime_theme_tokens.dart';
import 'package:goanime/widgets/load_failure_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('failed Anime Home refresh preserves the loaded catalog', (
    tester,
  ) async {
    final service = _SequenceHomeJikanService();

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

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
        home: HomeScreen(jikanService: service),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Stable Anime'), findsWidgets);
    expect(find.byType(LoadFailurePanel), findsNothing);

    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();
    await tester.pumpAndSettle();

    expect(service.homeCalls, 2);
    expect(find.text('Stable Anime'), findsWidgets);
    final warning = tester.widget<LoadFailurePanel>(
      find.byType(LoadFailurePanel),
    );
    expect(warning.compact, isTrue);
  });
}

final class _SequenceHomeJikanService extends JikanService {
  _SequenceHomeJikanService() : super(propagateErrors: true);

  int homeCalls = 0;

  @override
  Future<HomeData?> loadCachedHomeDataSnapshot({
    bool allowExpired = false,
  }) async {
    return null;
  }

  @override
  Future<HomeData> loadHomeData({bool forceRefresh = false}) async {
    homeCalls += 1;
    if (homeCalls > 1) throw StateError('refresh failed');
    return HomeData(
      seasonAnimes: const [],
      todaysReleases: const [],
      topAnimes: [JikanAnime(malId: 1, title: 'Stable Anime', imageUrl: '')],
      actionAnimes: const [],
      romanceAnimes: const [],
      comedyAnimes: const [],
      fantasyAnimes: const [],
    );
  }
}
