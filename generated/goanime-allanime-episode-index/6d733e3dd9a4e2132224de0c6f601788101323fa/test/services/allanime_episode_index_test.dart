import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/services/allanime_service.dart';

void main() {
  test('episode info index keeps the first matching payload per number', () {
    final index = AllAnimeService.indexEpisodeInfosForTesting([
      {'episodeIdNum': 1, 'notes': 'first'},
      {'episodeIdNum': '2', 'notes': 'second'},
      {'episodeIdNum': 1, 'notes': 'duplicate'},
      {'notes': 'missing number'},
      null,
    ]);

    expect(index.keys, containsAll(<String>['1', '2']));
    expect(index.length, 2);
    expect(index['1']?['notes'], 'first');
    expect(index['2']?['notes'], 'second');
  });
}
