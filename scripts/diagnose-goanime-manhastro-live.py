#!/usr/bin/env python3
import json
import math
import sys
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


def describe_text(value):
    if value is None:
        return 'null'
    if not isinstance(value, str):
        return f'type:{type(value).__name__}'
    return f'string_len:{len(value.strip())}'


def fetch_page(page):
    query = urllib.parse.urlencode({'page': page, 'per_page': 100})
    url = f'{BASE_URL}?{query}'
    request = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            status = response.status
            content_type = response.headers.get('content-type', '')
            body = response.read(2 * 1024 * 1024 + 1)
    except urllib.error.HTTPError as error:
        print(f'page_{page}_http_status={error.code}')
        print(f'page_{page}_classification=http_error')
        return None
    except Exception as error:
        print(f'page_{page}_exception_type={type(error).__name__}')
        print(f'page_{page}_classification=transport_exception')
        return None

    print(f'page_{page}_http_status={status}')
    print(f'page_{page}_content_type={content_type}')
    print(f'page_{page}_body_bytes={len(body)}')
    if len(body) > 2 * 1024 * 1024:
        print(f'page_{page}_classification=body_too_large')
        return None
    try:
        decoded = json.loads(body.decode('utf-8-sig'))
    except Exception as error:
        print(f'page_{page}_json_exception_type={type(error).__name__}')
        print(f'page_{page}_classification=invalid_json')
        return None
    if not isinstance(decoded, dict):
        print(f'page_{page}_classification=non_object_json')
        return None
    return decoded


def inspect_page(page, decoded):
    success = decoded.get('success', '<missing>')
    data = decoded.get('data', '<missing>')
    meta = decoded.get('meta', '<missing>')
    print(f'page_{page}_success_value={success!r}')
    print(f'page_{page}_data_type={type(data).__name__}')
    print(f'page_{page}_meta_type={type(meta).__name__}')
    if isinstance(meta, dict):
        print(f'page_{page}_meta_current_page={meta.get("current_page", "<missing>")!r}')
        print(f'page_{page}_meta_per_page={meta.get("per_page", "<missing>")!r}')
        print(f'page_{page}_meta_total={meta.get("total", "<missing>")!r}')
        print(f'page_{page}_meta_last_page={meta.get("last_page", "<missing>")!r}')
        print(f'page_{page}_meta_has_more={meta.get("has_more", "<missing>")!r}')

    if not isinstance(data, list):
        print(f'page_{page}_classification=unexpected_payload_shape')
        return

    invalid_type = 0
    invalid_id = 0
    invalid_title = 0
    first_invalid = None
    for index, raw in enumerate(data):
        if not isinstance(raw, dict):
            invalid_type += 1
            if first_invalid is None:
                first_invalid = (index, None)
            continue
        item_id_valid = valid_id(raw.get('manga_id'))
        title_valid = nonempty_text(raw.get('titulo_brasil')) or nonempty_text(
            raw.get('titulo')
        )
        if not item_id_valid:
            invalid_id += 1
        if not title_valid:
            invalid_title += 1
        if (not item_id_valid or not title_valid) and first_invalid is None:
            first_invalid = (index, raw)

    print(f'page_{page}_data_count={len(data)}')
    print(f'page_{page}_invalid_item_type_count={invalid_type}')
    print(f'page_{page}_invalid_id_count={invalid_id}')
    print(f'page_{page}_invalid_title_count={invalid_title}')
    if first_invalid is None:
        print(f'page_{page}_first_invalid_index=none')
    else:
        index, raw = first_invalid
        print(f'page_{page}_first_invalid_index={index}')
        if isinstance(raw, dict):
            print(f'page_{page}_first_invalid_manga_id_type={type(raw.get("manga_id")).__name__}')
            print(f'page_{page}_first_invalid_titulo={describe_text(raw.get("titulo"))}')
            print(f'page_{page}_first_invalid_titulo_brasil={describe_text(raw.get("titulo_brasil"))}')
            print(
                f'page_{page}_first_invalid_titulo_alternative='
                f'{describe_text(raw.get("titulo_alternative"))}'
            )

    if success is True:
        if invalid_type or invalid_id or invalid_title:
            print(f'page_{page}_classification=strict_item_contract_violation')
        else:
            print(f'page_{page}_classification=adapter_contract_compatible')
    else:
        print(f'page_{page}_classification=success_field_not_true')


for page in (1, 2):
    payload = fetch_page(page)
    if payload is not None:
        inspect_page(page, payload)
