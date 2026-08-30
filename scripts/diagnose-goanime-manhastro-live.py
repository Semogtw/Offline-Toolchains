#!/usr/bin/env python3
import json
import urllib.error
import urllib.parse
import urllib.request

BASE_URL = 'https://api2.manhastro.net/dados'
HEADERS = {
    'User-Agent': (
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/139.0.0.0 Safari/537.36'
    ),
    'Accept': 'application/json',
    'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
    'Referer': 'https://manhastro.net/',
}


def fetch(prefix, **params):
    query = urllib.parse.urlencode(params)
    request = urllib.request.Request(f'{BASE_URL}?{query}', headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read(4 * 1024 * 1024 + 1)
            print(f'{prefix}_http_status={response.status}')
    except urllib.error.HTTPError as error:
        print(f'{prefix}_http_status={error.code}')
        return None
    except Exception as error:
        print(f'{prefix}_transport_exception={type(error).__name__}')
        return None
    if len(body) > 4 * 1024 * 1024:
        print(f'{prefix}_body_too_large=true')
        return None
    try:
        payload = json.loads(body.decode('utf-8-sig'))
    except Exception as error:
        print(f'{prefix}_json_exception={type(error).__name__}')
        return None
    if not isinstance(payload, dict):
        print(f'{prefix}_payload_type={type(payload).__name__}')
        return None
    data = payload.get('data')
    meta = payload.get('meta')
    print(f'{prefix}_success={payload.get("success") is True}')
    print(f'{prefix}_data_count={len(data) if isinstance(data, list) else -1}')
    if isinstance(meta, dict):
        for key in ('current_page', 'per_page', 'total', 'last_page', 'has_more'):
            print(f'{prefix}_{key}={meta.get(key)!r}')
    return payload


first = fetch('baseline', page=1, per_page=100)
if isinstance(first, dict) and isinstance(first.get('meta'), dict):
    last_page = first['meta'].get('last_page')
    if isinstance(last_page, int) and last_page > 0:
        fetch('terminal_from_baseline', page=last_page, per_page=100)
        if last_page > 1:
            fetch('penultimate_from_baseline', page=last_page - 1, per_page=100)

for per_page in (200, 500, 1000):
    fetch(f'page_size_{per_page}', page=1, per_page=per_page)
