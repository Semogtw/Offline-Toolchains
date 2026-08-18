#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request

_SHA40 = re.compile(r"^[0-9a-f]{40}$")
_WORKFLOW = "goanime-scrapling-provider-cache.yml"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-branch", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--workers", default="8")
    args = parser.parse_args()

    target_branch = args.target_branch.strip()
    source_sha = args.source_sha.strip().lower()
    workers = args.workers.strip()
    if not target_branch:
        raise SystemExit("--target-branch cannot be empty")
    if not _SHA40.fullmatch(source_sha):
        raise SystemExit("--source-sha must be a full 40-character SHA")
    if not workers.isdigit() or not 1 <= int(workers) <= 16:
        raise SystemExit("--workers must be an integer from 1 to 16")

    token = os.environ.get("GITHUB_TOKEN", "")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    if not token or not repository:
        raise SystemExit("GitHub dispatch environment is incomplete")

    workflow = urllib.parse.quote(_WORKFLOW, safe="")
    payload = json.dumps(
        {
            "ref": "main",
            "inputs": {
                "target_branch": target_branch,
                "source_hint": source_sha,
                "workers": workers,
            },
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/actions/workflows/{workflow}/dispatches",
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
            "User-Agent": "goanime-scrapling-toolchains",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            if response.status != 204:
                raise SystemExit(
                    f"unexpected workflow dispatch response: {response.status}"
                )
    except urllib.error.HTTPError as error:
        raise SystemExit(
            f"failed to dispatch canonical gate: HTTP {error.code}"
        ) from None

    print(f"Dispatched canonical gate for source {source_sha[:12]}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
