#!/usr/bin/env python3
"""Verify AniTube x2episodio resolves to a readable direct HLS manifest."""

from __future__ import annotations

import html
import re
import sys
import urllib.parse
import urllib.request

BASE = "https://www.anitube.biz"
EPISODE = f"{BASE}/589734"
UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/126.0 Mobile Safari/537.36"
X2_RE = re.compile(r'href=["\']([^"\']*x2episodio[^"\']*)["\']', re.I)
ANIVIDEO_RE = re.compile(r'src=["\'](https://api\.anivideo\.net/videohls\.php\?[^"\']+)["\']', re.I)


def fetch(url: str, referer: str):
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "*/*",
            "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
            "Referer": referer,
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        body = response.read(2 * 1024 * 1024).decode("utf-8", errors="replace")
        return response.status, response.geturl(), response.headers.get("Content-Type", ""), body


def host(url: str) -> str:
    return urllib.parse.urlparse(url).hostname or "unknown"


def main() -> int:
    try:
        status, episode_url, _, episode = fetch(EPISODE, BASE + "/")
        if status != 200:
            print(f"episode status={status}")
            return 2
        x2 = X2_RE.search(episode)
        if not x2:
            print("x2=missing")
            return 3
        x2_url = urllib.parse.urljoin(episode_url, html.unescape(x2.group(1)))

        status, player_url, _, player = fetch(x2_url, episode_url)
        print(f"player status={status} host={host(player_url)}")
        if status != 200:
            return 4
        iframe = ANIVIDEO_RE.search(player)
        if not iframe:
            print("anivideo=missing")
            return 5
        iframe_url = html.unescape(iframe.group(1))
        params = urllib.parse.parse_qs(urllib.parse.urlparse(iframe_url).query)
        hls_url = (params.get("d") or [""])[0]
        if not hls_url or ".m3u8" not in hls_url.lower():
            print("hls=missing")
            return 6

        status, _, content_type, manifest = fetch(hls_url, iframe_url)
        valid = manifest.lstrip().startswith("#EXTM3U")
        print(
            f"hls status={status} host={host(hls_url)} "
            f"type={content_type.split(';', 1)[0] or 'unknown'} manifest={valid}"
        )
        return 0 if status == 200 and valid else 7
    except Exception as exc:
        print(f"probe_error={type(exc).__name__}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
