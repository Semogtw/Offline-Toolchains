#!/usr/bin/env python3
from pathlib import Path
import argparse


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise SystemExit(f'{path}: expected exactly one target')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    root = args.root
    home = root / 'lib/screens/home_screen.dart'

    replace_once(
        home,
        """              // Conteúdo principal
              SliverToBoxAdapter(
                child: Column(
                  children: [
""",
        """              // Conteúdo principal. Keep vertical sections in a sliver so
              // distant rows are not laid out/mounted during the first frame.
              SliverList(
                delegate: SliverChildListDelegate([
""",
    )
    replace_once(
        home,
        """                    SizedBox(height: 48),
                  ],
                ),
              ),
""",
        """                    SizedBox(height: 48),
                  ]),
              ),
""",
    )

    test = root / 'test/widgets/home_lazy_sections_test.dart'
    test.write_text("""import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/l10n/app_localizations.dart';
import 'package:goanime/models/franchise_availability_cache_models.dart';
import 'package:goanime/models/jikan_models.dart';
import 'package:goanime/screens/home_screen.dart';
import 'package:goanime/services/franchise_availability_cache_service.dart';
import 'package:goanime/services/jikan_service.dart';
import 'package:goanime/theme/goanime_theme_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (databaseFactoryOrNull == null) databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FranchiseAvailabilityCacheService.debugSetPayloadForTesting(
      FranchiseAvailabilityCachePayload.empty(),
    );
  });

  tearDown(() async {
    await FranchiseAvailabilityCacheService.debugResetForTesting();
  });

  testWidgets('Home mounts distant catalog rows only near the viewport', (
    tester,
  ) async {
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
        home: HomeScreen(jikanService: _AllSectionsJikanService()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('Fantasy Item'), findsNothing);

    for (var i = 0; i < 8; i++) {
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -500),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Fantasy Item'), findsOneWidget);
  });
}

class _AllSectionsJikanService extends JikanService {
  _AllSectionsJikanService() : super(propagateErrors: true);

  @override
  Future<HomeData?> loadCachedHomeDataSnapshot({
    bool allowExpired = false,
  }) async => null;

  @override
  Future<HomeData> loadHomeData({bool forceRefresh = false}) async {
    return HomeData(
      seasonAnimes: [_anime('Season Item')],
      todaysReleases: [_anime('Today Item')],
      topAnimes: [_anime('Top Item')],
      actionAnimes: [_anime('Action Item')],
      romanceAnimes: [_anime('Romance Item')],
      comedyAnimes: [_anime('Comedy Item')],
      fantasyAnimes: [_anime('Fantasy Item')],
    );
  }
}

JikanAnime _anime(String title) {
  return JikanAnime(malId: 0, title: title, imageUrl: '');
}
""", encoding='utf-8')


if __name__ == '__main__':
    main()
