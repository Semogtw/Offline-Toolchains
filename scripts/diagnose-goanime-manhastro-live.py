#!/usr/bin/env python3
import json
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
if isinstance(data, list):
    print(f'data_count={len(data)}')
    if data:
        first = data[0]
        print(f'first_item_type={type(first).__name__}')
        if isinstance(first, dict):
            print('first_item_keys=' + ','.join(sorted(str(key) for key in first.keys())))

if success is True and isinstance(data, list):
    print('classification=adapter_contract_compatible')
elif isinstance(data, list) and success == '<missing>':
    print('classification=success_field_missing')
elif isinstance(data, list):
    print('classification=success_field_not_true')
else:
    print('classification=unexpected_payload_shape')
