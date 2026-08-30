#!/usr/bin/env bash
set -euo pipefail

# The first strict-items run proved five behavior fixes and exposed one
# remaining distinction: a present-but-malformed response offset was being
# treated like an absent optional offset. Patch the exact-SHA fixer itself so
# the existing RED suite remains the source of truth and the retry stays CAS
# protected.
python3 - <<'PY'
from pathlib import Path

path = Path('scripts/fix-goanime-mangadex-strict-items.sh')
text = path.read_text(encoding='utf-8')
marker = "path.write_text(text, encoding='utf-8')\n\nmaterializer = Path('tools/manga/materialize_global_manga_availability_ci.sh')"
if text.count(marker) != 1:
    raise SystemExit(f'unexpected strict-items fixer write marker: {text.count(marker)}')

insertion = r'''old = """int _responseOffset(
  Object? value, {
  required int requestedOffset,
  required String responseName,
}) {
  final responseOffset = _nonNegativeInt(value);
  if (responseOffset == null) return requestedOffset;
  if (responseOffset != requestedOffset) {
    throw FormatException(
      '$responseName response offset does not match requested offset '
      '$requestedOffset.',
    );
  }
  return responseOffset;
}
"""
new = """int _responseOffset(
  Object? value, {
  required int requestedOffset,
  required String responseName,
}) {
  if (value == null) return requestedOffset;
  final responseOffset = _nonNegativeInt(value);
  if (responseOffset == null) {
    throw FormatException('$responseName response has invalid offset.');
  }
  if (responseOffset != requestedOffset) {
    throw FormatException(
      '$responseName response offset does not match requested offset '
      '$requestedOffset.',
    );
  }
  return responseOffset;
}
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected MangaDex response-offset shape: {text.count(old)}')
text = text.replace(old, new, 1)
'''

text = text.replace(marker, insertion + '\n' + marker, 1)
path.write_text(text, encoding='utf-8')
PY

exec bash scripts/fix-goanime-mangadex-strict-items.sh
