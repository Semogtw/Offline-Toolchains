#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import urllib.request

ALLOWED_STATES = {"pending", "success", "failure", "error"}
CONTEXT_PREFIX = "goanime-scrapling/"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", required=True, choices=sorted(ALLOWED_STATES))
    parser.add_argument("--context", required=True)
    parser.add_argument(
        "--description",
        default="Sanitized GoAnime Scrapling workflow status",
    )
    args = parser.parse_args()

    if not args.context.startswith(CONTEXT_PREFIX):
        raise SystemExit(f"context must start with {CONTEXT_PREFIX!r}")
    if len(args.description) > 140:
        raise SystemExit("description must be at most 140 characters")

    token = os.environ.get("GITHUB_TOKEN", "")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    sha = os.environ.get("GITHUB_SHA", "")
    if not token or not repository or not sha:
        raise SystemExit("GitHub status environment is incomplete")

    payload = json.dumps(
        {
            "state": args.state,
            "context": args.context,
            "description": args.description,
        }
    ).encode("utf-8")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/statuses/{sha}",
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
    with urllib.request.urlopen(request, timeout=20) as response:
        if response.status not in {200, 201}:
            raise SystemExit(f"unexpected GitHub status response: {response.status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
