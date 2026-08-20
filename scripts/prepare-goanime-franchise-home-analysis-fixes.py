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

    home = root / 'lib/screens/home_screen_data.dart'
    replace_once(
        home,
        """    final provider = CachedNetworkImageProvider(imageUrl);
    final imageProvider = cacheWidth == null && cacheHeight == null
        ? provider
        : ResizeImage(provider, width: cacheWidth, height: cacheHeight);
""",
        """    final provider = CachedNetworkImageProvider(imageUrl);
    final ImageProvider<Object> imageProvider =
        cacheWidth == null && cacheHeight == null
        ? provider
        : ResizeImage(provider, width: cacheWidth, height: cacheHeight);
""",
    )

    franchise = root / 'lib/services/franchise_availability_database_service.dart'
    replace_once(
        franchise,
        """    return {
      for (final entry in franchiseIdByMalId.entries)
        if (franchiseById[entry.value] case final franchise?)
          entry.key: franchise,
    };
""",
        """    final result = <int, AnimeFranchise>{};
    for (final entry in franchiseIdByMalId.entries) {
      final franchise = franchiseById[entry.value];
      if (franchise != null) result[entry.key] = franchise;
    }
    return result;
""",
    )


if __name__ == '__main__':
    main()
