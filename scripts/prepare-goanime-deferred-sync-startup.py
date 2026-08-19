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
    sync = root / 'lib/services/user_sync_service.dart'
    bootstrap = root / 'lib/app/bootstrap.dart'

    replace_once(
        sync,
        '  Future<void> initialize({bool enabledByDefault = true}) async {',
        '  Future<void> initialize({\n'
        '    bool enabledByDefault = true,\n'
        '    bool deferAnonymousSignIn = false,\n'
        '  }) async {',
    )
    replace_once(
        sync,
        '    await signInAnonymously();\n  }\n\n  Future<void> setEnabled(bool enabled) async {',
        '    if (deferAnonymousSignIn) {\n'
        '      unawaited(signInAnonymously());\n'
        '      return;\n'
        '    }\n'
        '    await signInAnonymously();\n'
        '  }\n\n'
        '  Future<void> setEnabled(bool enabled) async {',
    )
    replace_once(
        bootstrap,
        '  await userSyncService.initialize();',
        '  await userSyncService.initialize(deferAnonymousSignIn: true);',
    )


if __name__ == '__main__':
    main()
