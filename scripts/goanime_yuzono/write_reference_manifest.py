#!/usr/bin/env python3
"""Write the exact, sanitized identity manifest for one audit runtime."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_FLEXIBLE_ADAPTER_SHA = "c80135339bcff5f7f8c2c2380329dfc155b26232"
MANIFEST_FIELDS = frozenset(
    {
        "schemaVersion",
        "goAnimeSourceSha",
        "anikkuSha",
        "flexibleAdapterSha",
        "appApkSha256",
        "testApkSha256",
        "jdkMajor",
        "buildAttempt",
        "fallbackUsed",
    }
)


def _sha40(value: str, label: str) -> str:
    if not SHA40.fullmatch(value):
        raise ValueError(f"{label} must be a lowercase 40-hex SHA")
    return value


def _flexible_adapter_sha(value: str) -> str:
    value = _sha40(value, "flexibleAdapterSha")
    if value != EXPECTED_FLEXIBLE_ADAPTER_SHA:
        raise ValueError("flexibleAdapterSha is not the allowed full SHA")
    return value


def sha256_file(path: Path, label: str) -> str:
    if not path.is_file():
        raise ValueError(f"{label} is missing")
    if path.stat().st_size == 0:
        raise ValueError(f"{label} is empty")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    value = digest.hexdigest()
    if not SHA256.fullmatch(value):
        raise ValueError(f"{label} digest is invalid")
    return value


def build_manifest(
    *,
    goanime_source_sha: str,
    anikku_sha: str,
    flexible_adapter_sha: str,
    app_apk: Path,
    test_apk: Path,
    jdk_major: int,
    build_attempt: int,
    fallback_used: bool,
) -> dict[str, object]:
    if jdk_major != 17:
        raise ValueError("jdkMajor must be 17")
    if build_attempt < 1:
        raise ValueError("buildAttempt must be positive")
    if type(fallback_used) is not bool:
        raise ValueError("fallbackUsed must be boolean")
    return {
        "schemaVersion": 1,
        "goAnimeSourceSha": _sha40(goanime_source_sha, "goAnimeSourceSha"),
        "anikkuSha": _sha40(anikku_sha, "anikkuSha"),
        "flexibleAdapterSha": _flexible_adapter_sha(flexible_adapter_sha),
        "appApkSha256": sha256_file(app_apk, "app APK"),
        "testApkSha256": sha256_file(test_apk, "test APK"),
        "jdkMajor": jdk_major,
        "buildAttempt": build_attempt,
        "fallbackUsed": fallback_used,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Write a sanitized immutable Yuzono reference-runtime manifest."
    )
    parser.add_argument("--output", type=Path, required=True, help="manifest JSON path")
    parser.add_argument("--goanime-source-sha", required=True)
    parser.add_argument("--anikku-sha", required=True)
    parser.add_argument("--flexible-adapter-sha", required=True)
    parser.add_argument("--app-apk", type=Path, required=True)
    parser.add_argument("--test-apk", type=Path, required=True)
    parser.add_argument("--jdk-major", type=int, required=True)
    parser.add_argument("--build-attempt", type=int, required=True)
    fallback = parser.add_mutually_exclusive_group(required=True)
    fallback.add_argument("--fallback-used", action="store_true")
    fallback.add_argument("--no-fallback-used", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        payload = build_manifest(
            goanime_source_sha=args.goanime_source_sha,
            anikku_sha=args.anikku_sha,
            flexible_adapter_sha=args.flexible_adapter_sha,
            app_apk=args.app_apk,
            test_apk=args.test_apk,
            jdk_major=args.jdk_major,
            build_attempt=args.build_attempt,
            fallback_used=args.fallback_used,
        )
    except ValueError as error:
        print(f"reference manifest rejected: {error}")
        return 2
    if frozenset(payload) != MANIFEST_FIELDS:
        print("reference manifest rejected: schema fields are not exact")
        return 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print("reference runtime manifest written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
