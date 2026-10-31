#!/usr/bin/env python3
"""Keep only the active GoAnime R2 release and MegaPlay catalog.

Uses the live, published R2 manifests as the source of truth. Never touches
other buckets, arbitrary latest/ keys, or metadata required by the app.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from urllib.parse import urlparse

import boto3
from botocore.config import Config

BUCKET = os.environ.get("R2_BUCKET", "")
ACCOUNT = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "")
RELEASE_PREFIX = "releases/"
MEGAPLAY_PREFIX = "latest/megaplay/"
MEGAPLAY_DB = re.compile(r"^latest/megaplay/megaplay_catalog_[0-9a-f]+\.db$")
RELEASE_URL = re.compile(r"/download/([^/]+)/([^/?#]+)$")


def fail(reason: str) -> None:
    raise RuntimeError(reason)


def get_json(s3, key: str) -> tuple[dict, bytes, object]:
    result = s3.get_object(Bucket=BUCKET, Key=key)
    raw = result["Body"].read()
    payload = json.loads(raw)
    if not isinstance(payload, dict):
        fail("Not a JSON object: " + key)
    return payload, raw, result["LastModified"]


def list_prefix(s3, prefix: str) -> list[dict]:
    objects = []
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix, PaginationConfig={"PageSize": 1000}):
        objects.extend(page.get("Contents", []))
    return objects


def validated_state(s3) -> tuple[str, str, bytes, bytes, object, object]:
    update, update_raw, release_time = get_json(s3, "latest/update.json")
    mega, mega_raw, mega_time = get_json(s3, MEGAPLAY_PREFIX + "manifest.json")
    assets = update.get("assets")
    if not isinstance(assets, list) or not assets:
        fail("Published update.json has no assets")
    release_tags = set()
    for asset in assets:
        if not isinstance(asset, dict):
            fail("Malformed update asset")
        match = RELEASE_URL.search(urlparse(str(asset.get("url", ""))).path)
        if not match or match.group(2) != asset.get("fileName"):
            fail("Unexpected release asset URL or filename")
        release_tags.add(match.group(1))
    if len(release_tags) != 1:
        fail("Active update references multiple release tags")
    tag = release_tags.pop()
    if not re.fullmatch(r"(?:release-)?v[0-9]+\.[0-9]+\.[0-9]+(?:[-.][a-zA-Z0-9._-]+)?", tag):
        fail("Unexpected active release tag: " + tag)
    release_prefix = RELEASE_PREFIX + tag + "/"
    release_update, release_raw, _ = get_json(s3, release_prefix + "update.json")
    if release_raw != update_raw or release_update.get("version") != update.get("version"):
        fail("Active release update differs from published latest/update.json")
    for asset in assets:
        key = release_prefix + asset["fileName"]
        head = s3.head_object(Bucket=BUCKET, Key=key)
        if head["ContentLength"] != asset.get("sizeBytes"):
            fail("Published release asset missing or wrong size: " + key)

    mega_asset = mega.get("asset", {})
    catalog = urlparse(str(mega_asset.get("url", ""))).path.lstrip("/")
    if not MEGAPLAY_DB.fullmatch(catalog):
        fail("Unexpected MegaPlay active object URL: " + catalog)
    catalog_head = s3.head_object(Bucket=BUCKET, Key=catalog)
    if catalog_head["ContentLength"] != mega_asset.get("sizeBytes"):
        fail("Active MegaPlay catalog missing or wrong size")
    return release_prefix, catalog, update_raw, mega_raw, release_time, mega_time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Delete obsolete files (default: dry run)")
    args = parser.parse_args()
    if not BUCKET or not ACCOUNT:
        fail("R2_BUCKET and CLOUDFLARE_ACCOUNT_ID are required")
    if BUCKET != "goanime-releases":
        fail("Refusing to run outside goanime-releases")
    s3 = boto3.client(
        "s3",
        endpoint_url=f"https://{ACCOUNT}.r2.cloudflarestorage.com",
        region_name="auto",
        config=Config(retries={"max_attempts": 5, "mode": "standard"}),
    )
    release_prefix, catalog, update_raw, mega_raw, release_time, mega_time = validated_state(s3)
    release_objects = list_prefix(s3, RELEASE_PREFIX)
    mega_objects = list_prefix(s3, MEGAPLAY_PREFIX)

    # Protect newer uploads that may be staging while the current pointers
    # still reference an earlier generation.
    obsolete_releases = [
        o for o in release_objects
        if not o["Key"].startswith(release_prefix) and o["LastModified"] < release_time
    ]
    obsolete_catalogs = [
        o for o in mega_objects
        if MEGAPLAY_DB.fullmatch(o["Key"])
        and o["Key"] != catalog and o["LastModified"] < mega_time
    ]
    obsolete = obsolete_releases + obsolete_catalogs
    proposed_bytes = sum(o["Size"] for o in obsolete)
    print(json.dumps({
        "mode": "apply" if args.apply else "dry_run",
        "bucket": BUCKET,
        "protected_release": release_prefix,
        "protected_catalog": catalog,
        "obsolete_releases": len(obsolete_releases),
        "obsolete_catalogs": len(obsolete_catalogs),
        "obsolete_bytes": proposed_bytes,
    }, indent=2), flush=True)

    if args.apply:
        for start in range(0, len(obsolete), 100):
            # A manifest may change in another repository between batches.
            state = validated_state(s3)
            if state[0] != release_prefix or state[1] != catalog or state[2] != update_raw or state[3] != mega_raw:
                fail("Published manifest changed mid-cleanup; stopped safely")
            batch = obsolete[start:start + 100]
            response = s3.delete_objects(
                Bucket=BUCKET,
                Delete={"Objects": [{"Key": o["Key"]} for o in batch], "Quiet": True},
            )
            if response.get("Errors"):
                fail("R2 rejected object deletion: " + json.dumps(response["Errors"]))
            print(f"Deleted {min(start + 100, len(obsolete))}/{len(obsolete)} obsolete objects", flush=True)

    remaining_release = list_prefix(s3, RELEASE_PREFIX)
    remaining_mega = list_prefix(s3, MEGAPLAY_PREFIX)
    old_releases = [o for o in remaining_release if not o["Key"].startswith(release_prefix)]
    old_catalogs = [o for o in remaining_mega if MEGAPLAY_DB.fullmatch(o["Key"]) and o["Key"] != catalog]
    print(json.dumps({
        "verified": args.apply,
        "remaining_old_release_objects": len(old_releases),
        "remaining_old_megaplay_catalogs": len(old_catalogs),
        "remaining_release_objects": len(remaining_release),
        "remaining_megaplay_objects": len(remaining_mega),
        "remaining_release_and_megaplay_bytes": sum(o["Size"] for o in remaining_release + remaining_mega),
    }, indent=2), flush=True)
    if args.apply and (old_releases or old_catalogs):
        fail("Old objects remain: possible concurrent publish, too-new staging files, or incomplete deletion")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
