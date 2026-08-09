#!/usr/bin/env python3
"""Probe AniTube.biz search/list/playback and capture private live fixtures."""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request

BASE = "https://www.anitube.biz"
KNOWN_EPISODE = f"{BASE}/589734"
SEARCH_URL = f"{BASE}/?s=naruto"
UA = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/126.0 Mobile Safari/537.36"
PLAYER_LINK_RE = re.compile(r'href=["\']([^"\']*x2episodio[^"\']*)["\']', re.I)
LIST_LINK_RE = re.compile(r'href=["\']([^"\']+)["\'][^>]*>\s*<div[^>]*>[^<]*<span[^>]*>Lista Completa</span>', re.I)
IFRAME_RE = re.compile(r'<iframe[^>]+src=["\']([^"\']+)["\']', re.I)
MEDIA_RE = re.compile(r'https?://[^\s\"\']+?\.(?:m3u8|mp4)(?:\?[^\s\"\']*)?', re.I)
BLOGGER_RE = re.compile(r'https?://[^\s\"\']*blogger\.com/[^\s\"\']+', re.I)


def fetch(url: str, *, referer: str | None = None):
    headers = {
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
        "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
    }
    if referer:
        headers["Referer"] = referer
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        body = response.read(6 * 1024 * 1024).decode("utf-8", errors="replace")
        return response.status, response.geturl(), response.headers.get("Content-Type", ""), body


def host(url: str) -> str:
    return urllib.parse.urlparse(url).hostname or "unknown"


def capture(name: str, body: str) -> None:
    directory = os.environ.get("CAPTURE_DIR", "").strip()
    if not directory:
        return
    target = Path(directory)
    target.mkdir(parents=True, exist_ok=True)
    (target / name).write_text(body, encoding="utf-8")


def extract_list_url(episode_url: str, episode: str) -> str | None:
    match = LIST_LINK_RE.search(episode)
    if match:
        return urllib.parse.urljoin(episode_url, match.group(1))
    # Current pages use a tooltip anchor containing a category URL immediately
    # before the literal Lista Completa label.
    match = re.search(
        r'<a\s+href=["\']([^"\']+/categoria/[^"\']+)["\'][^>]*>[\s\S]{0,500}?Lista Completa',
        episode,
        re.I,
    )
    return urllib.parse.urljoin(episode_url, match.group(1)) if match else None


def direct_hls_from_iframe(iframe_url: str) -> str | None:
    parsed = urllib.parse.urlparse(iframe_url)
    if parsed.hostname != "api.anivideo.net":
        return None
    params = urllib.parse.parse_qs(parsed.query)
    candidate = (params.get("d") or [None])[0]
    if not candidate:
        return None
    decoded = urllib.parse.unquote(candidate)
    return decoded if ".m3u8" in decoded.lower() else None


def main() -> int:
    try:
        search_status, _, _, search = fetch(SEARCH_URL, referer=BASE + "/")
        print(f"search status={search_status} host={host(SEARCH_URL)} bytes={len(search)}")
        capture("search.html", search)
        if search_status != 200 or 'class="aniItem"' not in search:
            return 1

        status, episode_url, content_type, episode = fetch(KNOWN_EPISODE, referer=BASE + "/")
        print(f"episode status={status} host={host(episode_url)} type={content_type.split(';', 1)[0]}")
        capture("episode.html", episode)
        if status != 200:
            return 2

        list_url = extract_list_url(episode_url, episode)
        if not list_url:
            print("episode_list=missing")
            return 3
        list_status, _, _, list_page = fetch(list_url, referer=episode_url)
        print(f"episode_list status={list_status} host={host(list_url)} items={list_page.count('class=\"aniItem\"')}")
        capture("episode-list.html", list_page)
        if list_status != 200 or 'class="aniItem"' not in list_page:
            return 4

        player_match = PLAYER_LINK_RE.search(episode)
        if not player_match:
            print("x2episodio=missing")
            return 5
        player_url = urllib.parse.urljoin(episode_url, player_match.group(1).replace("&amp;", "&"))
        print(f"x2episodio=present host={host(player_url)}")

        status, final_url, content_type, player = fetch(player_url, referer=episode_url)
        print(f"player status={status} host={host(final_url)} type={content_type.split(';', 1)[0]} bytes={len(player)}")
        capture("player-response.html", player)
        capture("player-final-url.txt", final_url)
        if status != 200:
            return 6

        for iframe_match in IFRAME_RE.finditer(player):
            iframe_url = urllib.parse.urljoin(final_url, iframe_match.group(1))
            hls = direct_hls_from_iframe(iframe_url)
            if hls:
                manifest_status, _, manifest_type, manifest = fetch(hls, referer=iframe_url)
                is_hls = manifest.lstrip().startswith("#EXTM3U")
                print(
                    f"playback_shape=anitube-hls host={host(hls)} "
                    f"status={manifest_status} type={manifest_type.split(';', 1)[0]} manifest={is_hls}"
                )
                return 0 if manifest_status == 200 and is_hls else 7

        media = MEDIA_RE.search(player)
        if media:
            print(f"playback_shape=direct host={host(media.group(0))}")
            return 0
        blogger = BLOGGER_RE.search(player)
        if blogger:
            print(f"playback_shape=blogger host={host(blogger.group(0))}")
            return 0
        iframe = IFRAME_RE.search(player)
        if iframe:
            iframe_url = urllib.parse.urljoin(final_url, iframe.group(1))
            print(f"playback_shape=iframe host={host(iframe_url)}")
            return 0

        print("playback_shape=unresolved")
        return 8
    except Exception as exc:
        print(f"probe_error={type(exc).__name__}")
        return 9


if __name__ == "__main__":
    sys.exit(main())
