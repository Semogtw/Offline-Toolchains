#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


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


def apply_image_decode(root: Path) -> None:
    helper = root / "lib/utils/image_cache_dimensions.dart"
    create_exact(
        helper,
        """int? imageCachePixelDimension(\n"
        "  double logicalPixels,\n"
        "  double devicePixelRatio,\n"
        ") {\n"
        "  if (!logicalPixels.isFinite || logicalPixels <= 0) return null;\n"
        "  if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) return null;\n"
        "  return (logicalPixels * devicePixelRatio).ceil();\n"
        "}\n""".replace('"\n        "', ""),
    )

    legacy = root / "lib/widgets/anime_card.dart"
    replace_once(
        legacy,
        "import '../theme/app_colors.dart';\nimport 'modern_theme.dart';",
        "import '../theme/app_colors.dart';\nimport '../utils/image_cache_dimensions.dart';\nimport 'modern_theme.dart';",
    )
    replace_once(
        legacy,
        "      return _networkImage(fallbackUrl);",
        "      return _networkImage(context, fallbackUrl);",
    )
    replace_once(
        legacy,
        "        return _networkImage(imageUrl);",
        "        return _networkImage(context, imageUrl);",
    )
    replace_once(
        legacy,
        """  Widget _networkImage(String imageUrl) {\n"
        "    return CachedNetworkImage(\n"
        "      imageUrl: imageUrl,\n"
        "      width: width,\n"
        "      height: height,\n"
        "      fit: BoxFit.cover,\n"
        "      filterQuality: FilterQuality.high,""".replace('"\n        "', ""),
        """  Widget _networkImage(BuildContext context, String imageUrl) {\n"
        "    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);\n"
        "    return CachedNetworkImage(\n"
        "      imageUrl: imageUrl,\n"
        "      width: width,\n"
        "      height: height,\n"
        "      memCacheWidth: imageCachePixelDimension(width, devicePixelRatio),\n"
        "      memCacheHeight: imageCachePixelDimension(height, devicePixelRatio),\n"
        "      fit: BoxFit.cover,\n"
        "      filterQuality: FilterQuality.high,""".replace('"\n        "', ""),
    )

    modern = root / "lib/widgets/anime/goanime_anime_card.dart"
    replace_once(
        modern,
        "import '../../theme/goanime_theme_tokens.dart';",
        "import '../../theme/goanime_theme_tokens.dart';\nimport '../../utils/image_cache_dimensions.dart';",
    )
    replace_once(
        modern,
        """    return CachedNetworkImage(\n"
        "      imageUrl: imageUrl,\n"
        "      width: double.infinity,\n"
        "      height: double.infinity,\n"
        "      fit: BoxFit.cover,\n"
        "      placeholder: (context, url) => const _ArtworkFallback(),\n"
        "      errorWidget: (context, url, error) => const _ArtworkFallback(),\n"
        "    );""".replace('"\n        "', ""),
        """    return LayoutBuilder(\n"
        "      builder: (context, constraints) {\n"
        "        final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);\n"
        "        return CachedNetworkImage(\n"
        "          imageUrl: imageUrl,\n"
        "          width: double.infinity,\n"
        "          height: double.infinity,\n"
        "          memCacheWidth: imageCachePixelDimension(\n"
        "            constraints.maxWidth,\n"
        "            devicePixelRatio,\n"
        "          ),\n"
        "          memCacheHeight: imageCachePixelDimension(\n"
        "            constraints.maxHeight,\n"
        "            devicePixelRatio,\n"
        "          ),\n"
        "          fit: BoxFit.cover,\n"
        "          placeholder: (context, url) => const _ArtworkFallback(),\n"
        "          errorWidget: (context, url, error) => const _ArtworkFallback(),\n"
        "        );\n"
        "      },\n"
        "    );""".replace('"\n        "', ""),
    )

    test_file = root / "test/utils/image_cache_dimensions_test.dart"
    create_exact(
        test_file,
        """import 'package:flutter_test/flutter_test.dart';\n"
        "import 'package:goanime/utils/image_cache_dimensions.dart';\n"
        "\n"
        "void main() {\n"
        "  test('converts logical image size to physical cache pixels', () {\n"
        "    expect(imageCachePixelDimension(120, 2.625), 315);\n"
        "    expect(imageCachePixelDimension(180, 3), 540);\n"
        "  });\n"
        "\n"
        "  test('rejects invalid cache dimensions', () {\n"
        "    expect(imageCachePixelDimension(0, 2), isNull);\n"
        "    expect(imageCachePixelDimension(-1, 2), isNull);\n"
        "    expect(imageCachePixelDimension(double.infinity, 2), isNull);\n"
        "    expect(imageCachePixelDimension(120, 0), isNull);\n"
        "    expect(imageCachePixelDimension(120, double.nan), isNull);\n"
        "  });\n"
        "}\n""".replace('"\n        "', ""),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--stage", required=True, choices=["image-decode"])
    args = parser.parse_args()
    root = args.root.resolve()

    if args.stage == "image-decode":
        apply_image_decode(root)


if __name__ == "__main__":
    main()
