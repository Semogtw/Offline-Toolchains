#!/usr/bin/env python3
"""Fail-closed allowlist gate for T02/T03 uploads, summaries and runner logs.

This gate validates the recursive trees that the audit workflow uploads. Raw
instrumentation and Gradle output is read only from the runner temp directory;
it is never copied to an artifact or a step summary.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
MODULE = re.compile(r"^[a-z0-9._-]{1,80}$")
FORBIDDEN_TEXT = re.compile(
    r"(?i)(?:https?://|ftp://|www\.|<\s*/?\s*[a-z!][^>]*>|"
    r"(?:authorization|proxy-authorization|cookie|set-cookie|x-api-key|api-key|"
    r"access-token|refresh-token|bearer|streamurl|stream-url|rawpayload|raw-payload)\s*[:=])"
)
FORBIDDEN_KEY = re.compile(
    r"(?i)^(?:url|urls|headers?|cookies?|token|tokens|payload|raw|response|body|html|"
    r"streamurl|stream-url|authorization|proxy-authorization|set-cookie|api-key)$"
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
PROBE_PROVIDER_FIELDS = {
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
INVENTORY_FIELDS = {
    "sourceId",
    "module",
    "upstreamPath",
    "upstreamRevision",
    "displayName",
    "extensionClass",
    "themePkg",
    "isNsfw",
    "language",
}
MATRIX_FIELDS = {"include"}
MATRIX_ENTRY_FIELDS = {"shard", "modules"}
AGGREGATE_PROVIDER_FIELDS = {
    "sourceId",
    "module",
    "displayName",
    "status",
    "stage",
    "languageMode",
    "pagesVisited",
    "catalogueComplete",
    "catalogueTermination",
    "rawTitleCount",
    "distinctRawTitleCount",
    "normalizedTitleCount",
    "overlapWithGoAnime",
    "exclusiveVsGoAnime",
    "normalizationCollisions",
    "incrementalUniqueContribution",
    "incrementalExclusiveContribution",
    "playbackSampleCount",
    "failureKind",
}
AGGREGATE_FIELDS = {
    "providerCount",
    "statusCounts",
    "baselineGoAnimeUniqueTitles",
    "candidateRawOccurrences",
    "candidateNormalizedOccurrences",
    "candidateUnionUniqueTitles",
    "crossProviderDuplicateOccurrences",
    "candidateExclusiveUniqueTitles",
    "combinedUniqueTitles",
    "candidateExclusiveTitles",
    "identityMappingMode",
    "canonicalMatched",
    "canonicalUnresolved",
    "auditComplete",
    "auditBlockers",
    "promotionCandidates",
    "promotionRejected",
    "providers",
}
VERIFICATION_FIELDS = {
    "consistent",
    "complete",
    "scoped_count",
    "accepted_terminal_count",
    "pending_count",
    "blocker_count",
    "missing_result_count",
    "identity_mismatch_count",
    "violations",
}
COMPARISON_FIELDS = {
    "baselineGoAnimeUniqueTitles",
    "candidateUnionUniqueTitles",
    "candidateExclusiveUniqueTitles",
    "combinedUniqueTitles",
    "candidateExclusiveTitles",
}
REFERENCE_MANIFEST_FIELDS = {
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
REPORT_HEADINGS = {
    "# Yuzono PT-BR Anime Probe",
    "| Metric | Value |",
    "| --- | ---: |",
    "| Provider | Status | Stage | Language | Catalog complete | Titles | Overlap | Exclusive | Incremental unique | Playback samples | Failure |",
    "| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |",
    "## Promotion candidates",
    "## Audit blockers",
}
REPORT_ITEM = re.compile(r"^- yuzono\.pt\.[a-z0-9._-]{1,80}$")
REPORT_METRICS = frozenset(
    {
        "Audit complete",
        "Audit blockers",
        "Promotion candidates",
        "GoAnime baseline unique titles",
        "Candidate raw occurrences",
        "Candidate normalized occurrences",
        "Candidate union unique titles",
        "Cross-provider duplicate occurrences",
        "Candidate exclusive titles",
        "Combined unique titles",
    }
)
SUMMARY_STATUS = frozenset(
    {"ready", "partial", "blocked", "broken", "unsupported", "not-anime", "unknown"}
)
SUMMARY_STAGE = frozenset(
    {"discovered", "reachable", "catalog", "identity", "episodes", "player", "stream", "classified"}
)
SUMMARY_LANGUAGE = frozenset({"sub", "dub", "mixed", "unknown"})
SUMMARY_SCOPE_LINE = (
    "- Scope: centralized module policy; isNsfw remains metadata and mixed-content "
    "anime modules remain candidates; current GoAnime PT production modules are "
    "canary/control-only; donghuanosekai, doramogo and muitohentai are excluded as "
    "non-conventional; audit-only, with no production registration"
)
SUMMARY_GENERATION = re.compile(r"^- generation: `([A-Za-z0-9._-]{1,100})`$")
SUMMARY_INDEX = re.compile(r"^- continuation index: `([0-9]+)`$")
SUMMARY_RUN = re.compile(r"^- reference runtime origin run: `([1-9][0-9]*)`$")
SUMMARY_PENDING = re.compile(r"^- pending providers: `([0-9]+)`$")
SUMMARY_SHA = re.compile(r"^- (?:GoAnime probe|GoAnime baseline|Yuzono|Anikku) SHA: `([0-9a-f]{40})`$")
CANARY_ROW = re.compile(
    r"^\| (?P<name>[^|\r\n]{1,160}) \| (?P<status>[^|\r\n]+) \| "
    r"(?P<stage>[^|\r\n]+) \| (?P<titles>[0-9]+) \| (?P<playback>[0-9]+) \| "
    r"(?P<failure>[^|\r\n]{0,80}) \|$"
)


class SanitizationError(ValueError):
    pass


def _object_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise SanitizationError("duplicate JSON field")
        result[key] = value
    return result


def _json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_object_pairs)
    except (OSError, UnicodeError, json.JSONDecodeError, SanitizationError) as error:
        raise SanitizationError("invalid JSON") from error


def _field_object(value: Any, fields: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SanitizationError(f"{label}: schema root must be an object")
    actual = set(value)
    if actual != fields:
        raise SanitizationError(f"{label}: schema fields are not exact")
    for key in value:
        if FORBIDDEN_KEY.fullmatch(key):
            raise SanitizationError(f"{label}: forbidden field")
    return value


def _nonnegative(value: Any, label: str) -> None:
    if type(value) is not int or value < 0:
        raise SanitizationError(f"{label}: expected non-negative integer")


def _safe_string(value: Any, label: str, *, allow_empty: bool = True) -> None:
    if not isinstance(value, str) or (not allow_empty and not value):
        raise SanitizationError(f"{label}: expected string")
    if "\x00" in value or "\n" in value or "\r" in value:
        raise SanitizationError(f"{label}: control character")
    if "|" in value:
        raise SanitizationError(f"{label}: table delimiter")
    if FORBIDDEN_TEXT.search(value):
        raise SanitizationError(f"{label}: forbidden content")


def _safe_list(value: Any, label: str) -> None:
    if not isinstance(value, list):
        raise SanitizationError(f"{label}: expected list")
    for index, item in enumerate(value):
        _safe_string(item, f"{label}[{index}]")


def _validate_sha(value: Any, label: str, pattern: re.Pattern[str]) -> None:
    if not isinstance(value, str) or pattern.fullmatch(value) is None:
        raise SanitizationError(f"{label}: invalid digest")


def _validate_checkpoint(value: Any, label: str) -> None:
    payload = _field_object(value, CHECKPOINT_FIELDS, label)
    for key in ("generationId", "sourceId", "stage", "status"):
        _safe_string(payload[key], f"{label}.{key}", allow_empty=False)
    for key in ("goAnimeSourceSha", "goAnimeBaselineSha", "upstreamRevision", "anikkuRevision"):
        _validate_sha(payload[key], f"{label}.{key}", SHA40)
    if payload["schemaVersion"] not in (1, 2):
        raise SanitizationError(f"{label}.schemaVersion: unsupported")
    for key in ("retryCount", "titleCount", "playbackSampleCount"):
        _nonnegative(payload[key], f"{label}.{key}")
    if payload["failureKind"] is not None:
        _safe_string(payload["failureKind"], f"{label}.failureKind")


def _validate_probe_provider(value: Any, label: str) -> None:
    payload = _field_object(value, PROBE_PROVIDER_FIELDS, label)
    _safe_string(payload["sourceId"], f"{label}.sourceId", allow_empty=False)
    _safe_string(payload["module"], f"{label}.module", allow_empty=False)
    if MODULE.fullmatch(payload["module"]) is None:
        raise SanitizationError(f"{label}.module: invalid module")
    _safe_string(payload["displayName"], f"{label}.displayName")
    for key in ("status", "stage", "languageMode", "catalogueTermination"):
        _safe_string(payload[key], f"{label}.{key}", allow_empty=False)
    _safe_list(payload["titles"], f"{label}.titles")
    for key in ("pagesVisited", "rawTitleCount", "distinctRawTitleCount", "playbackSampleCount"):
        _nonnegative(payload[key], f"{label}.{key}")
    if type(payload["catalogueComplete"]) is not bool:
        raise SanitizationError(f"{label}.catalogueComplete: expected boolean")
    if payload["failureKind"] is not None:
        _safe_string(payload["failureKind"], f"{label}.failureKind")


def _validate_inventory(value: Any, label: str) -> None:
    if not isinstance(value, list):
        raise SanitizationError(f"{label}: expected list")
    for index, entry in enumerate(value):
        payload = _field_object(entry, INVENTORY_FIELDS, f"{label}[{index}]")
        for key in ("sourceId", "module", "upstreamPath", "displayName", "extensionClass", "language"):
            _safe_string(payload[key], f"{label}[{index}].{key}", allow_empty=False)
        if MODULE.fullmatch(payload["module"]) is None:
            raise SanitizationError(f"{label}[{index}].module: invalid module")
        _validate_sha(payload["upstreamRevision"], f"{label}[{index}].upstreamRevision", SHA40)
        if payload["themePkg"] is not None:
            _safe_string(payload["themePkg"], f"{label}[{index}].themePkg")
        if type(payload["isNsfw"]) is not bool:
            raise SanitizationError(f"{label}[{index}].isNsfw: expected boolean")


def _validate_matrix(value: Any, label: str) -> None:
    payload = _field_object(value, MATRIX_FIELDS, label)
    if not isinstance(payload["include"], list):
        raise SanitizationError(f"{label}.include: expected list")
    for index, entry in enumerate(payload["include"]):
        item = _field_object(entry, MATRIX_ENTRY_FIELDS, f"{label}.include[{index}]")
        _nonnegative(item["shard"], f"{label}.include[{index}].shard")
        _safe_module_list(item["modules"], f"{label}.include[{index}].modules")


def _safe_module_list(value: Any, label: str) -> None:
    if not isinstance(value, list):
        raise SanitizationError(f"{label}: expected list")
    for index, item in enumerate(value):
        if not isinstance(item, str) or MODULE.fullmatch(item) is None:
            raise SanitizationError(f"{label}[{index}]: invalid module")


def _validate_checkpoint_or_provider_tree(relative: Path, path: Path, label: str) -> None:
    if (
        len(relative.parts) != 2
        or relative.parts[0] not in {"checkpoints", "providers"}
        or relative.suffix != ".json"
    ):
        raise SanitizationError(f"{label}: path is outside the allowlist")
    module = relative.stem
    if MODULE.fullmatch(module) is None:
        raise SanitizationError(f"{label}: invalid module path")
    payload = _json(path)
    if relative.parts[0] == "checkpoints":
        _validate_checkpoint(payload, label)
    else:
        _validate_probe_provider(payload, label)


def _validate_aggregate_provider(value: Any, label: str) -> None:
    payload = _field_object(value, AGGREGATE_PROVIDER_FIELDS, label)
    for key in ("sourceId", "module", "displayName", "status", "stage", "languageMode", "catalogueTermination"):
        _safe_string(payload[key], f"{label}.{key}")
    if MODULE.fullmatch(payload["module"]) is None:
        raise SanitizationError(f"{label}.module: invalid module")
    for key in (
        "pagesVisited", "rawTitleCount", "distinctRawTitleCount", "normalizedTitleCount",
        "overlapWithGoAnime", "exclusiveVsGoAnime", "normalizationCollisions",
        "incrementalUniqueContribution", "incrementalExclusiveContribution", "playbackSampleCount",
    ):
        _nonnegative(payload[key], f"{label}.{key}")
    if type(payload["catalogueComplete"]) is not bool and payload["catalogueComplete"] is not None:
        raise SanitizationError(f"{label}.catalogueComplete: expected boolean or null")
    if payload["failureKind"] is not None:
        _safe_string(payload["failureKind"], f"{label}.failureKind")


def _validate_aggregate(value: Any, label: str) -> None:
    payload = _field_object(value, AGGREGATE_FIELDS, label)
    for key in (
        "providerCount", "baselineGoAnimeUniqueTitles", "candidateRawOccurrences",
        "candidateNormalizedOccurrences", "candidateUnionUniqueTitles", "crossProviderDuplicateOccurrences",
        "candidateExclusiveUniqueTitles", "combinedUniqueTitles", "canonicalMatched", "canonicalUnresolved",
    ):
        _nonnegative(payload[key], f"{label}.{key}")
    if not isinstance(payload["statusCounts"], dict):
        raise SanitizationError(f"{label}.statusCounts: expected object")
    for key, count in payload["statusCounts"].items():
        _safe_string(key, f"{label}.statusCounts key", allow_empty=False)
        _nonnegative(count, f"{label}.statusCounts.{key}")
    _safe_string(payload["identityMappingMode"], f"{label}.identityMappingMode", allow_empty=False)
    if type(payload["auditComplete"]) is not bool:
        raise SanitizationError(f"{label}.auditComplete: expected boolean")
    for key in ("candidateExclusiveTitles", "auditBlockers", "promotionCandidates"):
        _safe_list(payload[key], f"{label}.{key}")
    if not isinstance(payload["promotionRejected"], dict):
        raise SanitizationError(f"{label}.promotionRejected: expected object")
    for source_id, reasons in payload["promotionRejected"].items():
        _safe_string(source_id, f"{label}.promotionRejected key", allow_empty=False)
        _safe_list(reasons, f"{label}.promotionRejected.{source_id}")
    if not isinstance(payload["providers"], list):
        raise SanitizationError(f"{label}.providers: expected list")
    for index, provider in enumerate(payload["providers"]):
        _validate_aggregate_provider(provider, f"{label}.providers[{index}]")


def _validate_verification(value: Any, label: str) -> None:
    payload = _field_object(value, VERIFICATION_FIELDS, label)
    for key in ("consistent", "complete"):
        if type(payload[key]) is not bool:
            raise SanitizationError(f"{label}.{key}: expected boolean")
    for key in (
        "scoped_count",
        "accepted_terminal_count",
        "pending_count",
        "blocker_count",
        "missing_result_count",
        "identity_mismatch_count",
    ):
        _nonnegative(payload[key], f"{label}.{key}")
    _safe_list(payload["violations"], f"{label}.violations")


def _validate_comparison(value: Any, label: str) -> None:
    payload = _field_object(value, COMPARISON_FIELDS, label)
    for key in COMPARISON_FIELDS - {"candidateExclusiveTitles"}:
        _nonnegative(payload[key], f"{label}.{key}")
    _safe_list(payload["candidateExclusiveTitles"], f"{label}.candidateExclusiveTitles")


def _validate_manifest(value: Any, label: str) -> None:
    payload = _field_object(value, REFERENCE_MANIFEST_FIELDS, label)
    if payload["schemaVersion"] != 1 or payload["jdkMajor"] != 17:
        raise SanitizationError(f"{label}: unsupported identity")
    for key in ("goAnimeSourceSha", "anikkuSha", "flexibleAdapterSha"):
        _validate_sha(payload[key], f"{label}.{key}", SHA40)
    for key in ("appApkSha256", "testApkSha256"):
        _validate_sha(payload[key], f"{label}.{key}", SHA256)
    if type(payload["buildAttempt"]) is not int or payload["buildAttempt"] < 1:
        raise SanitizationError(f"{label}.buildAttempt: invalid")
    if type(payload["fallbackUsed"]) is not bool:
        raise SanitizationError(f"{label}.fallbackUsed: expected boolean")


def _summary_text(value: str, label: str) -> None:
    _safe_string(value, label, allow_empty=False)
    if value.strip().lower() in {"raw", "payload", "html", "url", "token", "cookie"}:
        raise SanitizationError(f"{label}: forbidden summary value")


def _validate_report_line(line: str, label: str, index: int) -> None:
    if not line or line in REPORT_HEADINGS or REPORT_ITEM.fullmatch(line):
        return
    if not line.startswith("| ") or not line.endswith(" |"):
        raise SanitizationError(f"{label}:{index}: report line is outside the schema")
    cells = line[2:-2].split(" | ")
    if len(cells) == 2:
        metric, value = cells
        if metric not in REPORT_METRICS:
            raise SanitizationError(f"{label}:{index}: report metric is not allowlisted")
        if metric == "Audit complete":
            if value not in {"yes", "no"}:
                raise SanitizationError(f"{label}:{index}: report boolean is invalid")
        elif re.fullmatch(r"[0-9]+", value) is None:
            raise SanitizationError(f"{label}:{index}: report number is invalid")
        return
    if len(cells) != 11:
        raise SanitizationError(f"{label}:{index}: report table shape is invalid")
    name, status, stage, language, complete, *numeric, failure = cells
    _summary_text(name, f"{label}:{index}.displayName")
    if status not in SUMMARY_STATUS or stage not in SUMMARY_STAGE or language not in SUMMARY_LANGUAGE:
        raise SanitizationError(f"{label}:{index}: report enum is invalid")
    if complete not in {"yes", "no"} or any(re.fullmatch(r"[0-9]+", value) is None for value in numeric):
        raise SanitizationError(f"{label}:{index}: report numeric field is invalid")
    if failure != "-" and re.fullmatch(r"[a-z0-9._-]{1,80}", failure) is None:
        raise SanitizationError(f"{label}:{index}: report failure is invalid")
    _summary_text(failure, f"{label}:{index}.failure") if failure != "-" else None


def _validate_report(path: Path, label: str) -> None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise SanitizationError(f"{label}: invalid report text") from error
    for index, line in enumerate(lines, 1):
        if len(line) > 400 or "\x00" in line or FORBIDDEN_TEXT.search(line):
            raise SanitizationError(f"{label}:{index}: forbidden content")
        _validate_report_line(line, label, index)


def _validate_summary_line(line: str, label: str, index: int) -> None:
    if not line:
        return
    if line in REPORT_HEADINGS or line in {
        "## Instrumented PT-BR canary",
        "## Generation receipt",
        "| Provider | Status | Stage | Titles | Playback | Failure |",
        "|---|---|---|---:|---:|---|",
    }:
        return
    if line.startswith("|"):
        try:
            _validate_report_line(line, label, index)
            return
        except SanitizationError:
            pass
        match = CANARY_ROW.fullmatch(line)
        if match is None:
            raise SanitizationError(f"{label}:{index}: summary table is not allowlisted")
        if match.group("status") not in SUMMARY_STATUS or match.group("stage") not in SUMMARY_STAGE:
            raise SanitizationError(f"{label}:{index}: summary enum is invalid")
        _summary_text(match.group("name"), f"{label}:{index}.displayName")
        failure = match.group("failure")
        if failure and failure != "-" and re.fullmatch(r"[a-z0-9._-]{1,80}", failure) is None:
            raise SanitizationError(f"{label}:{index}: summary failure is invalid")
        if failure and failure != "-":
            _summary_text(failure, f"{label}:{index}.failure")
        return
    if REPORT_ITEM.fullmatch(line):
        return
    if line == SUMMARY_SCOPE_LINE:
        return
    if any(pattern.fullmatch(line) for pattern in (SUMMARY_GENERATION, SUMMARY_INDEX, SUMMARY_RUN, SUMMARY_PENDING, SUMMARY_SHA)):
        return
    raise SanitizationError(f"{label}:{index}: summary line is outside the schema")


def _scan_summary(path: Path) -> None:
    if path.is_symlink() or not path.is_file():
        raise SanitizationError(f"{path}: non-regular summary")
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        raise SanitizationError(f"{path}: summary is not sanitized text") from error
    if not lines:
        raise SanitizationError(f"{path}: summary is empty")
    for index, line in enumerate(lines, 1):
        if len(line) > 400 or "\x00" in line or FORBIDDEN_TEXT.search(line):
            raise SanitizationError(f"{path}:{index}: forbidden summary content")
        _validate_summary_line(line, str(path), index)


def _validate_file(root_name: str, relative: Path, path: Path) -> None:
    label = str(path)
    if path.is_symlink() or not path.is_file():
        raise SanitizationError(f"{label}: non-regular file")
    if path.stat().st_size == 0:
        raise SanitizationError(f"{label}: empty file")

    if root_name == "reference-runtime":
        allowed = {
            "anikku-app-debug.apk",
            "anikku-app-debug-androidTest.apk",
            "reference-runtime-manifest.json",
        }
        if str(relative) not in allowed:
            raise SanitizationError(f"{label}: path is outside the allowlist")
        if path.name.endswith(".json"):
            _validate_manifest(_json(path), label)
        return

    if root_name in {"probe-state", "consolidated-state"}:
        _validate_checkpoint_or_provider_tree(relative, path, label)
        return

    if root_name == "audit-plan":
        if relative.parts[:1] == ("resume-state",):
            _validate_checkpoint_or_provider_tree(Path(*relative.parts[1:]), path, label)
        elif str(relative) in {"inventory.json", "pending-inventory.json"}:
            _validate_inventory(_json(path), label)
        elif str(relative) == "pending.json":
            _safe_module_list(_json(path), label)
        elif str(relative) == "matrix.json":
            _validate_matrix(_json(path), label)
        else:
            raise SanitizationError(f"{label}: path is outside the allowlist")
        return

    if root_name == "audit-output":
        if path.name == "results.json" and relative == Path("results.json"):
            _validate_aggregate(_json(path), label)
        elif path.name == "verification.json" and relative == Path("verification.json"):
            _validate_verification(_json(path), label)
        elif path.name == "catalog-comparison.json" and relative == Path("catalog-comparison.json"):
            _validate_comparison(_json(path), label)
        elif path.name == "pending.json" and relative == Path("pending.json"):
            _safe_module_list(_json(path), label)
        elif path.name == "report.md" and relative == Path("report.md"):
            _validate_report(path, label)
        else:
            raise SanitizationError(f"{label}: path is outside the allowlist")
        return

    raise SanitizationError(f"{label}: unsupported output root")


def _scan_root(root: Path) -> int:
    if not root.exists() or root.is_symlink():
        raise SanitizationError(f"{root}: missing or symlink root")
    root_name = root.name
    if root.is_file():
        parent_name = root.parent.name
        _validate_file(parent_name, Path(root.name), root)
        return 1
    files = sorted(path for path in root.rglob("*") if path.is_file() or path.is_symlink())
    if not files:
        raise SanitizationError(f"{root}: output tree is empty")
    for path in files:
        _validate_file(root_name, path.relative_to(root), path)
    return len(files)


def _log_line_allowed(line: str, kind: str) -> bool:
    if not line:
        return True
    if kind == "instrumentation":
        patterns = (
            r"^GoAnime probe instrumentation registration:$",
            r"^instrumentation:[A-Za-z0-9_.:/()=+\- ]{1,240}$",
            r"^INSTRUMENTATION_STATUS: (?:class|current|id|numtests|stream)=[A-Za-z0-9_.:/=+\- ]{0,240}$",
            r"^INSTRUMENTATION_RESULT: stream=[A-Za-z0-9_.:/=+\- ]{0,240}$",
            r"^INSTRUMENTATION_CODE: -?[0-9]+$",
            r"^(?:Instrumentation command failed|Instrumentation runner reported failure|Instrumentation completed but result file is missing) for [a-z0-9._-]{1,80}$",
            r"^Skipping terminal module [a-z0-9._-]{1,80}$",
            r"^Soft budget reached before [a-z0-9._-]{1,80}; leaving remaining modules pending$",
        )
    else:
        patterns = (
            r"^> Task [A-Za-z0-9:._-]+$",
            r"^BUILD (?:SUCCESSFUL|FAILED) in [0-9]+s$",
            r"^Starting a Gradle Daemon.*$",
            r"^Daemon will be stopped at the end of the build$",
            r"^Welcome to Gradle [0-9.]+!$",
            r"^Calculating task graph as no cached configuration is available for tasks: [A-Za-z0-9:._, -]+$",
            r"^Configuration on demand is an incubating feature\.$",
            r"^Deprecated Gradle features were used in this build, making it incompatible with Gradle [0-9.]+\.$",
        )
    return any(re.fullmatch(pattern, line) for pattern in patterns)


def _scan_log(path: Path, kind: str) -> None:
    if path.is_symlink() or not path.is_file():
        raise SanitizationError(f"{path}: non-regular log")
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        raise SanitizationError(f"{path}: log is not sanitized text") from error
    for index, line in enumerate(text.splitlines(), 1):
        if len(line) > 400 or "\x00" in line or FORBIDDEN_TEXT.search(line):
            raise SanitizationError(f"{path}:{index}: forbidden log content")
        if not _log_line_allowed(line, kind):
            raise SanitizationError(f"{path}:{index}: log line is outside the schema")


def _scan_logs(logs_dir: Path | None, explicit: list[Path]) -> int:
    paths = list(explicit)
    if logs_dir is not None:
        if not logs_dir.exists() or logs_dir.is_symlink():
            raise SanitizationError(f"{logs_dir}: missing log directory")
        paths.extend(sorted(path for path in logs_dir.rglob("*") if path.is_file() or path.is_symlink()))
    seen: set[Path] = set()
    count = 0
    for path in paths:
        resolved = path.absolute()
        if resolved in seen:
            continue
        seen.add(resolved)
        if path.suffix != ".log":
            raise SanitizationError(f"{path}: log extension is not allowlisted")
        kind = "instrumentation" if "instrumentation" in path.name else "gradle"
        _scan_log(path, kind)
        count += 1
    return count


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Recursively verify allowlisted, sanitized audit outputs and runner logs."
    )
    parser.add_argument("--root", action="append", type=Path, default=[], help="output root to scan")
    parser.add_argument("--summary-file", type=Path, help="materialized summary candidate to scan")
    parser.add_argument("--logs-dir", type=Path, help="runner-temp directory containing non-uploaded logs")
    parser.add_argument("--log", action="append", type=Path, default=[], help="individual runner log to scan")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.root and args.summary_file is None:
        print("audit output sanitation failed: at least one root or summary is required", file=sys.stderr)
        return 2
    try:
        output_files = sum(_scan_root(root) for root in args.root)
        log_files = _scan_logs(args.logs_dir, args.log)
        summary_files = 0
        if args.summary_file is not None:
            _scan_summary(args.summary_file)
            summary_files = 1
    except SanitizationError as error:
        print(f"audit output sanitation failed: {error}", file=sys.stderr)
        return 1
    print(
        "audit output sanitation passed: "
        f"output_files={output_files} log_files={log_files} summary_files={summary_files}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
