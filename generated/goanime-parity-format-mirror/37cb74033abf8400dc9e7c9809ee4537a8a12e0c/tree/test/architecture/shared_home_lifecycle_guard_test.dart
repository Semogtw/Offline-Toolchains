import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Manga and Anime Home consume the shared lifecycle controller', () {
    final mangaHome = File(
      'lib/screens/manga/manga_home_screen.dart',
    ).readAsStringSync();
    final animeHome = File('lib/screens/home_screen.dart').readAsStringSync();

    expect(mangaHome, contains('HomeSnapshotController<MangaHomeSnapshot>'));
    expect(mangaHome, isNot(contains('FutureBuilder<MangaHomeSnapshot>')));

    expect(animeHome, contains('HomeSnapshotController<HomeData>'));
    expect(animeHome, contains('AnimeHomeSnapshotAdapter'));
  });
}
