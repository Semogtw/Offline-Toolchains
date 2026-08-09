#!/usr/bin/env python3
"""Verify AniTube x2episodio resolves to a readable direct HLS manifest."""

from __future__ import annotations

import html
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://www.anitube.biz"
EPISODE = f"{BASE}/589734"
UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/126.0 Mobile Safari/537.36"
X2_RE = re.compile(r'href=["\']([^"\']*x2episodio[^"\']*)["\']', re.I)
ANIVIDEO_RE = re.compile(r'src=["\'](https://api\.anivideo\.net/videohls\.php\?[^"\']+)["\']', re.I)


def fetch(url: str, referer: str, *, origin: str | None = None):
    headers = {
        "User-Agent": UA,
        "Accept": "*/*",
        "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
        "Referer": referer,
    }
    if origin:
        headers["Origin"] = origin
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        body = response.read(2 * 1024 * 1024).decode("utf-8", errors="replace")
        return response.status, response.geturl(), response.headers.get("Content-Type", ""), body


def host(url: str) -> str:
    return urllib.parse.urlparse(url).hostname or "unknown"


def origin(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    return f"{parsed.scheme}://{parsed.netloc}"


def try_manifest(label: str, hls_url: str, referer: str, *, request_origin: str | None = None) -> bool:
    try:
        status, _, content_type, manifest = fetch(
            hls_url,
            referer,
            origin=request_origin,
        )
    except urllib.error.HTTPError as exc:
        print(f"{label} http={exc.code} host={host(hls_url)}")
        return False
    except urllib.error.URLError as exc:
        reason = exc.reason
        print(
            f"{label} url_error={type(reason).__name__} "
            f"errno={getattr(reason, 'errno', 'none')} host={host(hls_url)}"
        )
        return False
    except Exception as exc:
        print(f"{label} error={type(exc).__name__} host={host(hls_url)}")
        return False

    valid = manifest.lstrip().startswith("#EXTM3U")
    print(
        f"{label} status={status} host={host(hls_url)} "
        f"type={content_type.split(';', 1)[0] or 'unknown'} manifest={valid}"
    )
    return status == 200 and valid


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

        attempts = [
            ("iframe-referer", iframe_url, None),
            ("iframe-origin", iframe_url, origin(iframe_url)),
            ("player-referer", player_url, None),
            ("player-origin", player_url, origin(player_url)),
        ]
        for label, referer, request_origin in attempts:
            if try_manifest(
                label,
                hls_url,
                referer,
                request_origin=request_origin,
            ):
                return 0
        return 7
    except urllib.error.HTTPError as exc:
        print(f"probe_http={exc.code}")
        return 1
    except urllib.error.URLError as exc:
        reason = exc.reason
        print(
            f"probe_url_error={type(reason).__name__} "
            f"errno={getattr(reason, 'errno', 'none')}"
        )
        return 1
    except Exception as exc:
        print(f"probe_error={type(exc).__name__}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
