#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

path = Path('scripts/fix-goanime-taimu-strict-items.sh')
text = path.read_text(encoding='utf-8')

red_anchor = "grep -Fq 'pages reject malformed entries instead of returning a partial manifest' /tmp/taimu-strict-red.log\n"
red_insert = red_anchor + "grep -Fq 'pagination rejects fractional integer metadata' /tmp/taimu-strict-red.log\n"
if text.count(red_anchor) != 1:
    raise SystemExit(f'unexpected Taimu strict RED anchor: {text.count(red_anchor)}')
text = text.replace(red_anchor, red_insert, 1)

write_anchor = "path.write_text(text, encoding='utf-8')"
helper_patch = """old = \"\"\"int? _nonNegativeInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : null;
}
\"\"\"
new = \"\"\"int? _nonNegativeInt(Object? value) {
  int? parsed;
  if (value is num) {
    if (!value.isFinite) return null;
    final integer = value.toInt();
    if (value != integer) return null;
    parsed = integer;
  } else {
    parsed = int.tryParse('$value');
  }
  return parsed != null && parsed >= 0 ? parsed : null;
}
\"\"\"
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu integer parser shape: {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')"""
if text.count(write_anchor) != 1:
    raise SystemExit(f'unexpected Taimu patch write boundary: {text.count(write_anchor)}')
text = text.replace(write_anchor, helper_patch, 1)
path.write_text(text, encoding='utf-8')
PY

exec bash scripts/fix-goanime-taimu-strict-items.sh
