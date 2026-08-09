#!/usr/bin/env python3
"""Probe the live Goyabu Blogger decoder without logging tokens or media URLs."""

from __future__ import annotations

import json
import re
import sys
import urllib.parse
import urllib.request
import uuid

BASE = "https://goyabu.io"
QUERY = "black clover dublado"
UA = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36"
)
NONCE_RE = re.compile(r'"nonce"\s*:\s*"([a-f0-9]+)"', re.I)
PLAYERS_RE = re.compile(r"var\s+playersData\s*=\s*(\[[\s\S]*?\])\s*;", re.I)
EPISODE_LINK_RE = re.compile(r'"link"\s*:\s*"([^"]+)"', re.I)


def fetch(url: str, *, data: bytes | None = None, referer: str | None = None, content_type: str | None = None):
    headers = {
        "User-Agent": UA,
        "Accept": "application/json,text/html;q=0.9,*/*;q=0.8",
        "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
    }
    if referer:
        headers["Referer"] = referer
    if content_type:
        headers["Content-Type"] = content_type
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data is not None else "GET")
    with urllib.request.urlopen(req, timeout=20) as response:
        return response.status, response.headers.get("Content-Type", ""), response.read(6 * 1024 * 1024).decode("utf-8", errors="replace")


def result_from_body(label: str, status: int, content_type: str, body: str) -> str | None:
    print(f"{label} status={status} type={content_type.split(';', 1)[0] or 'unknown'} bytes={len(body)}")
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        print(f"{label} json=no")
        return None
    if not isinstance(payload, dict):
        print(f"{label} json=scalar")
        return None
    data = payload.get("data")
    play = data.get("play") if isinstance(data, dict) else None
    print(
        f"{label} success={payload.get('success') is True} "
        f"data={type(data).__name__} play_count={len(play) if isinstance(play, list) else 0}"
    )
    if not isinstance(play, list):
        return None
    candidates = [item for item in play if isinstance(item, dict) and item.get("src")]
    if not candidates:
        return None
    candidates.sort(key=lambda item: float(item.get("size") or 0), reverse=True)
    return str(candidates[0]["src"])


def multipart(fields: dict[str, str]) -> tuple[bytes, str]:
    boundary = f"----GoAnime{uuid.uuid4().hex}"
    parts: list[bytes] = []
    for key, value in fields.items():
        parts.extend(
            [
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode(),
                value.encode(),
                b"\r\n",
            ]
        )
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def main() -> int:
    status, _, home = fetch(BASE + "/")
    if status != 200:
        print(f"home status={status}")
        return 2
    nonce_match = NONCE_RE.search(home)
    if not nonce_match:
        print("nonce=missing")
        return 3

    query = urllib.parse.urlencode({"keyword": QUERY, "nonce": nonce_match.group(1)})
    status, _, search_body = fetch(f"{BASE}/wp-json/animeonline/search/?{query}", referer=BASE + "/")
    if status != 200:
        print(f"search status={status}")
        return 4
    payload = json.loads(search_body)
    results = [value for value in payload.values() if isinstance(value, dict) and value.get("url")]
    if not results:
        print("search_result=missing")
        return 5
    exact = next((value for value in results if str(value.get("title", "")).strip().lower() == QUERY), results[0])
    anime_url = urllib.parse.urljoin(BASE + "/", str(exact["url"]))
    status, _, anime_body = fetch(anime_url, referer=BASE + "/")
    if status != 200:
        print(f"anime status={status}")
        return 6
    episode_match = EPISODE_LINK_RE.search(anime_body)
    if not episode_match:
        print("episode=missing")
        return 7
    episode_url = urllib.parse.urljoin(anime_url, episode_match.group(1).replace(r"\/", "/"))
    status, _, episode_body = fetch(episode_url, referer=anime_url)
    if status != 200:
        print(f"episode status={status}")
        return 8
    players_match = PLAYERS_RE.search(episode_body)
    if not players_match:
        print("players=missing")
        return 9
    players = json.loads(players_match.group(1))
    token = next((str(item.get("blogger_token")) for item in players if isinstance(item, dict) and item.get("blogger_token")), "")
    if not token:
        print("blogger_token=missing")
        return 10
    print("blogger_token=present")

    ajax = f"{BASE}/wp-admin/admin-ajax.php"
    fields = {"action": "decode_blogger_video", "token": token}

    encoded = urllib.parse.urlencode(fields).encode()
    try:
        status, content_type, body = fetch(
            ajax,
            data=encoded,
            referer=episode_url,
            content_type="application/x-www-form-urlencoded; charset=UTF-8",
        )
        direct = result_from_body("urlencoded", status, content_type, body)
        if direct:
            print(f"decoder=urlencoded host={urllib.parse.urlparse(direct).hostname or 'unknown'}")
            return 0
    except Exception as exc:
        print(f"urlencoded error={type(exc).__name__}")

    data, content_type = multipart(fields)
    try:
        status, response_type, body = fetch(
            ajax,
            data=data,
            referer=episode_url,
            content_type=content_type,
        )
        direct = result_from_body("multipart", status, response_type, body)
        if direct:
            print(f"decoder=multipart host={urllib.parse.urlparse(direct).hostname or 'unknown'}")
            return 0
    except Exception as exc:
        print(f"multipart error={type(exc).__name__}")

    return 11


if __name__ == "__main__":
    sys.exit(main())
