#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

path = Path('scripts/fix-goanime-manhastro-strict-items.sh')
text = path.read_text(encoding='utf-8')
needle = "path.write_text(text, encoding='utf-8')"
replacement = """date_access = "item?['capitulo_data']"
if text.count(date_access) != 1:
    raise SystemExit(f'unexpected nullable Manhastro chapter-date access: {text.count(date_access)}')
text = text.replace(date_access, "item['capitulo_data']", 1)
path.write_text(text, encoding='utf-8')"""
if text.count(needle) != 1:
    raise SystemExit(f'unexpected Manhastro patch write boundary: {text.count(needle)}')
path.write_text(text.replace(needle, replacement, 1), encoding='utf-8')
PY

exec bash scripts/fix-goanime-manhastro-strict-items.sh
