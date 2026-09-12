#!/usr/bin/env python3
"""Independently validate the live canary boundary before a full audit.

The canary is accepted only when the shared runtime identity is valid, every
selected provider has an identity-bearing v3 receipt, the structural control
reaches provider code, and at least one candidate reaches provider code with
terminal-media observations. A provider marked ready must also carry all
terminal-media observations.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MODULE = re.compile(r"^[a-z0-9._-]{1,80}$")
PACKAGE = re.compile(r"^[A-Za-z0-9_.]{3,200}$")
CLASS = re.compile(r"^[A-Za-z_][A-Za-z0-9_$]*(?:\.[A-Za-z_][A-Za-z0-9_$]*)+$")
SAFE_TEXT = re.compile(r"^[^\x00\r\n|]{0,400}$")

FLEXIBLE_ADAPTER_SHA = "c80135339bcff5f7f8c2c2380329dfc155b26232"
STATUSES = frozenset(
    {"ready", "partial", "blocked", "broken", "unsupported", "not-anime", "unknown"}
)
CHECKPOINT_STATUSES = STATUSES | {"pending"}
STAGES = frozenset(
    {"discovered", "reachable", "catalog", "identity", "episodes", "player", "stream", "classified"}
)
LANGUAGES = frozenset({"sub", "dub", "mixed", "unknown"})
TERMINATIONS = frozenset(
    {"natural-end", "empty-page", "empty-catalog", "safety-ceiling", "error", "unknown"}
)
CHECKPOINT_FIELDS = {
    "schemaVersion",
    "generationId",
    "goAnimeSourceSha",
    "goAnimeBaselineSha",
    "upstreamRevision",
    "anikkuRevision",
    "sourceId",
    "stage",
    "status",
    "retryCount",
    "titleCount",
    "playbackSampleCount",
    "failureKind",
}
PROVIDER_FIELDS = {
    "sourceId",
    "module",
    "displayName",
    "status",
    "stage",
    "languageMode",
    "titles",
    "pagesVisited",
    "catalogueComplete",
    "catalogueTermination",
    "rawTitleCount",
    "distinctRawTitleCount",
    "playbackSampleCount",
    "failureKind",
}
PROVIDER_V3_FIELDS = PROVIDER_FIELDS | {
    "schemaVersion",
    "executionIdentity",
    "sampleLineage",
    "resolutionSampleCount",
    "mediaEvidence",
}
EXECUTION_IDENTITY_FIELDS = {
    "extensionPackage",
    "extensionClass",
    "extensionApkSha256",
}
LINEAGE_FIELDS = {
    "catalogueDigest",
    "animeOrdinal",
    "animeLabelHash",
    "episodeOrdinal",
    "episodeLabelHash",
    "resolverMode",
}
MEDIA_FIELDS = {
    "transportObserved",
    "playerReadyObserved",
    "timeAdvancedObserved",
    "videoTrackObserved",
    "firstFrameObserved",
    "failureKind",
}
MANIFEST_FIELDS = {
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


class CanaryVerificationError(ValueError):
    """Raised for malformed input that cannot be safely classified."""


def _object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise CanaryVerificationError("duplicate JSON field")
        result[key] = value
    return result


def _json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_object_pairs)
    except (OSError, UnicodeError, json.JSONDecodeError, CanaryVerificationError) as error:
        raise CanaryVerificationError("invalid JSON") from error


def _exact_object(value: Any, fields: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != fields:
        raise CanaryVerificationError(f"{label}: schema fields are not exact")
    return value


def _safe_text(value: Any, label: str, *, nonempty: bool = False) -> None:
    if not isinstance(value, str) or (nonempty and not value) or SAFE_TEXT.fullmatch(value) is None:
        raise CanaryVerificationError(f"{label}: unsafe text")


def _sha(value: Any, label: str, pattern: re.Pattern[str]) -> None:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise CanaryVerificationError(f"{label}: invalid digest")


def _number(value: Any, label: str) -> None:
    if type(value) is not int or value < 0:
        raise CanaryVerificationError(f"{label}: expected non-negative integer")


def _module_list(value: str, label: str) -> list[str]:
    modules = [item.strip() for item in value.split(",") if item.strip()]
    if not modules or any(MODULE.fullmatch(item) is None for item in modules):
        raise CanaryVerificationError(f"{label}: invalid module list")
    if len(set(modules)) != len(modules):
        raise CanaryVerificationError(f"{label}: duplicate module")
    return modules


def _regular(path: Path, label: str) -> None:
    if path.is_symlink() or not path.is_file() or path.stat().st_size == 0:
        raise CanaryVerificationError(f"{label}: missing or non-regular file")


def _digest(path: Path, label: str) -> str:
    _regular(path, label)
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _validate_manifest(path: Path, expected: dict[str, str]) -> dict[str, str]:
    manifest = _exact_object(_json(path), MANIFEST_FIELDS, "reference runtime manifest")
    if manifest["schemaVersion"] != 1 or manifest["jdkMajor"] != 17:
        raise CanaryVerificationError("reference runtime manifest identity is unsupported")
    for key in ("goAnimeSourceSha", "anikkuSha", "flexibleAdapterSha"):
        _sha(manifest[key], f"manifest.{key}", SHA40)
    for key in ("appApkSha256", "testApkSha256"):
        _sha(manifest[key], f"manifest.{key}", SHA256)
    if manifest["goAnimeSourceSha"] != expected["goAnimeSourceSha"]:
        raise CanaryVerificationError("reference runtime GoAnime source identity mismatch")
    if manifest["anikkuSha"] != expected["anikkuSha"]:
        raise CanaryVerificationError("reference runtime Anikku identity mismatch")
    if manifest["flexibleAdapterSha"] != FLEXIBLE_ADAPTER_SHA:
        raise CanaryVerificationError("reference runtime FlexibleAdapter identity mismatch")
    if type(manifest["buildAttempt"]) is not int or manifest["buildAttempt"] < 1:
        raise CanaryVerificationError("reference runtime build attempt is invalid")
    if type(manifest["fallbackUsed"]) is not bool:
        raise CanaryVerificationError("reference runtime fallback flag is invalid")

    runtime_dir = path.parent
    app_digest = _digest(runtime_dir / "anikku-app-debug.apk", "reference runtime app APK")
    test_digest = _digest(runtime_dir / "anikku-app-debug-androidTest.apk", "reference runtime test APK")
    if app_digest != manifest["appApkSha256"] or test_digest != manifest["testApkSha256"]:
        raise CanaryVerificationError("reference runtime APK digest mismatch")
    return {
        "appApkSha256": app_digest,
        "testApkSha256": test_digest,
    }


def _validate_checkpoint(path: Path, module: str, expected: dict[str, str]) -> dict[str, Any]:
    payload = _exact_object(_json(path), CHECKPOINT_FIELDS, f"checkpoint {module}")
    if payload["schemaVersion"] not in (1, 2):
        raise CanaryVerificationError(f"checkpoint {module}: unsupported schema")
    for key in ("generationId", "sourceId", "stage", "status"):
        _safe_text(payload[key], f"checkpoint {module}.{key}", nonempty=True)
    for key in ("goAnimeSourceSha", "goAnimeBaselineSha", "upstreamRevision", "anikkuRevision"):
        _sha(payload[key], f"checkpoint {module}.{key}", SHA40)
    if (
        payload["generationId"] != expected["generationId"]
        or payload["goAnimeSourceSha"] != expected["goAnimeSourceSha"]
        or payload["goAnimeBaselineSha"] != expected["goAnimeBaselineSha"]
        or payload["upstreamRevision"] != expected["upstreamRevision"]
        or payload["anikkuRevision"] != expected["anikkuRevision"]
        or payload["sourceId"] != f"yuzono.pt.{module}"
    ):
        raise CanaryVerificationError(f"checkpoint {module}: identity mismatch")
    if payload["stage"] not in STAGES or payload["status"] not in CHECKPOINT_STATUSES:
        raise CanaryVerificationError(f"checkpoint {module}: invalid state")
    for key in ("retryCount", "titleCount", "playbackSampleCount"):
        _number(payload[key], f"checkpoint {module}.{key}")
    if payload["failureKind"] is not None:
        _safe_text(payload["failureKind"], f"checkpoint {module}.failureKind")
    return payload


def _validate_provider(path: Path, module: str) -> dict[str, Any]:
    payload = _json(path)
    if not isinstance(payload, dict):
        raise CanaryVerificationError(f"provider {module}: root is not an object")
    v3 = "schemaVersion" in payload
    fields = PROVIDER_V3_FIELDS if v3 else PROVIDER_FIELDS
    payload = _exact_object(payload, fields, f"provider {module}")
    if v3 and payload["schemaVersion"] != 3:
        raise CanaryVerificationError(f"provider {module}: unsupported schema")
    if payload["sourceId"] != f"yuzono.pt.{module}" or payload["module"] != module:
        raise CanaryVerificationError(f"provider {module}: source identity mismatch")
    _safe_text(payload["displayName"], f"provider {module}.displayName")
    if payload["status"] not in STATUSES or payload["stage"] not in STAGES:
        raise CanaryVerificationError(f"provider {module}: invalid state")
    if payload["languageMode"] not in LANGUAGES or payload["catalogueTermination"] not in TERMINATIONS:
        raise CanaryVerificationError(f"provider {module}: invalid classification")
    if not isinstance(payload["titles"], list) or any(
        not isinstance(title, str) or SAFE_TEXT.fullmatch(title) is None for title in payload["titles"]
    ):
        raise CanaryVerificationError(f"provider {module}: unsafe titles")
    for key in ("pagesVisited", "rawTitleCount", "distinctRawTitleCount", "playbackSampleCount"):
        _number(payload[key], f"provider {module}.{key}")
    if payload["distinctRawTitleCount"] > payload["rawTitleCount"]:
        raise CanaryVerificationError(f"provider {module}: title count contradiction")
    if type(payload["catalogueComplete"]) is not bool:
        raise CanaryVerificationError(f"provider {module}: invalid catalogueComplete")
    if payload["failureKind"] is not None:
        _safe_text(payload["failureKind"], f"provider {module}.failureKind")

    info: dict[str, Any] = {
        "hasIdentity": False,
        "reachedProvider": payload["stage"] != "discovered",
        "terminalMedia": False,
        "playable": payload["status"] == "ready",
    }
    if not v3:
        return info

    identity = _exact_object(payload["executionIdentity"], EXECUTION_IDENTITY_FIELDS, f"provider {module}.executionIdentity")
    _safe_text(identity["extensionPackage"], f"provider {module}.executionIdentity.extensionPackage", nonempty=True)
    _safe_text(identity["extensionClass"], f"provider {module}.executionIdentity.extensionClass", nonempty=True)
    if PACKAGE.fullmatch(identity["extensionPackage"]) is None or CLASS.fullmatch(identity["extensionClass"]) is None:
        raise CanaryVerificationError(f"provider {module}: invalid extension identity")
    _sha(identity["extensionApkSha256"], f"provider {module}.executionIdentity.extensionApkSha256", SHA256)
    info["hasIdentity"] = True

    lineage = payload["sampleLineage"]
    if lineage is not None:
        lineage = _exact_object(lineage, LINEAGE_FIELDS, f"provider {module}.sampleLineage")
        for key in ("catalogueDigest", "animeLabelHash", "episodeLabelHash"):
            _sha(lineage[key], f"provider {module}.sampleLineage.{key}", SHA256)
        for key in ("animeOrdinal", "episodeOrdinal"):
            _number(lineage[key], f"provider {module}.sampleLineage.{key}")
        if lineage["resolverMode"] not in {"direct", "hoster"}:
            raise CanaryVerificationError(f"provider {module}: invalid resolver mode")

    _number(payload["resolutionSampleCount"], f"provider {module}.resolutionSampleCount")
    if payload["playbackSampleCount"] > payload["resolutionSampleCount"]:
        raise CanaryVerificationError(f"provider {module}: playback count contradiction")
    media = _exact_object(payload["mediaEvidence"], MEDIA_FIELDS, f"provider {module}.mediaEvidence")
    for key in MEDIA_FIELDS - {"failureKind"}:
        if type(media[key]) is not bool:
            raise CanaryVerificationError(f"provider {module}: invalid media flag")
    if media["failureKind"] is not None:
        _safe_text(media["failureKind"], f"provider {module}.mediaEvidence.failureKind")
    info["terminalMedia"] = lineage is not None and payload["playbackSampleCount"] > 0 and all(
        media[key] is True for key in MEDIA_FIELDS - {"failureKind"}
    )
    if info["terminalMedia"] and media["failureKind"] is not None:
        raise CanaryVerificationError(f"provider {module}: terminal media carries failure")
    if info["playable"] and (
        payload["catalogueComplete"] is not True or not info["terminalMedia"]
    ):
        raise CanaryVerificationError(f"provider {module}: ready result lacks terminal media")
    return info


def verify_canary(
    *,
    root: Path,
    manifest: Path,
    modules: list[str],
    structural_module: str,
    candidate_modules: list[str],
    generation_id: str,
    goanime_source_sha: str,
    goanime_baseline_sha: str,
    upstream_revision: str,
    anikku_sha: str,
) -> dict[str, Any]:
    for label, value, pattern in (
        ("GoAnime source", goanime_source_sha, SHA40),
        ("GoAnime baseline", goanime_baseline_sha, SHA40),
        ("Yuzono", upstream_revision, SHA40),
        ("Anikku", anikku_sha, SHA40),
    ):
        _sha(value, label, pattern)
    _safe_text(generation_id, "generation_id", nonempty=True)
    if not MODULE.fullmatch(structural_module) or structural_module not in modules:
        raise CanaryVerificationError("structural module is outside the selected canary")
    if not candidate_modules or any(module not in modules for module in candidate_modules):
        raise CanaryVerificationError("candidate module is outside the selected canary")
    if structural_module in candidate_modules:
        raise CanaryVerificationError("structural module cannot also be a candidate")
    if root.is_symlink() or not root.is_dir():
        raise CanaryVerificationError("canary state root is missing or symlinked")

    manifest_identity = _validate_manifest(
        manifest,
        {
            "goAnimeSourceSha": goanime_source_sha,
            "anikkuSha": anikku_sha,
        },
    )
    providers = root / "providers"
    checkpoints = root / "checkpoints"
    if providers.is_symlink() or checkpoints.is_symlink() or not providers.is_dir() or not checkpoints.is_dir():
        raise CanaryVerificationError("canary state directories are missing")

    selected_info: dict[str, dict[str, Any]] = {}
    violations: list[str] = []
    for module in modules:
        provider_path = providers / f"{module}.json"
        checkpoint_path = checkpoints / f"{module}.json"
        try:
            _regular(provider_path, f"provider {module}")
            _regular(checkpoint_path, f"checkpoint {module}")
            checkpoint = _validate_checkpoint(
                checkpoint_path,
                module,
                {
                    "generationId": generation_id,
                    "goAnimeSourceSha": goanime_source_sha,
                    "goAnimeBaselineSha": goanime_baseline_sha,
                    "upstreamRevision": upstream_revision,
                    "anikkuRevision": anikku_sha,
                },
            )
            info = _validate_provider(provider_path, module)
            if checkpoint["sourceId"] != f"yuzono.pt.{module}":
                raise CanaryVerificationError(f"provider {module}: checkpoint source mismatch")
            selected_info[module] = info
        except CanaryVerificationError as error:
            # Keep diagnostics structural and never echo provider payload values.
            violations.append(str(error).split(":", 1)[0])

    provider_files = {path.name for path in providers.iterdir() if path.is_file()}
    checkpoint_files = {path.name for path in checkpoints.iterdir() if path.is_file()}
    expected_files = {f"{module}.json" for module in modules}
    if provider_files != expected_files:
        violations.append("provider file set mismatch")
    if checkpoint_files != expected_files:
        violations.append("checkpoint file set mismatch")

    observed = sorted(module for module, info in selected_info.items() if info["reachedProvider"])
    path_identity = sorted(module for module, info in selected_info.items() if info["hasIdentity"])
    terminal_media = sorted(module for module, info in selected_info.items() if info["terminalMedia"])
    playable = sorted(module for module, info in selected_info.items() if info["playable"])

    for module in modules:
        if module not in path_identity:
            violations.append(f"path identity missing: {module}")
    if structural_module not in observed:
        violations.append("structural control did not reach provider code")
    candidate_observed = [module for module in candidate_modules if module in observed]
    if not candidate_observed:
        violations.append("candidate provider did not reach provider code")
    candidate_terminal_media = [module for module in candidate_modules if module in terminal_media]
    if not candidate_terminal_media:
        violations.append("candidate provider lacks terminal media")
    if any(module not in terminal_media for module in playable):
        violations.append("playable provider lacks terminal media")

    # De-duplicate while retaining deterministic order.
    violations = list(dict.fromkeys(violations))
    return {
        "schemaVersion": 1,
        "generationId": generation_id,
        "goAnimeSourceSha": goanime_source_sha,
        "goAnimeBaselineSha": goanime_baseline_sha,
        "upstreamRevision": upstream_revision,
        "anikkuRevision": anikku_sha,
        "referenceRuntimeAppApkSha256": manifest_identity["appApkSha256"],
        "referenceRuntimeTestApkSha256": manifest_identity["testApkSha256"],
        "structuralModules": [structural_module],
        "candidateModules": candidate_modules,
        "observedModules": observed,
        "pathIdentityModules": path_identity,
        "terminalMediaModules": terminal_media,
        "playableModules": playable,
        "accepted": not violations,
        "violations": violations,
    }


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--modules", required=True)
    parser.add_argument("--structural-module", required=True)
    parser.add_argument("--candidate-modules", required=True)
    parser.add_argument("--generation-id", required=True)
    parser.add_argument("--goanime-source-sha", required=True)
    parser.add_argument("--goanime-baseline-sha", required=True)
    parser.add_argument("--upstream-revision", required=True)
    parser.add_argument("--anikku-sha", required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        modules = _module_list(args.modules, "modules")
        candidates = _module_list(args.candidate_modules, "candidate-modules")
        verification = verify_canary(
            root=args.root,
            manifest=args.manifest,
            modules=modules,
            structural_module=args.structural_module,
            candidate_modules=candidates,
            generation_id=args.generation_id,
            goanime_source_sha=args.goanime_source_sha,
            goanime_baseline_sha=args.goanime_baseline_sha,
            upstream_revision=args.upstream_revision,
            anikku_sha=args.anikku_sha,
        )
    except CanaryVerificationError as error:
        print(f"canary verification failed: {error}", file=sys.stderr)
        return 2

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(verification, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if not verification["accepted"]:
        print("canary verification rejected", file=sys.stderr)
        return 1
    print("canary verification accepted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
