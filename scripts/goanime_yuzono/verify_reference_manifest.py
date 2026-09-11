#!/usr/bin/env python3
"""Fail-closed verifier for one downloaded Yuzono reference runtime."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path


SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_FLEXIBLE_ADAPTER_SHA = "c80135339bcff5f7f8c2c2380329dfc155b26232"
EXPECTED_FIELDS = frozenset(
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


def file_sha256(path: Path, label: str) -> str:
    if not path.is_file():
        raise ValueError(f"{label} is missing")
    if path.stat().st_size == 0:
        raise ValueError(f"{label} is empty")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_sha(value: object, label: str) -> str:
    if not isinstance(value, str) or not SHA40.fullmatch(value):
        raise ValueError(f"{label} identity is invalid")
    return value


def require_flexible_adapter_sha(value: object, label: str = "FlexibleAdapter") -> str:
    value = require_sha(value, label)
    if value != EXPECTED_FLEXIBLE_ADAPTER_SHA:
        raise ValueError(f"{label} identity is not the allowed full SHA")
    return value


def verify_manifest(
    *,
    manifest_path: Path,
    app_apk: Path,
    test_apk: Path,
    goanime_source_sha: str,
    anikku_sha: str,
    flexible_adapter_sha: str,
    jdk_major: int,
) -> dict[str, object]:
    if not SHA40.fullmatch(goanime_source_sha):
        raise ValueError("expected GoAnime source identity is invalid")
    if not SHA40.fullmatch(anikku_sha):
        raise ValueError("expected Anikku identity is invalid")
    require_flexible_adapter_sha(flexible_adapter_sha, "expected FlexibleAdapter")
    if jdk_major != 17:
        raise ValueError("expected JDK identity must be 17")
    if not manifest_path.is_file():
        raise ValueError("manifest is missing")
    try:
        payload = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValueError("manifest is not valid JSON") from error
    if not isinstance(payload, dict):
        raise ValueError("manifest root must be an object")
    if frozenset(payload) != EXPECTED_FIELDS:
        raise ValueError("manifest fields are not exact")
    if payload.get("schemaVersion") != 1:
        raise ValueError("manifest schemaVersion is unsupported")
    if payload.get("goAnimeSourceSha") != goanime_source_sha:
        raise ValueError("GoAnime source identity mismatch")
    if payload.get("anikkuSha") != anikku_sha:
        raise ValueError("Anikku identity mismatch")
    if payload.get("flexibleAdapterSha") != flexible_adapter_sha:
        raise ValueError("FlexibleAdapter identity mismatch")
    require_sha(payload.get("goAnimeSourceSha"), "GoAnime source")
    require_sha(payload.get("anikkuSha"), "Anikku")
    require_flexible_adapter_sha(payload.get("flexibleAdapterSha"))
    if not isinstance(payload.get("appApkSha256"), str) or not SHA256.fullmatch(payload["appApkSha256"]):
        raise ValueError("app APK digest is invalid")
    if not isinstance(payload.get("testApkSha256"), str) or not SHA256.fullmatch(payload["testApkSha256"]):
        raise ValueError("test APK digest is invalid")
    if type(payload.get("jdkMajor")) is not int or payload["jdkMajor"] != jdk_major:
        raise ValueError("JDK identity mismatch")
    if type(payload.get("buildAttempt")) is not int or payload["buildAttempt"] < 1:
        raise ValueError("build attempt is invalid")
    if type(payload.get("fallbackUsed")) is not bool:
        raise ValueError("fallbackUsed must be boolean")
    if file_sha256(app_apk, "app APK") != payload["appApkSha256"]:
        raise ValueError("app APK digest mismatch")
    if file_sha256(test_apk, "test APK") != payload["testApkSha256"]:
        raise ValueError("test APK digest mismatch")
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Verify identities and SHA-256 digests for a reference runtime."
    )
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--app-apk", type=Path, required=True)
    parser.add_argument("--test-apk", type=Path, required=True)
    parser.add_argument("--goanime-source-sha", required=True)
    parser.add_argument("--anikku-sha", required=True)
    parser.add_argument("--flexible-adapter-sha", required=True)
    parser.add_argument("--jdk-major", type=int, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        payload = verify_manifest(
            manifest_path=args.manifest,
            app_apk=args.app_apk,
            test_apk=args.test_apk,
            goanime_source_sha=args.goanime_source_sha,
            anikku_sha=args.anikku_sha,
            flexible_adapter_sha=args.flexible_adapter_sha,
            jdk_major=args.jdk_major,
        )
    except ValueError as error:
        print(f"reference manifest verification failed: {error}", file=sys.stderr)
        return 1
    print(
        "reference runtime manifest verified: "
        f"app_sha256={payload['appApkSha256']} "
        f"test_sha256={payload['testApkSha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
