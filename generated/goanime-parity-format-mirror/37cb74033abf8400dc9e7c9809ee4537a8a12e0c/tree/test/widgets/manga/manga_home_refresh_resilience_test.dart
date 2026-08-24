import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/l10n/app_localizations.dart';
import 'package:goanime/screens/manga/manga_home_screen.dart';
import 'package:goanime/services/manga/manga_availability_models.dart';
import 'package:goanime/services/manga/manga_browse_data_source.dart';
import 'package:goanime/theme/app_theme.dart';
import 'package:goanime/theme/goanime_theme_tokens.dart';
import 'package:goanime/widgets/manga/manga_load_error_view.dart';
import 'package:goanime_core/goanime_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  testWidgets('failed refresh keeps the loaded Manga Home snapshot visible', (
    tester,
  ) async {
    final source = _SequenceBrowseDataSource([
      MangaHomeSnapshot(
        availableCatalog: [_item('mw_catalog', 'Catalog Work')],
      ),
      StateError('refresh failed'),
    ]);

    await _pump(tester, MangaHomeScreen(dataSource: source));
    await tester.pumpAndSettle();

    expect(find.text('Catalog Work'), findsOneWidget);
    expect(find.byType(MangaLoadErrorView), findsNothing);

    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    await refresh.onRefresh();
    await tester.pumpAndSettle();

    expect(source.homeCalls, 2);
    expect(find.text('Catalog Work'), findsOneWidget);
    expect(find.byType(MangaLoadErrorView), findsOneWidget);
  });
}

final class _SequenceBrowseDataSource implements MangaBrowseDataSource {
  _SequenceBrowseDataSource(this._homeResponses);

  final List<Object> _homeResponses;
  int homeCalls = 0;

  @override
  Future<MangaHomeSnapshot> loadHome() async {
    final index = homeCalls;
    homeCalls += 1;
    final response =
        _homeResponses[index < _homeResponses.length
            ? index
            : _homeResponses.length - 1];
    if (response is MangaHomeSnapshot) return response;
    throw response;
  }

  @override
  Future<List<MangaBrowseItem>> loadCategories() async => const [];

  @override
  Future<List<MangaBrowseItem>> loadLibrary() async => const [];
}

MangaBrowseItem _item(String workId, String title) {
  return MangaBrowseItem(availability: _record(workId, title));
}

MangaAvailabilityRecord _record(String workId, String title) {
  return MangaAvailabilityRecord(
    work: MangaWork(workId: workId, canonicalTitle: title),
    sourceLinks: [
      MangaSourceLink(
        workId: workId,
        occurrence: MangaSourceOccurrence(
          sourceId: 'ptbr.local',
          mangaId: '$workId-source',
          title: title,
        ),
        matchConfidence: 1,
      ),
    ],
    evidence: [
      MangaReadabilityEvidence(
        workId: workId,
        sourceId: 'ptbr.local',
        mangaId: '$workId-source',
        sampleChapterId: 'chapter-1',
        contentKind: MangaContentKind.imageSequence,
        verifiedAt: DateTime.utc(2026, 8, 24),
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(const Size(900, 1100));
  addTearDown(() async {
    tester.view.reset();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en', 'US'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.darkTheme.copyWith(
        extensions: [GoAnimeThemeTokens.fromCurrentStyle()],
      ),
      home: child,
    ),
  );
}
