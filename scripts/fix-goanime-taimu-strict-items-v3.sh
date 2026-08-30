#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

path = Path('scripts/fix-goanime-taimu-strict-items.sh')
text = path.read_text(encoding='utf-8')
write_anchor = "path.write_text(text, encoding='utf-8')"
cleanup_patch = """cleanup = {
    \"_httpsText(item?['cover'])\": \"_httpsText(item['cover'])\",
    \"_text(item?['title']) ??\": \"_text(item['title']) ??\",
    \"_number(item?['volume'])\": \"_number(item['volume'])\",
    \"item?['published_at']\": \"item['published_at']\",
    \"item?['publishedAt']\": \"item['publishedAt']\",
    \"item?['created_at']\": \"item['created_at']\",
}
for old, new in cleanup.items():
    if text.count(old) != 1:
        raise SystemExit(f'unexpected Taimu nullable access {old}: {text.count(old)}')
    text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')"""
if text.count(write_anchor) != 1:
    raise SystemExit(f'unexpected Taimu patch write boundary: {text.count(write_anchor)}')
path.write_text(text.replace(write_anchor, cleanup_patch, 1), encoding='utf-8')
PY

exec bash scripts/fix-goanime-taimu-strict-items-v2.sh
