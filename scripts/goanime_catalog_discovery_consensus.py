#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import urllib.request
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

_ALLOWED_PROVIDERS = frozenset({"animefire", "animesonline", "goyabu", "anitube"})
_DOCUMENT_RE = re.compile(r"/documents/users/([^/]+)/catalogDiscoveries/([^/]+)$")
_MAX_TITLE_LENGTH = 300
_MAX_PROVIDER_TITLE_LENGTH = 500
_MAX_CLOCK_SKEW = timedelta(minutes=5)


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _parse_time(value: object) -> datetime | None:
    text = str(value or "").strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _firestore_value(value: object) -> object:
    if not isinstance(value, dict):
        return None
    if "stringValue" in value:
        return str(value["stringValue"])
    if "integerValue" in value:
        try:
            return int(str(value["integerValue"]))
        except ValueError:
            return None
    if "booleanValue" in value:
        return bool(value["booleanValue"])
    if "timestampValue" in value:
        return str(value["timestampValue"])
    if "doubleValue" in value:
        try:
            return float(value["doubleValue"])
        except (TypeError, ValueError):
            return None
    return None


def _firestore_fields(document: dict[str, Any]) -> dict[str, object]:
    raw = document.get("fields")
    if not isinstance(raw, dict):
        return {}
    return {str(key): _firestore_value(value) for key, value in raw.items()}


@dataclass(frozen=True)
class DiscoveryReport:
    reporter_uid: str
    mal_id: int
    title: str
    normalized_title: str
    provider_id: str
    provider_name: str
    provider_title: str
    has_sub: bool
    has_dub: bool
    verified_at: datetime

    @property
    def group_key(self) -> tuple[int, str, str]:
        return self.mal_id, self.provider_id, self.normalized_title


def parse_report(
    document: dict[str, Any],
    *,
    now: datetime,
    max_age: timedelta,
) -> DiscoveryReport | None:
    name = str(document.get("name") or "")
    match = _DOCUMENT_RE.search(name)
    if match is None:
        return None
    reporter_uid = match.group(1).strip()
    if not reporter_uid:
        return None

    fields = _firestore_fields(document)
    if fields.get("schemaVersion") != 1:
        return None
    if fields.get("playbackVerified") is not True:
        return None
    if fields.get("verificationSource") != "dynamicAvailabilityCache":
        return None

    mal_id = fields.get("malId")
    provider_id = str(fields.get("providerId") or "").strip().lower()
    title = str(fields.get("title") or "").strip()
    normalized_title = str(fields.get("normalizedTitle") or "").strip().lower()
    provider_name = str(fields.get("providerName") or "").strip()
    provider_title = str(fields.get("providerTitle") or "").strip()
    has_sub = fields.get("hasSub") is True
    has_dub = fields.get("hasDub") is True
    verified_at = _parse_time(fields.get("verifiedAt"))

    if not isinstance(mal_id, int) or mal_id <= 0:
        return None
    if provider_id not in _ALLOWED_PROVIDERS:
        return None
    if not title or len(title) > _MAX_TITLE_LENGTH:
        return None
    if not normalized_title or len(normalized_title) > _MAX_TITLE_LENGTH:
        return None
    if len(provider_title) > _MAX_PROVIDER_TITLE_LENGTH:
        return None
    if not has_sub and not has_dub:
        return None
    if verified_at is None:
        return None
    if verified_at > now + _MAX_CLOCK_SKEW:
        return None
    if now - verified_at > max_age:
        return None

    return DiscoveryReport(
        reporter_uid=reporter_uid,
        mal_id=mal_id,
        title=title,
        normalized_title=normalized_title,
        provider_id=provider_id,
        provider_name=provider_name,
        provider_title=provider_title,
        has_sub=has_sub,
        has_dub=has_dub,
        verified_at=verified_at,
    )


def _pick_text(values: Iterable[str]) -> str:
    cleaned = [value.strip() for value in values if value and value.strip()]
    if not cleaned:
        return ""
    counts = Counter(cleaned)
    return sorted(counts, key=lambda value: (-counts[value], len(value), value))[0]


