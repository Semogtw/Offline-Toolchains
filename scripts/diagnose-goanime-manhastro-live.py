#!/usr/bin/env python3
import json
import math
import sys
import urllib.error
import urllib.request

url = 'https://api2.manhastro.net/dados'
request = urllib.request.Request(
    url,
    headers={
        'User-Agent': (
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/139.0.0.0 Safari/537.36'
        ),
        'Accept': 'application/json',
        'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
        'Referer': 'https://manhastro.net/',
    },
)


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


try:
    with urllib.request.urlopen(request, timeout=25) as response:
        status = response.status
        content_type = response.headers.get('content-type', '')
        body = response.read(2 * 1024 * 1024 + 1)
except urllib.error.HTTPError as error:
    print(f'http_status={error.code}')
    print(f'content_type={error.headers.get("content-type", "")}')
    print('classification=http_error')
    sys.exit(0)
except Exception as error:
    print(f'exception_type={type(error).__name__}')
    print('classification=transport_exception')
    sys.exit(0)

print(f'http_status={status}')
print(f'content_type={content_type}')
print(f'body_bytes={len(body)}')
if len(body) > 2 * 1024 * 1024:
    print('classification=body_too_large')
    sys.exit(0)

try:
    decoded = json.loads(body.decode('utf-8-sig'))
except Exception as error:
    print(f'json_exception_type={type(error).__name__}')
    print('classification=invalid_json')
    sys.exit(0)

print(f'json_type={type(decoded).__name__}')
if not isinstance(decoded, dict):
    print('classification=non_object_json')
    sys.exit(0)

safe_keys = sorted(str(key) for key in decoded.keys())
print('top_level_keys=' + ','.join(safe_keys))
success = decoded.get('success', '<missing>')
print(f'success_type={type(success).__name__}')
print(f'success_value={success!r}')
data = decoded.get('data', '<missing>')
print(f'data_type={type(data).__name__}')

meta = decoded.get('meta', '<missing>')
print(f'meta_type={type(meta).__name__}')
if isinstance(meta, dict):
    print('meta_keys=' + ','.join(sorted(str(key) for key in meta.keys())))
    for key in (
        'current_page',
        'page',
        'per_page',
        'total',
        'last_page',
        'from',
        'to',
    ):
        value = meta.get(key, '<missing>')
        if isinstance(value, (str, int, float, bool)) or value == '<missing>':
            print(f'meta_{key}={value!r}')

if isinstance(data, list):
    print(f'data_count={len(data)}')
    invalid_type = 0
    invalid_id = 0
    invalid_title = 0
    first_invalid_index = None
    for index, raw in enumerate(data):
        if not isinstance(raw, dict):
            invalid_type += 1
            if first_invalid_index is None:
                first_invalid_index = index
            continue
        item_id_valid = valid_id(raw.get('manga_id'))
        title_valid = nonempty_text(raw.get('titulo_brasil')) or nonempty_text(
            raw.get('titulo')
        )
        if not item_id_valid:
            invalid_id += 1
        if not title_valid:
            invalid_title += 1
        if (not item_id_valid or not title_valid) and first_invalid_index is None:
            first_invalid_index = index
    print(f'invalid_item_type_count={invalid_type}')
    print(f'invalid_id_count={invalid_id}')
    print(f'invalid_title_count={invalid_title}')
    print(
        'first_invalid_index='
        + ('none' if first_invalid_index is None else str(first_invalid_index))
    )

if success is True and isinstance(data, list):
    if invalid_type or invalid_id or invalid_title:
        print('classification=strict_item_contract_violation')
    else:
        print('classification=adapter_contract_compatible')
elif isinstance(data, list) and success == '<missing>':
    print('classification=success_field_missing')
elif isinstance(data, list):
    print('classification=success_field_not_true')
else:
    print('classification=unexpected_payload_shape')
