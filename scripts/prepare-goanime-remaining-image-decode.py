#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import argparse


def read_preserving_newlines(path: Path) -> str:
    with path.open("r", encoding="utf-8", newline="") as stream:
        return stream.read()


def write_preserving_newlines(path: Path, text: str) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        stream.write(text)


def replace_once(path: Path, old: str, new: str) -> None:
    text = read_preserving_newlines(path)
    newline = "\r\n" if "\r\n" in text else "\n"
    old = old.replace("\n", newline)
    new = new.replace("\n", newline)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one replacement target, found {count}")
    write_preserving_newlines(path, text.replace(old, new, 1))


def create_exact(path: Path, content: str) -> None:
    if path.exists():
        current = read_preserving_newlines(path).replace("\r\n", "\n")
        if current == content:
            return
        raise SystemExit(f"{path}: refusing to overwrite unexpected existing file")
    path.parent.mkdir(parents=True, exist_ok=True)
    write_preserving_newlines(path, content)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    root = args.root.resolve()

    unified_screen = root / "lib/screens/unified_episode_list_screen.dart"
    replace_once(
        unified_screen,
        "import '../utils/episode_ranges.dart';\nimport '../utils/responsive.dart';",
        "import '../utils/episode_ranges.dart';\nimport '../utils/image_cache_dimensions.dart';\nimport '../utils/responsive.dart';",
    )

    unified_presentation = root / "lib/screens/unified_episode_list_presentation_6.dart"
    replace_once(
        unified_presentation,
        "    return CachedNetworkImage(\n      imageUrl: imageUrl,\n      width: width,\n      height: height,\n      fit: BoxFit.cover,",
        "    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);\n    return CachedNetworkImage(\n      imageUrl: imageUrl,\n      width: width,\n      height: height,\n      memCacheWidth: imageCachePixelDimension(width, devicePixelRatio),\n      memCacheHeight: imageCachePixelDimension(height, devicePixelRatio),\n      fit: BoxFit.cover,",
    )

    downloads_screen = root / "lib/screens/downloads_screen.dart"
    replace_once(
        downloads_screen,
        "import '../utils/responsive.dart';\nimport '../widgets/foundation/goanime_responsive_content.dart';",
        "import '../utils/image_cache_dimensions.dart';\nimport '../utils/responsive.dart';\nimport '../widgets/foundation/goanime_responsive_content.dart';",
    )

    downloads_cards = root / "lib/screens/downloads_screen_cards.dart"
    replace_once(
        downloads_cards,
        "                      imageUrl: widget.thumbnailUrl,\n                      width: 60,\n                      height: 90,\n                      fit: BoxFit.cover,",
        "                      imageUrl: widget.thumbnailUrl,\n                      width: 60,\n                      height: 90,\n                      memCacheWidth: imageCachePixelDimension(\n                        60,\n                        MediaQuery.devicePixelRatioOf(context),\n                      ),\n                      memCacheHeight: imageCachePixelDimension(\n                        90,\n                        MediaQuery.devicePixelRatioOf(context),\n                      ),\n                      fit: BoxFit.cover,",
    )

    downloads_editorial = root / "lib/screens/downloads_screen_editorial_cards.dart"
    replace_once(
        downloads_editorial,
        "              imageUrl: download.thumbnailUrl,\n              width: 64,\n              height: 94,\n              fit: BoxFit.cover,",
        "              imageUrl: download.thumbnailUrl,\n              width: 64,\n              height: 94,\n              memCacheWidth: imageCachePixelDimension(\n                64,\n                MediaQuery.devicePixelRatioOf(context),\n              ),\n              memCacheHeight: imageCachePixelDimension(\n                94,\n                MediaQuery.devicePixelRatioOf(context),\n              ),\n              fit: BoxFit.cover,",
    )
    replace_once(
        downloads_editorial,
        "                      imageUrl: widget.thumbnailUrl,\n                      width: 54,\n                      height: 78,\n                      fit: BoxFit.cover,",
        "                      imageUrl: widget.thumbnailUrl,\n                      width: 54,\n                      height: 78,\n                      memCacheWidth: imageCachePixelDimension(\n                        54,\n                        MediaQuery.devicePixelRatioOf(context),\n                      ),\n                      memCacheHeight: imageCachePixelDimension(\n                        78,\n                        MediaQuery.devicePixelRatioOf(context),\n                      ),\n                      fit: BoxFit.cover,",
    )

    continue_card = root / "lib/widgets/home/goanime_continue_watching_card.dart"
    replace_once(
        continue_card,
        "import '../../theme/goanime_theme_tokens.dart';",
        "import '../../theme/goanime_theme_tokens.dart';\nimport '../../utils/image_cache_dimensions.dart';",
    )
    replace_once(
        continue_card,
        "    return CachedNetworkImage(\n      imageUrl: imageUrl,\n      fit: BoxFit.cover,\n      placeholder: (context, url) => ColoredBox(color: tokens.surfaceRaised),\n      errorWidget: (context, url, error) => ColoredBox(\n        color: tokens.surfaceRaised,\n        child: Icon(Icons.movie_outlined, color: tokens.textDisabled),\n      ),\n    );",
        "    return LayoutBuilder(\n      builder: (context, constraints) {\n        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);\n        return CachedNetworkImage(\n          imageUrl: imageUrl,\n          memCacheWidth: imageCachePixelDimension(\n            constraints.maxWidth,\n            devicePixelRatio,\n          ),\n          memCacheHeight: imageCachePixelDimension(\n            constraints.maxHeight,\n            devicePixelRatio,\n          ),\n          fit: BoxFit.cover,\n          placeholder: (context, url) =>\n              ColoredBox(color: tokens.surfaceRaised),\n          errorWidget: (context, url, error) => ColoredBox(\n            color: tokens.surfaceRaised,\n            child: Icon(Icons.movie_outlined, color: tokens.textDisabled),\n          ),\n        );\n      },\n    );",
    )

    create_exact(
        root / "test/widgets/remaining_image_cache_bounds_test.dart",
        """import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goanime/widgets/home/goanime_continue_watching_card.dart';

void main() {
  testWidgets('continue watching bounds decoded artwork to physical card size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoAnimeContinueWatchingCard(
            imageUrl: 'https://cdn.example/continue.jpg',
            title: 'Anime',
            subtitle: 'Episode 1',
            progress: 0.5,
            progressLabel: '50%',
            onPressed: () {},
            width: 300,
            height: 158,
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(image.memCacheWidth, 600);
    expect(image.memCacheHeight, 316);
  });

  test('episode and downloads list images keep explicit decode bounds', () {
    final episodeSource = File(
      'lib/screens/unified_episode_list_presentation_6.dart',
    ).readAsStringSync();
    final downloadCards = File(
      'lib/screens/downloads_screen_cards.dart',
    ).readAsStringSync();
    final downloadEditorial = File(
      'lib/screens/downloads_screen_editorial_cards.dart',
    ).readAsStringSync();

    expect(episodeSource, contains('memCacheWidth: imageCachePixelDimension'));
    expect(episodeSource, contains('memCacheHeight: imageCachePixelDimension'));
    expect(downloadCards, contains('memCacheWidth: imageCachePixelDimension'));
    expect(downloadCards, contains('memCacheHeight: imageCachePixelDimension'));
    expect(
      'memCacheWidth: imageCachePixelDimension'.allMatches(downloadEditorial),
      hasLength(2),
    );
    expect(
      'memCacheHeight: imageCachePixelDimension'.allMatches(downloadEditorial),
      hasLength(2),
    );
  });
}
""",
    )


if __name__ == "__main__":
    main()
