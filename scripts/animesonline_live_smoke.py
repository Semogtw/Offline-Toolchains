#!/usr/bin/env python3
"""Probe the public AnimesOnline search/episode/playback path safely."""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = "https://animesonlinecc.to"
SEARCH_URL = f"{BASE}/?s=naruto"
UA = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36"
)

HREF_RE = re.compile(r'href=["\']([^"\']+)["\']', re.I)
EPISODE_HREF_RE = re.compile(
    r'<[^>]+class=["\'][^"\']*\bepisodios\b[^"\']*["\'][^>]*>[\s\S]*?'
    r'href=["\']([^"\']+)["\']',
    re.I,
)
IFRAME_RE = re.compile(r'<iframe[^>]+src=["\']([^"\']+)["\']', re.I)
BLOGGER_RE = re.compile(r'https?://[^\s\"\']*blogger\.com/[^\s\"\']+', re.I)
MEDIA_RE = re.compile(r'https?://[^\s\"\']+?\.(?:m3u8|mp4)(?:\?[^\s\"\']*)?', re.I)


def fetch(url: str, *, referer: str | None = None):
    headers = {
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
        "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
    }
    if referer:
        headers["Referer"] = referer
    request = urllib.request.Request(url, headers=headers)
    try:
        response = urllib.request.urlopen(request, timeout=20)
    except urllib.error.HTTPError as error:
        body = error.read(6 * 1024 * 1024).decode("utf-8", errors="replace")
        return error.code, error.geturl(), error.headers.get("Content-Type", ""), body
    with response:
        body = response.read(6 * 1024 * 1024).decode("utf-8", errors="replace")
        return response.status, response.geturl(), response.headers.get("Content-Type", ""), body


def host(url: str) -> str:
    return urllib.parse.urlparse(url).hostname or "unknown"


def resolve(base: str, value: str) -> str:
    return urllib.parse.urljoin(base, value.replace("&amp;", "&"))


def capture(name: str, body: str) -> None:
    directory = os.environ.get("CAPTURE_DIR", "").strip()
    if not directory:
        return
    target = Path(directory)
    target.mkdir(parents=True, exist_ok=True)
    (target / name).write_text(body, encoding="utf-8")


def first_anime_url(search_url: str, body: str) -> str | None:
    for href in HREF_RE.findall(body):
        candidate = resolve(search_url, href)
        parsed = urllib.parse.urlparse(candidate)
        if parsed.hostname and "/anime/" in parsed.path.lower():
            return candidate
    return None


def first_episode_url(anime_url: str, body: str) -> str | None:
    match = EPISODE_HREF_RE.search(body)
    if match:
        return resolve(anime_url, match.group(1))
    for href in HREF_RE.findall(body):
        candidate = resolve(anime_url, href)
        path = urllib.parse.urlparse(candidate).path.lower()
        if "episodio" in path or "episode" in path:
            return candidate
    return None


def player_source(episode_url: str, body: str) -> str | None:
    blogger = BLOGGER_RE.search(body)
    if blogger:
        return blogger.group(0)
    media = MEDIA_RE.search(body)
    if media:
        return media.group(0)
    for match in IFRAME_RE.finditer(body):
        value = match.group(1).strip()
        if not value or "youtube" in value.lower():
            continue
        return resolve(episode_url, value)
    return None


def main() -> int:
    try:
        search_status, final_search, _, search = fetch(SEARCH_URL, referer=BASE + "/")
        capture("search.html", search)
        print(f"search status={search_status} host={host(final_search)} bytes={len(search)}")
        if search_status != 200:
            return 2

        anime_url = first_anime_url(final_search, search)
        if not anime_url:
            print("anime_result=missing")
            return 3
        print(f"anime_result=present host={host(anime_url)}")

        anime_status, final_anime, _, anime = fetch(anime_url, referer=final_search)
        capture("anime.html", anime)
        print(f"anime status={anime_status} host={host(final_anime)}")
        if anime_status != 200:
            return 4

        episode_url = first_episode_url(final_anime, anime)
        if not episode_url:
            print("episode=missing")
            return 5
        print(f"episode=present host={host(episode_url)}")

        episode_status, final_episode, _, episode = fetch(episode_url, referer=final_anime)
        capture("episode.html", episode)
        print(f"episode_page status={episode_status} host={host(final_episode)}")
        if episode_status != 200:
            return 6

        player = player_source(final_episode, episode)
        if not player:
            print("player=missing")
            return 7

        player_host = host(player)
        print(f"player=present host={player_host}")
        lower = player.lower()
        if ".m3u8" in lower or ".mp4" in lower:
            print(f"playback_shape=direct host={player_host}")
            return 0
        if "blogger.com" in player_host:
            print(f"playback_shape=blogger-browser-fallback host={player_host}")
            return 0

        print(f"playback_shape=unrecognized host={player_host}")
        return 8
    except Exception as exc:
        print(f"probe_error={type(exc).__name__}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
