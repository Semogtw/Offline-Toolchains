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
    service = root / 'lib/services/allanime_service.dart'

    marker = """  static const String _allAnimeReferer = 'https://allmanga.to';
"""
    helper = """  static Map<String, Map<String, dynamic>> _indexEpisodeInfos(
    Iterable<dynamic> episodeInfos,
  ) {
    final index = <String, Map<String, dynamic>>{};
    for (final rawInfo in episodeInfos) {
      final info = jsonMap(rawInfo);
      final episodeNumber = info?['episodeIdNum']?.toString();
      if (info == null || episodeNumber == null || episodeNumber.isEmpty) {
        continue;
      }
      index.putIfAbsent(episodeNumber, () => info);
    }
    return index;
  }

  @visibleForTesting
  static Map<String, Map<String, dynamic>> indexEpisodeInfosForTesting(
    Iterable<dynamic> episodeInfos,
  ) => _indexEpisodeInfos(episodeInfos);

"""
    replace_once(service, marker, helper + marker)

    replace_once(
        service,
        """          final episodeInfos = jsonList(show['episodeInfos']);
          final availableDetail = jsonMap(show['availableEpisodesDetail']);
""",
        """          final episodeInfos = jsonList(show['episodeInfos']);
          final episodeInfoByNumber = _indexEpisodeInfos(episodeInfos);
          final availableDetail = jsonMap(show['availableEpisodesDetail']);
""",
    )

    replace_once(
        service,
        """            // Find matching episode info
            final episodeInfo =
                episodeInfos.firstWhere(
                      (info) =>
                          jsonMap(info)?['episodeIdNum']?.toString() ==
                          episodeNum,
                      orElse: () => <String, dynamic>{},
                    )
                    as Map<String, dynamic>;
""",
        """            final episodeInfo =
                episodeInfoByNumber[episodeNum] ?? <String, dynamic>{};
""",
    )

    test = root / 'test/services/allanime_episode_index_test.dart'
    test.write_text("""import 'package:flutter_test/flutter_test.dart';
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
""", encoding='utf-8')


if __name__ == '__main__':
    main()
