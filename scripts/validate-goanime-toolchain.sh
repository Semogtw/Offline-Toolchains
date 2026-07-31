#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$root/.github/workflows/build-goanime.yml"
manifest="$root/fixtures/goanime/hosted-lock.json"

python3 -m unittest "$root/scripts/test_goanime_lock_cache.py"
bash "$root/scripts/test_repair_portable_flutter.sh"
python3 "$root/scripts/goanime_lock_cache.py" validate --manifest "$manifest"
bash -n "$root/scripts/repair-portable-flutter.sh"
bash -n "$root/scripts/test_repair_portable_flutter.sh"

grep -q 'goanime_lock_cache.py write-pubspec' "$workflow"
grep -Eq 'goanime[_-]lock[_-]cache\.py.*verify-cache' "$workflow"
grep -q 'repair-portable-flutter.sh' "$workflow"
grep -q 'PUB_HOSTED_URL=http://127.0.0.1:9' "$workflow"
grep -q 'flutter pub get --offline --enforce-lockfile' "$workflow"

printf 'validate-goanime-toolchain: PASS\n'
