#!/usr/bin/env python3
from pathlib import Path
import argparse


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    args = parser.parse_args()
    path = args.root / 'lib/services/dynamic_availability_cache.dart'
    text = path.read_text(encoding='utf-8')
    old = """    final normalizedProvider = _normalizeProviderId(providerId);
    for (final title in titles) {
      for (final key in TitleNormalizer.keysForTitle(title)) {
        for (final entry in entries) {
"""
    new = """    final normalizedProvider = _normalizeProviderId(providerId);
    final freshEntries = entries;
    if (freshEntries.isEmpty) return false;
    for (final title in titles) {
      for (final key in TitleNormalizer.keysForTitle(title)) {
        for (final entry in freshEntries) {
"""
    if text.count(old) != 1:
        raise SystemExit(f'{path}: expected exactly one hot-path target')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


if __name__ == '__main__':
    main()
