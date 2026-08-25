#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import unicodedata
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from goanime_catalog_discovery_consensus import (
    _firestore_value,
    _load_service_account,
    _parse_time,
    fetch_firestore_documents,
)

_ALLOWED_PROVIDERS = frozenset(
    {
        "ptbr.arthurscan",
        "ptbr.astratoons",
        "ptbr.capitoons",
        "ptbr.hqnow",
        "ptbr.hipertoon",
        "ptbr.kamisamaexplorer",
        "ptbr.kivaratoons",
        "ptbr.leituramanga",
        "ptbr.ler999",
        "ptbr.littletyrant",
        "ptbr.maidscan",
        "ptbr.mangadash",
        "ptbr.mangaflix",
        "ptbr.mangalivreblog",
        "ptbr.mangalivreorg",
        "ptbr.ninjascan",
    }
)
_ALLOWED_CONTENT_KINDS = frozenset({"imageSequence", "pdfDocument"})
_MAX_TITLE_LENGTH = 300
_MAX_ID_LENGTH = 300
_MAX_CLOCK_SKEW = timedelta(minutes=5)


def _normalize_title(value: object) -> str:
    text = str(value or "").strip().lower()
    text = "".join(
        character
        for character in unicodedata.normalize("NFKD", text)
        if not unicodedata.combining(character)
    )
    text = text.replace("&", " and ")
    for character in "'´`’":
        text = text.replace(character, "")
    words = text.replace("-", " ").replace("_", " ").split()
    filtered = [
        word
        for word in words
        if word not in {"dublado", "legendado", "dub", "sub"}
    ]
    title = " ".join(filtered)
    if "todos os episodios" in title:
        title = title.replace("todos os episodios", " ")
    return " ".join(title.split())


def _value(document: dict[str, Any], key: str) -> object:
    fields = document.get("fields")
    if not isinstance(fields, dict):
        return None
    return _firestore_value(fields.get(key))


def _reporter_uid(document: dict[str, Any]) -> str:
    name = str(document.get("name") or "")
    marker = "/users/"
    if marker not in name:
        return ""
    return name.split(marker, 1)[1].split("/", 1)[0].strip()


def _content_kinds(raw: object) -> tuple[str, ...]:
    if isinstance(raw, str):
        values = [item.strip() for item in raw.split(",")]
    elif isinstance(raw, list):
        values = [str(item).strip() for item in raw]
    else:
        values = []
    return tuple(sorted(set(value for value in values if value)))


class MangaDiscoveryReport:
    def __init__(
        self,
        *,
        reporter_uid: str,
        source_id: str,
        manga_id: str,
        title: str,
        normalized_title: str,
        provider_title: str,
        content_kinds: tuple[str, ...],
        sample_chapter_id: str,
        verified_at: datetime,
    ) -> None:
        self.reporter_uid = reporter_uid
        self.source_id = source_id
        self.manga_id = manga_id
        self.title = title
        self.normalized_title = normalized_title
        self.provider_title = provider_title
        self.content_kinds = content_kinds
        self.sample_chapter_id = sample_chapter_id
        self.verified_at = verified_at

    @property
    def group_key(self) -> tuple[str, str, str]:
        return self.source_id, self.manga_id, self.normalized_title


def parse_report(
    document: dict[str, Any], *, now: datetime, max_age: timedelta
) -> MangaDiscoveryReport | None:
    reporter_uid = _reporter_uid(document)
    source_id = str(_value(document, "sourceId") or "").strip().lower()
    manga_id = str(_value(document, "mangaId") or "").strip()
    title = str(_value(document, "title") or "").strip()
    normalized_title = str(_value(document, "normalizedTitle") or "").strip()
    provider_title = str(_value(document, "providerTitle") or "").strip()
    sample_chapter_id = str(_value(document, "sampleChapterId") or "").strip()
    verified_at = _parse_time(_value(document, "verifiedAt"))
    content_kinds = _content_kinds(_value(document, "contentKinds"))
    if (
        not reporter_uid
        or source_id not in _ALLOWED_PROVIDERS
        or not manga_id
        or len(manga_id) > _MAX_ID_LENGTH
        or not title
        or len(title) > _MAX_TITLE_LENGTH
        or not provider_title
        or not sample_chapter_id
        or not normalized_title
        or normalized_title != _normalize_title(title)
        or not content_kinds
        or any(kind not in _ALLOWED_CONTENT_KINDS for kind in content_kinds)
        or _value(document, "schemaVersion") != 1
        or _value(document, "readabilityVerified") is not True
        or verified_at is None
    ):
        return None
    if verified_at > now + _MAX_CLOCK_SKEW or now - verified_at > max_age:
        return None
    return MangaDiscoveryReport(
        reporter_uid=reporter_uid,
        source_id=source_id,
        manga_id=manga_id,
        title=title,
        normalized_title=normalized_title,
        provider_title=provider_title,
        content_kinds=content_kinds,
        sample_chapter_id=sample_chapter_id,
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

    current = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    max_age = timedelta(days=max_age_days)
    grouped: dict[tuple[str, str, str], dict[str, MangaDiscoveryReport]] = defaultdict(dict)
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
    for (source_id, manga_id, normalized_title), reports_by_uid in grouped.items():
        reports = list(reports_by_uid.values())
        if len(reports) < min_reporters:
            continue
        kind_counts = Counter(
            kind for report in reports for kind in report.content_kinds
        )
        promoted_kinds = sorted(
            kind for kind, count in kind_counts.items() if count >= min_reporters
        )
        if not promoted_kinds:
            continue
        latest = max(report.verified_at for report in reports)
        candidates.append(
            {
                "sourceId": source_id,
                "mangaId": manga_id,
                "title": _pick_text(report.title for report in reports),
                "normalizedTitle": normalized_title,
                "providerTitle": _pick_text(report.provider_title for report in reports),
                "contentKinds": promoted_kinds,
                "sampleChapterId": min(
                    (
                        report.sample_chapter_id
                        for report in reports
                        if set(report.content_kinds).intersection(promoted_kinds)
                    ),
                    default="",
                ),
                "verifiedAt": latest.isoformat().replace("+00:00", "Z"),
                "reporterCount": len(reports),
                "contentKindReporterCounts": {
                    kind: kind_counts[kind] for kind in promoted_kinds
                },
            }
        )

    candidates.sort(
        key=lambda item: (
            str(item["sourceId"]),
            str(item["mangaId"]),
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--min-reporters", type=int, default=2)
    parser.add_argument("--max-age-days", type=int, default=14)
    parser.add_argument(
        "--service-account-env",
        default="GOANIME_FIREBASE_SERVICE_ACCOUNT_JSON_B64",
    )
    parser.add_argument("--input-json", type=Path)
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
            documents = fetch_firestore_documents(
                _load_service_account(encoded), collection_id="mangaCatalogDiscoveries"
            )
            configured = True
        else:
            documents = []
            print(
                f"{args.service_account_env} is not configured; "
                "emitting an empty Manga consensus artifact."
            )

    consensus = build_consensus(
        documents,
        min_reporters=args.min_reporters,
        max_age_days=args.max_age_days,
    )
    consensus["configured"] = configured
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(consensus, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "Manga catalog discovery consensus: "
        f"reports={consensus['acceptedReportCount']} "
        f"candidates={consensus['candidateCount']} configured={configured}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
