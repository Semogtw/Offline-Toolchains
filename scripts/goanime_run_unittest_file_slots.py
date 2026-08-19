#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import io
import os
import subprocess
import sys
import unittest
from pathlib import Path


def flatten(suite: unittest.TestSuite):
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from flatten(item)
        else:
            yield item


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-file", type=Path, required=True)
    parser.add_argument("--reporter", type=Path, required=True)
    parser.add_argument("--context-prefix", required=True)
    args = parser.parse_args()

    test_file = args.test_file.resolve()
    module_name = f"goanime_slots_{test_file.stem}"
    spec = importlib.util.spec_from_file_location(module_name, test_file)
    if spec is None or spec.loader is None:
        raise SystemExit("unable to load test file")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)

    tests = list(flatten(unittest.defaultTestLoader.loadTestsFromModule(module)))
    tests.sort(key=lambda test: test.id())
    if not tests:
        raise SystemExit("test file has no unittest cases")

    for slot, test in enumerate(tests, start=1):
        stream = io.StringIO()
        result = unittest.TextTestRunner(stream=stream, verbosity=0).run(test)
        if not result.wasSuccessful():
            subprocess.run(
                [
                    sys.executable,
                    str(args.reporter.resolve()),
                    "--state",
                    "failure",
                    "--context",
                    f"{args.context_prefix}-{slot:02d}",
                ],
                env=os.environ.copy(),
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