def build_consensus(
    documents: Iterable[dict[str, Any]],
    *,
    now: datetime | None = None,
    min_reporters: int = 2,
    max_age_days: int = 14,
) -> dict[str, object]:
    if min_reporters < 2:
        raise ValueError("min_reporters must be at least 2")
    if max_age_days < 1:
        raise ValueError("max_age_days must be positive")

    current = (now or _utcnow()).astimezone(timezone.utc)
    max_age = timedelta(days=max_age_days)
    grouped: dict[tuple[int, str, str], dict[str, DiscoveryReport]] = defaultdict(dict)
    accepted_reports = 0

    for document in documents:
        if not isinstance(document, dict):
            continue
        report = parse_report(document, now=current, max_age=max_age)
        if report is None:
            continue
        accepted_reports += 1
        previous = grouped[report.group_key].get(report.reporter_uid)
        if previous is None or report.verified_at > previous.verified_at:
            grouped[report.group_key][report.reporter_uid] = report

    candidates: list[dict[str, object]] = []
    for (mal_id, provider_id, normalized_title), reports_by_uid in grouped.items():
        reports = list(reports_by_uid.values())
        if len(reports) < min_reporters:
            continue

        sub_reporter_count = sum(1 for report in reports if report.has_sub)
        dub_reporter_count = sum(1 for report in reports if report.has_dub)
        has_sub = sub_reporter_count >= min_reporters
        has_dub = dub_reporter_count >= min_reporters
        # Total group quorum is not sufficient to promote a mode. For example,
        # one SUB-only report plus one DUB-only report must not globally claim
        # either mode until that specific mode has independent corroboration.
        if not has_sub and not has_dub:
            continue

        latest = max(report.verified_at for report in reports)
        candidates.append(
            {
                "malId": mal_id,
                "title": _pick_text(report.title for report in reports),
                "normalizedTitle": normalized_title,
                "providerId": provider_id,
                "providerName": _pick_text(report.provider_name for report in reports),
                "providerTitle": _pick_text(report.provider_title for report in reports),
                "hasSub": has_sub,
                "hasDub": has_dub,
                "verifiedAt": latest.isoformat().replace("+00:00", "Z"),
                "reporterCount": len(reports),
                "subReporterCount": sub_reporter_count,
                "dubReporterCount": dub_reporter_count,
            }
        )

    candidates.sort(
        key=lambda item: (
            int(item["malId"]),
            str(item["providerId"]),
            str(item["normalizedTitle"]),
        )
    )
    return {
        "schemaVersion": 1,
        "generatedAt": current.isoformat().replace("+00:00", "Z"),
        "minReporters": min_reporters,
        "maxAgeDays": max_age_days,
        "acceptedReportCount": accepted_reports,
        "candidateCount": len(candidates),
        "candidates": candidates,
    }


def _load_service_account(encoded: str) -> dict[str, Any]:
    raw = base64.b64decode(encoded, validate=True)
    decoded = json.loads(raw.decode("utf-8"))
    if not isinstance(decoded, dict):
        raise ValueError("service account JSON root must be an object")
    if not str(decoded.get("project_id") or "").strip():
        raise ValueError("service account JSON has no project_id")
    return decoded


def fetch_firestore_documents(service_account_info: dict[str, Any]) -> list[dict[str, Any]]:
    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account as google_service_account
    except ImportError as error:  # pragma: no cover
        raise RuntimeError("google-auth is required for Firestore collection") from error

    credentials = google_service_account.Credentials.from_service_account_info(
        service_account_info,
        scopes=["https://www.googleapis.com/auth/datastore"],
    )
    credentials.refresh(Request())
    project_id = str(service_account_info["project_id"]).strip()
    url = (
        f"https://firestore.googleapis.com/v1/projects/{project_id}/"
        "databases/(default)/documents:runQuery"
    )
    body = json.dumps(
        {
            "structuredQuery": {
                "from": [
                    {
                        "collectionId": "catalogDiscoveries",
                        "allDescendants": True,
                    }
                ]
            }
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json",
            "User-Agent": "GoAnime-Toolchains-catalog-consensus/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if not isinstance(payload, list):
        raise RuntimeError("Firestore runQuery returned an unexpected payload")
    return [
        item["document"]
        for item in payload
        if isinstance(item, dict) and isinstance(item.get("document"), dict)
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("build/goanime/catalog_discovery_consensus.json"),
    )
    parser.add_argument("--min-reporters", type=int, default=2)
    parser.add_argument("--max-age-days", type=int, default=14)
    parser.add_argument(
        "--service-account-env",
        default="GOANIME_FIREBASE_SERVICE_ACCOUNT_JSON_B64",
    )
    parser.add_argument(
        "--input-json",
        type=Path,
        help="Offline Firestore runQuery fixture; bypasses service-account access.",
    )
    args = parser.parse_args()

    configured = False
    if args.input_json is not None:
        raw = json.loads(args.input_json.read_text(encoding="utf-8"))
        if not isinstance(raw, list):
            raise SystemExit("--input-json root must be a list")
        documents = [item.get("document", item) for item in raw if isinstance(item, dict)]
        configured = True
    else:
        encoded = os.environ.get(args.service_account_env, "").strip()
        if encoded:
            documents = fetch_firestore_documents(_load_service_account(encoded))
            configured = True
        else:
            documents = []
            print(
                f"{args.service_account_env} is not configured; "
                "emitting an empty consensus artifact."
            )

    consensus = build_consensus(
        documents,
        min_reporters=args.min_reporters,
        max_age_days=args.max_age_days,
    )
    consensus["configured"] = configured
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(consensus, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        "Catalog discovery consensus: "
        f"reports={consensus['acceptedReportCount']} "
        f"candidates={consensus['candidateCount']} configured={configured}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
