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


if __name__ == '__main__':
    main()
