#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import urllib.error
import urllib.request

_SHA40 = re.compile(r"^[0-9a-f]{40}$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-branch", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--reason", default="automatic full gate after green deterministic diagnostics")
    args = parser.parse_args()

    sha = args.source_sha.lower()
    if not _SHA40.fullmatch(sha):
        raise SystemExit("--source-sha must be a full 40-character SHA")
    if not args.target_branch.strip():
        raise SystemExit("--target-branch cannot be empty")

    token = os.environ.get("GITHUB_TOKEN", "")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    run_id = os.environ.get("GITHUB_RUN_ID", "manual")
    if not token or not repository:
        raise SystemExit("GitHub write environment is incomplete")

    path = (
        "triggers/goanime-scrapling-provider-cache/"
        f"diag-{run_id}-{sha[:12]}.request"
    )
    content = (
        f"target_branch={args.target_branch.strip()}\n"
        f"source_hint={sha}\n"
        f"reason={args.reason.strip()}\n"
    ).encode("utf-8")
    payload = json.dumps(
        {
            "message": f"ci(goanime): gate diagnosed source {sha[:12]}",
            "content": base64.b64encode(content).decode("ascii"),
            "branch": "main",
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/contents/{path}",
        data=payload,
        method="PUT",
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
            if response.status not in {200, 201}:
                raise SystemExit(
                    f"unexpected GitHub contents response: {response.status}"
                )
    except urllib.error.HTTPError as error:
        raise SystemExit(
            f"failed to create canonical gate request: HTTP {error.code}"
        ) from None

    print(f"Created source-bound canonical gate request for {sha[:12]}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
