#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$root/.github/workflows/build-goanime-lock-delta.yml"
manifest="$root/manifests/goanime/hosted-lock.json"

python3 -m unittest "$root/scripts/test_goanime_lock_cache.py"
bash "$root/scripts/test_repair_portable_flutter.sh"
bash "$root/scripts/test_apply_goanime_lock_delta.sh"
python3 "$root/scripts/goanime_lock_cache.py" validate --manifest "$manifest"
bash -n "$root/scripts/repair-portable-flutter.sh"
bash -n "$root/scripts/test_repair_portable_flutter.sh"
bash -n "$root/scripts/apply-goanime-lock-delta.sh"
bash -n "$root/scripts/test_apply_goanime_lock_delta.sh"

grep -q 'goanime_lock_cache.py write-pubspec' "$workflow"
grep -Eq 'goanime[_-]lock[_-]cache\.py.*verify-cache' "$workflow"
grep -q 'apply-goanime-lock-delta.sh' "$workflow"
grep -q 'PUB_HOSTED_URL=http://127.0.0.1:9' "$workflow"
grep -q 'flutter pub get --offline --enforce-lockfile' "$workflow"
grep -q 'split -b 400M' "$workflow"
grep -q 'retention-days: 1' "$workflow"

printf 'validate-goanime-toolchain: PASS\n'
