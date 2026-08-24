import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/l10n/app_localizations.dart';
import 'package:goanime/screens/manga/manga_library_screen.dart';
import 'package:goanime/services/manga/manga_availability_models.dart';
import 'package:goanime/services/manga/manga_browse_data_source.dart';
import 'package:goanime/services/manga/storage/manga_library_repository.dart';
import 'package:goanime/theme/app_theme.dart';
import 'package:goanime/theme/goanime_theme_tokens.dart';
import 'package:goanime/widgets/manga/manga_load_error_view.dart';
import 'package:goanime_core/goanime_core.dart';

void main() {
  testWidgets('failed refresh preserves library snapshot and exposes retry', (
    tester,
  ) async {
    final refresh = Completer<List<MangaBrowseItem>>();
    final source = _RefreshLibraryDataSource(
      initial: <MangaBrowseItem>[
        _item('stable', 'Stable Work', MangaLibraryStatus.reading),
      ],
      refresh: refresh,
    );

    await _pump(tester, MangaLibraryScreen(dataSource: source));
    await tester.pumpAndSettle();

    expect(find.text('Stable Work'), findsOneWidget);
    expect(find.byType(MangaLoadErrorView), findsNothing);

    final indicator = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final refreshFuture = indicator.onRefresh();
    await tester.pump();

    refresh.completeError(StateError('refresh failed'));
    await refreshFuture;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Stable Work'), findsOneWidget);
    expect(find.byType(MangaLoadErrorView), findsOneWidget);
    expect(
      tester
          .widget<MangaLoadErrorView>(find.byType(MangaLoadErrorView))
          .compact,
      isTrue,
    );
  });
}

final class _RefreshLibraryDataSource implements MangaBrowseDataSource {
  _RefreshLibraryDataSource({required this.initial, required this.refresh});

  final List<MangaBrowseItem> initial;
  final Completer<List<MangaBrowseItem>> refresh;
  int libraryCalls = 0;

  @override
  Future<MangaHomeSnapshot> loadHome() async => const MangaHomeSnapshot();

  @override
  Future<List<MangaBrowseItem>> loadCategories() async => const [];

  @override
  Future<List<MangaBrowseItem>> loadLibrary() {
    libraryCalls += 1;
    if (libraryCalls == 1) return Future<List<MangaBrowseItem>>.value(initial);
    return refresh.future;
  }
}

MangaBrowseItem _item(String workId, String title, MangaLibraryStatus status) {
  return MangaBrowseItem(
    availability: MangaAvailabilityRecord(
      work: MangaWork(workId: workId, canonicalTitle: title),
      sourceLinks: <MangaSourceLink>[
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
      evidence: <MangaReadabilityEvidence>[
        MangaReadabilityEvidence(
          workId: workId,
          sourceId: 'ptbr.local',
          mangaId: '$workId-source',
          sampleChapterId: 'chapter-1',
          contentKind: MangaContentKind.imageSequence,
          verifiedAt: DateTime.utc(2026, 8, 24),
        ),
      ],
    ),
    libraryStatus: status,
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
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.darkTheme.copyWith(
        extensions: <ThemeExtension<dynamic>>[
          GoAnimeThemeTokens.fromCurrentStyle(),
        ],
      ),
      home: child,
    ),
  );
}
