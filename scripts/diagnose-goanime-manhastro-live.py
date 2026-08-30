#!/usr/bin/env python3
import json
import math
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


def nonempty_text(value):
    return isinstance(value, str) and bool(value.strip())


def valid_id(value):
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    if isinstance(value, float):
        return math.isfinite(value) and value.is_integer()
    return nonempty_text(value)


def fetch(params):
    query = urllib.parse.urlencode(params)
    request = urllib.request.Request(f'{BASE_URL}?{query}', headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            body = response.read(2 * 1024 * 1024 + 1)
            print(f'probe_http_status={response.status}')
    except urllib.error.HTTPError as error:
        print(f'probe_http_status={error.code}')
        return None
    except Exception as error:
        print(f'probe_transport_exception={type(error).__name__}')
        return None
    if len(body) > 2 * 1024 * 1024:
        print('probe_body_too_large=true')
        return None
    try:
        decoded = json.loads(body.decode('utf-8-sig'))
    except Exception as error:
        print(f'probe_json_exception={type(error).__name__}')
        return None
    return decoded if isinstance(decoded, dict) else None


def meta_summary(prefix, payload):
    meta = payload.get('meta') if isinstance(payload, dict) else None
    data = payload.get('data') if isinstance(payload, dict) else None
    print(f'{prefix}_success={payload.get("success") is True}')
    print(f'{prefix}_data_count={len(data) if isinstance(data, list) else -1}')
    if isinstance(meta, dict):
        for key in ('current_page', 'per_page', 'total', 'last_page', 'has_more'):
            print(f'{prefix}_{key}={meta.get(key)!r}')
    return data if isinstance(data, list) else []


page1 = fetch({'page': 1, 'per_page': 100})
page2 = fetch({'page': 2, 'per_page': 100})
if page1 is None or page2 is None:
    raise SystemExit(0)

data1 = meta_summary('page1', page1)
data2 = meta_summary('page2', page2)

invalid_titles = 0
for raw in data1:
    if not isinstance(raw, dict) or not valid_id(raw.get('manga_id')):
        continue
    if not (nonempty_text(raw.get('titulo_brasil')) or nonempty_text(raw.get('titulo'))):
        invalid_titles += 1
print(f'page1_valid_id_untitled_count={invalid_titles}')

seed = next(
    (
        raw
        for raw in data2
        if isinstance(raw, dict)
        and valid_id(raw.get('manga_id'))
        and (nonempty_text(raw.get('titulo_brasil')) or nonempty_text(raw.get('titulo')))
    ),
    None,
)
if seed is None:
    print('seed_available=false')
    raise SystemExit(0)
print('seed_available=true')
seed_id = seed['manga_id']
seed_title = (
    seed.get('titulo_brasil').strip()
    if nonempty_text(seed.get('titulo_brasil'))
    else seed.get('titulo').strip()
)
seed_query = seed_title[: min(8, len(seed_title))]

id_payload = fetch({'page': 1, 'per_page': 100, 'manga_id': seed_id})
if id_payload is not None:
    id_data = meta_summary('id_filter', id_payload)
    id_maps = [raw for raw in id_data if isinstance(raw, dict)]
    print(f'id_filter_all_match={bool(id_maps) and all(raw.get("manga_id") == seed_id for raw in id_maps)}')

name_payload = fetch({'page': 1, 'per_page': 100, 'nome': seed_query})
if name_payload is not None:
    name_data = meta_summary('name_filter', name_payload)
    query_fold = seed_query.casefold()
    titled = [
        raw
        for raw in name_data
        if isinstance(raw, dict)
        and (nonempty_text(raw.get('titulo_brasil')) or nonempty_text(raw.get('titulo')))
    ]
    def title(raw):
        return (
            raw.get('titulo_brasil').strip()
            if nonempty_text(raw.get('titulo_brasil'))
            else raw.get('titulo').strip()
        )
    print(f'name_filter_all_match={bool(titled) and all(query_fold in title(raw).casefold() for raw in titled)}')
