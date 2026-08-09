#!/usr/bin/env python3
"""Live smoke probe for the public Goyabu source.

Only stage/status/host information is printed. Failed-page captures stay in
the ephemeral runner directory so the workflow can encrypt them before upload.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass

BASE = "https://goyabu.io"
QUERY = "black clover dublado"
UA = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36"
)

NONCE_RE = re.compile(r'"nonce"\s*:\s*"([a-f0-9]+)"', re.I)
EPISODE_URL_RES = [
    re.compile(r'"link"\s*:\s*"([^"]+)"', re.I),
    re.compile(r"link\s*:\s*['\"]([^'\"]+)['\"]", re.I),
    re.compile(r'href=["\']([^"\']*(?:/episodio/|/episode/)[^"\']*)["\']', re.I),
]
PLAYERS_DATA_RE = re.compile(r"var\s+playersData\s*=\s*(\[[\s\S]*?\])\s*;", re.I)
BLOGGER_RE = re.compile(r"https?://[^\s\"']*blogger\.com/[^\s\"']+", re.I)
MEDIA_RE = re.compile(r"https?://[^\s\"']+?\.(?:m3u8|mp4)(?:\?[^\s\"']*)?", re.I)
VIDEO_CONFIG_RE = re.compile(r"var\s+VIDEO_CONFIG\s*=\s*(\{[\s\S]*?\});", re.I)
PLAY_URL_RE = re.compile(r'"play_url"\s*:\s*"([^"]+)"', re.I)


@dataclass(frozen=True)
class Response:
    status: int
    url: str
    body: str


def request(url: str, *, method: str = "GET", data: bytes | None = None, referer: str | None = None) -> Response:
    headers = {
        "User-Agent": UA,
        "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
        "Accept-Language": "pt-BR,pt;q=0.9,en;q=0.7",
    }
    if referer:
        headers["Referer"] = referer
    if data is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-8"
        headers["X-Requested-With"] = "XMLHttpRequest"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=20) as resp:
        raw = resp.read(6 * 1024 * 1024)
        return Response(resp.status, resp.geturl(), raw.decode("utf-8", errors="replace"))


def safe_host(url: str) -> str:
    return urllib.parse.urlparse(url).hostname or "unknown"


def resolve(base: str, value: str) -> str:
    return urllib.parse.urljoin(base, value.replace(r"\/", "/"))


def normalize_title(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", value.lower()).strip()


def capture_episode_html(body: str) -> None:
    capture_dir = os.environ.get("CAPTURE_DIR", "").strip()
    if not capture_dir:
        return
    output = Path(capture_dir)
    output.mkdir(parents=True, exist_ok=True)
    (output / "episode.html").write_text(body, encoding="utf-8")


def choose_search_result(payload: dict) -> dict | None:
    results = [v for v in payload.values() if isinstance(v, dict) and v.get("url")]
    if not results:
        return None
    wanted = normalize_title(QUERY)
    exact = next((v for v in results if normalize_title(str(v.get("title", ""))) == wanted), None)
    return exact or results[0]


def first_episode_url(page_url: str, body: str) -> str | None:
    for pattern in EPISODE_URL_RES:
        for match in pattern.finditer(body):
            candidate = resolve(page_url, match.group(1))
            parsed = urllib.parse.urlparse(candidate)
            if parsed.scheme in {"http", "https"} and parsed.hostname:
                return candidate
    return None


def player_data(episode_url: str, body: str) -> tuple[list[str], str | None]:
    candidates: list[str] = []
    blogger_token: str | None = None
    match = PLAYERS_DATA_RE.search(body)
    if match:
        try:
            data = json.loads(match.group(1))
        except json.JSONDecodeError:
            data = []
        if isinstance(data, list):
            for item in data:
                if not isinstance(item, dict):
                    continue
                value = str(item.get("url") or "").strip()
                if value:
                    candidates.append(resolve(episode_url, value))
                token = str(item.get("blogger_token") or "").strip()
                if token and blogger_token is None:
                    blogger_token = token
    candidates.extend(resolve(episode_url, m.group(0)) for m in BLOGGER_RE.finditer(body))
    candidates.extend(resolve(episode_url, m.group(0)) for m in MEDIA_RE.finditer(body))
    return list(dict.fromkeys(candidates)), blogger_token


def decode_goyabu_blogger(token: str, referer: str) -> str | None:
    form = urllib.parse.urlencode({"action": "decode_blogger_video", "token": token}).encode()
    response = request(
        f"{BASE}/wp-admin/admin-ajax.php",
        method="POST",
        data=form,
        referer=referer,
    )
    if response.status != 200:
        return None
    try:
        payload = json.loads(response.body)
    except json.JSONDecodeError:
        return None
    if not isinstance(payload, dict) or not payload.get("success"):
        return None
    data = payload.get("data")
    if not isinstance(data, dict):
        return None
    play = data.get("play")
    if not isinstance(play, list):
        return None
    candidates = [item for item in play if isinstance(item, dict) and item.get("src")]
    if not candidates:
        return None
    candidates.sort(key=lambda item: float(item.get("size") or 0), reverse=True)
    return str(candidates[0]["src"])


def blogger_has_media(player_url: str) -> bool:
    response = request(player_url, referer=BASE + "/")
    if response.status != 200:
        return False
    if MEDIA_RE.search(response.body) or PLAY_URL_RE.search(response.body):
        return True
    config = VIDEO_CONFIG_RE.search(response.body)
    if not config:
        return False
    try:
        payload = json.loads(config.group(1))
    except json.JSONDecodeError:
        return False
    streams = payload.get("streams") if isinstance(payload, dict) else None
    return isinstance(streams, list) and any(
        isinstance(stream, dict) and bool(stream.get("play_url")) for stream in streams
    )


def main() -> int:
    try:
        home = request(BASE + "/")
        print(f"home status={home.status} host={safe_host(home.url)}")
        if home.status != 200:
            return 2
        nonce_match = NONCE_RE.search(home.body)
        if not nonce_match:
            print("nonce=missing")
            return 3
        nonce = nonce_match.group(1)
        print("nonce=present")

        params = urllib.parse.urlencode({"keyword": QUERY, "nonce": nonce})
        search = request(f"{BASE}/wp-json/animeonline/search/?{params}", referer=BASE + "/")
        print(f"search status={search.status} host={safe_host(search.url)}")
        if search.status != 200:
            return 4
        payload = json.loads(search.body)
        if not isinstance(payload, dict):
            print("search_shape=unexpected")
            return 5
        result = choose_search_result(payload)
        if not result:
            print("search_result=missing")
            return 6
        anime_url = resolve(BASE + "/", str(result["url"]))
        print(f"anime_result=present host={safe_host(anime_url)}")

        anime = request(anime_url, referer=BASE + "/")
        print(f"anime status={anime.status} host={safe_host(anime.url)}")
        if anime.status != 200:
            return 7
        episode_url = first_episode_url(anime.url, anime.body)
        if not episode_url:
            capture_episode_html(anime.body)
            print("episode=missing")
            return 8
        print(f"episode=present host={safe_host(episode_url)}")

        episode = request(episode_url, referer=anime.url)
        print(f"episode_page status={episode.status} host={safe_host(episode.url)}")
        if episode.status != 200:
            return 9
        candidates, token = player_data(episode.url, episode.body)
        if not candidates and not token:
            capture_episode_html(episode.body)
            print("player=missing")
            return 10
        hosts = sorted({safe_host(c) for c in candidates})
        print(f"player=present count={len(candidates)} hosts={','.join(hosts) if hosts else 'token-only'}")

        if token:
            try:
                decoded_url = decode_goyabu_blogger(token, episode.url)
            except Exception as exc:
                print(f"goyabu_ajax_error={type(exc).__name__}")
            else:
                if decoded_url:
                    print(f"playback_shape=goyabu-ajax host={safe_host(decoded_url)}")
                    return 0

        blogger_fallback: str | None = None
        for candidate in candidates:
            lower = candidate.lower()
            if ".m3u8" in lower or ".mp4" in lower:
                print(f"playback_shape=direct host={safe_host(candidate)}")
                return 0
            if "blogger.com" in safe_host(candidate):
                blogger_fallback = candidate
                try:
                    if blogger_has_media(candidate):
                        print(f"playback_shape=blogger-resolvable host={safe_host(candidate)}")
                        return 0
                except Exception as exc:
                    print(f"blogger_probe_error={type(exc).__name__}")

        # GoyabuService intentionally returns the Blogger embed when its direct
        # decoder cannot resolve media. VideoPlaybackResolver marks this host as
        # browser-only, so a public Blogger player is still a usable provider
        # fallback even when runner-side direct extraction is unavailable.
        if blogger_fallback:
            print(f"playback_shape=blogger-browser-fallback host={safe_host(blogger_fallback)}")
            return 0

        capture_episode_html(episode.body)
        print("playback_shape=unresolved")
        return 11
    except Exception as exc:
        print(f"probe_error={type(exc).__name__}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
