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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    args = parser.parse_args()
    root = args.root.resolve()

    model = root / "lib/models/anime_franchise_models.dart"
    replace_once(
        model,
        """  List<AnimeFranchiseEntry> get extraEntries => entries
      .where((entry) => entry.group == FranchiseEntryGroup.extra)
      .where((entry) => _runtimeVisibleExtraIds().contains(entry.malId))
      .toList();
""",
        """  List<AnimeFranchiseEntry> get extraEntries {
    final visibleExtraIds = _runtimeVisibleExtraIds();
    return entries
        .where(
          (entry) =>
              entry.group == FranchiseEntryGroup.extra &&
              visibleExtraIds.contains(entry.malId),
        )
        .toList();
  }
""",
    )
    replace_once(
        model,
        """  List<AnimeFranchiseEntry> get runtimeVisibleEntries => [
    ...mainlineEntries,
    ...extraEntries,
  ];

  bool isRuntimeVisibleMalId(int malId) {
    return runtimeVisibleEntries.any((entry) => entry.malId == malId);
  }
""",
        """  List<AnimeFranchiseEntry> get runtimeVisibleEntries {
    final visibleExtraIds = _runtimeVisibleExtraIds();
    return entries
        .where(
          (entry) =>
              entry.group == FranchiseEntryGroup.mainline ||
              (entry.group == FranchiseEntryGroup.extra &&
                  visibleExtraIds.contains(entry.malId)),
        )
        .toList();
  }

  bool isRuntimeVisibleMalId(int malId) {
    var hasExtra = false;
    for (final entry in entries) {
      if (entry.malId != malId) continue;
      if (entry.group == FranchiseEntryGroup.mainline) return true;
      if (entry.group == FranchiseEntryGroup.extra) hasExtra = true;
    }
    return hasExtra && _runtimeVisibleExtraIds().contains(malId);
  }
""",
    )

    unified = root / "lib/screens/unified_episode_list_data_1.dart"
    replace_once(
        unified,
        """  void _applyInitialFranchise() {
    final franchise = widget.initialFranchise;
    if (franchise == null || _visibleFranchiseEntries(franchise).isEmpty) {
      return;
    }

    final entries = _visibleFranchiseEntries(franchise);
""",
        """  void _applyInitialFranchise() {
    final franchise = widget.initialFranchise;
    if (franchise == null) return;

    final entries = _visibleFranchiseEntries(franchise);
    if (entries.isEmpty) return;
""",
    )
    replace_once(
        unified,
        """  int _preferredSelectedMalId(AnimeFranchise franchise) {
    final userSelected = _userSelectedFranchiseMalId;
    if (userSelected != null &&
        userSelected > 0 &&
        _visibleFranchiseEntries(
          franchise,
        ).any((entry) => entry.malId == userSelected)) {
      return userSelected;
    }

    final initial = widget.initialSelectedMalId;
    if (widget.forceInitialSelectedMalId && initial != null && initial > 0) {
      return initial;
    }
    if (initial != null &&
        initial > 0 &&
        _visibleFranchiseEntries(
          franchise,
        ).any((entry) => entry.malId == initial)) {
      return initial;
    }
    return franchise.canonicalMalId;
  }

  List<AnimeFranchiseEntry> _visibleFranchiseEntries(AnimeFranchise franchise) {
    return [...franchise.mainlineEntries, ...franchise.extraEntries];
  }
""",
        """  int _preferredSelectedMalId(AnimeFranchise franchise) {
    final visibleEntries = _visibleFranchiseEntries(franchise);
    final userSelected = _userSelectedFranchiseMalId;
    if (userSelected != null &&
        userSelected > 0 &&
        visibleEntries.any((entry) => entry.malId == userSelected)) {
      return userSelected;
    }

    final initial = widget.initialSelectedMalId;
    if (widget.forceInitialSelectedMalId && initial != null && initial > 0) {
      return initial;
    }
    if (initial != null &&
        initial > 0 &&
        visibleEntries.any((entry) => entry.malId == initial)) {
      return initial;
    }
    return franchise.canonicalMalId;
  }

  List<AnimeFranchiseEntry> _visibleFranchiseEntries(AnimeFranchise franchise) {
    return franchise.runtimeVisibleEntries;
  }
""",
    )

    detail = root / "lib/screens/anime_detail_screen_presentation_5.dart"
    replace_once(
        detail,
        """  Iterable<AnimeFranchiseEntry> _visibleFranchiseEntries(
    AnimeFranchise franchise,
  ) {
    return franchise.mainlineEntries.followedBy(franchise.extraEntries);
  }
""",
        """  Iterable<AnimeFranchiseEntry> _visibleFranchiseEntries(
    AnimeFranchise franchise,
  ) {
    return franchise.runtimeVisibleEntries;
  }
""",
    )


if __name__ == "__main__":
    main()
