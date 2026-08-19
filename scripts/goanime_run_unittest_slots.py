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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--test-file", type=Path, required=True)
    parser.add_argument("--test-class", required=True)
    parser.add_argument("--reporter", type=Path, required=True)
    parser.add_argument("--context-prefix", required=True)
    args = parser.parse_args()

    test_file = args.test_file.resolve()
    module_name = f"goanime_slot_{test_file.stem}"
    spec = importlib.util.spec_from_file_location(module_name, test_file)
    if spec is None or spec.loader is None:
        raise SystemExit("unable to load test file")
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)

    case = getattr(module, args.test_class, None)
    if not isinstance(case, type) or not issubclass(case, unittest.TestCase):
        raise SystemExit("requested unittest class was not found")

    names = unittest.defaultTestLoader.getTestCaseNames(case)
    if not names:
        raise SystemExit("requested unittest class has no tests")

    for slot, name in enumerate(names, start=1):
        stream = io.StringIO()
        result = unittest.TextTestRunner(stream=stream, verbosity=0).run(case(name))
        if not result.wasSuccessful():
            context = f"{args.context_prefix}-{slot:02d}"
            subprocess.run(
                [
                    sys.executable,
                    str(args.reporter.resolve()),
                    "--state",
                    "failure",
                    "--context",
                    context,
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
