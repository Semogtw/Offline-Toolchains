#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import time


def _commands(browser: str) -> list[list[str]]:
    commands = [[sys.executable, "-m", "patchright", "install", browser]]
    executable = shutil.which("patchright")
    if executable:
        cli = [executable, "install", browser]
        if cli != commands[0]:
            commands.append(cli)
    return commands


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--browser", default="chromium")
    parser.add_argument("--attempts", type=int, default=3)
    parser.add_argument("--delay-seconds", type=float, default=5.0)
    args = parser.parse_args()

    if args.attempts <= 0:
        raise SystemExit("--attempts must be greater than zero")
    if args.delay_seconds < 0:
        raise SystemExit("--delay-seconds cannot be negative")

    commands = _commands(args.browser)
    for attempt in range(1, args.attempts + 1):
        for command in commands:
            result = subprocess.run(command, check=False)
            if result.returncode == 0:
                print(
                    f"Patchright {args.browser} installation ready "
                    f"(attempt {attempt})."
                )
                return 0
        if attempt < args.attempts:
            print(
                f"Patchright {args.browser} install attempt {attempt} failed; retrying.",
                file=sys.stderr,
            )
            time.sleep(args.delay_seconds)

    print(
        f"Patchright {args.browser} installation failed after {args.attempts} attempts.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
