#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project="${1:-$PWD}"
exec python3 "$root/native_asset_cache.py" prepare \
  --cache "$root/native-assets-cache/hooks_runner-shared" \
  --project "$project"
