#!/usr/bin/env python3
"""Probe Goyabu's AJAX decoder with browser-like cookies/origin; never log secrets."""

from __future__ import annotations

import http.cookiejar
import json
import re
import sys
import urllib.parse
import urllib.request
import uuid

BASE = "https://goyabu.io"
QUERY = "black clover dublado"
UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/126.0 Mobile Safari/537.36"
NONCE_RE = re.compile(r'"nonce"\s*:\s*"([a-f0-9]+)"', re.I)
EP_RE = re.compile(r'"link"\s*:\s*"([^"]+)"', re.I)
PLAYERS_RE = re.compile(r"var\s+playersData\s*=\s*(\[[\s\S]*?\])\s*;", re.I)

cookies = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookies))


def call(url: str, *, data: bytes | None = None, referer: str | None = None, content_type: str | None = None):
    headers = {
        "User-Agent": UA,
        "Accept": "application/json,text/html;q=0.9,*/*;q=0.8",
        "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
    }
    if referer:
        headers["Referer"] = referer
    if data is not None:
        headers["Origin"] = BASE
        headers["X-Requested-With"] = "XMLHttpRequest"
    if content_type:
        headers["Content-Type"] = content_type
    request = urllib.request.Request(url, data=data, headers=headers, method="POST" if data is not None else "GET")
    with opener.open(request, timeout=20) as response:
        return response.status, response.headers.get("Content-Type", ""), response.read(6 * 1024 * 1024).decode("utf-8", errors="replace")


def multipart(fields: dict[str, str]):
    boundary = f"----GoAnime{uuid.uuid4().hex}"
    chunks: list[bytes] = []
    for key, value in fields.items():
        chunks.append(f"--{boundary}\r\n".encode())
        chunks.append(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode())
        chunks.append(value.encode())
        chunks.append(b"\r\n")
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def inspect(label: str, status: int, content_type: str, body: str) -> str | None:
    print(f"{label} status={status} type={content_type.split(';', 1)[0] or 'unknown'} bytes={len(body)} cookies={len(cookies)}")
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        print(f"{label} json=no")
        return None
    if not isinstance(payload, dict):
        print(f"{label} json=scalar")
        return None
    data = payload.get("data")
    message = data.get("message") if isinstance(data, dict) else None
    play = data.get("play") if isinstance(data, dict) else None
    if message:
        safe = re.sub(r"https?://\S+", "<url>", str(message))[:160]
        print(f"{label} message={safe}")
    print(f"{label} success={payload.get('success') is True} play_count={len(play) if isinstance(play, list) else 0}")
    if not isinstance(play, list):
        return None
    valid = [item for item in play if isinstance(item, dict) and item.get("src")]
    if not valid:
        return None
    valid.sort(key=lambda item: float(item.get("size") or 0), reverse=True)
    return str(valid[0]["src"])


def main() -> int:
    status, _, home = call(BASE + "/")
    if status != 200:
        return 2
    nonce = NONCE_RE.search(home)
    if not nonce:
        return 3
    params = urllib.parse.urlencode({"keyword": QUERY, "nonce": nonce.group(1)})
    status, _, search_body = call(f"{BASE}/wp-json/animeonline/search/?{params}", referer=BASE + "/")
    if status != 200:
        return 4
    search = json.loads(search_body)
    results = [value for value in search.values() if isinstance(value, dict) and value.get("url")]
    if not results:
        return 5
    exact = next((value for value in results if str(value.get("title", "")).strip().lower() == QUERY), results[0])
    anime_url = urllib.parse.urljoin(BASE + "/", str(exact["url"]))
    status, _, anime = call(anime_url, referer=BASE + "/")
    if status != 200:
        return 6
    ep = EP_RE.search(anime)
    if not ep:
        return 7
    episode_url = urllib.parse.urljoin(anime_url, ep.group(1).replace(r"\/", "/"))
    status, _, episode = call(episode_url, referer=anime_url)
    if status != 200:
        return 8
    players_match = PLAYERS_RE.search(episode)
    if not players_match:
        return 9
    players = json.loads(players_match.group(1))
    token = next((str(item.get("blogger_token")) for item in players if isinstance(item, dict) and item.get("blogger_token")), "")
    if not token:
        return 10
    print(f"session cookies={len(cookies)} token=present")

    fields = {"action": "decode_blogger_video", "token": token}
    ajax = f"{BASE}/wp-admin/admin-ajax.php"
    encoded = urllib.parse.urlencode(fields).encode()
    status, content_type, body = call(
        ajax,
        data=encoded,
        referer=episode_url,
        content_type="application/x-www-form-urlencoded; charset=UTF-8",
    )
    direct = inspect("urlencoded-session", status, content_type, body)
    if direct:
        print(f"decoder=urlencoded-session host={urllib.parse.urlparse(direct).hostname or 'unknown'}")
        return 0

    body_bytes, multipart_type = multipart(fields)
    status, content_type, body = call(
        ajax,
        data=body_bytes,
        referer=episode_url,
        content_type=multipart_type,
    )
    direct = inspect("multipart-session", status, content_type, body)
    if direct:
        print(f"decoder=multipart-session host={urllib.parse.urlparse(direct).hostname or 'unknown'}")
        return 0
    return 11


if __name__ == "__main__":
    sys.exit(main())
