import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Manga Library and Anime Watchlist consume shared Library lifecycle',
    () {
      final mangaLibrary = File(
        'lib/screens/manga/manga_library_screen.dart',
      ).readAsStringSync();
      final animeWatchlist = File(
        'lib/screens/watchlist_screen.dart',
      ).readAsStringSync();

      expect(
        mangaLibrary,
        contains('LibrarySnapshotController<MangaBrowseItem>'),
      );
      expect(mangaLibrary, contains('MangaLibrarySnapshotAdapter'));
      expect(
        mangaLibrary,
        isNot(contains('FutureBuilder<List<MangaBrowseItem>>')),
      );

      expect(
        animeWatchlist,
        contains('LibrarySnapshotController<WatchlistAnime>'),
      );
      expect(animeWatchlist, contains('AnimeWatchlistSnapshotAdapter'));
      expect(animeWatchlist, isNot(contains('_loadGeneration')));
    },
  );
}
