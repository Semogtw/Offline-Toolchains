#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Private source workflow validation failed: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file $1"
}

require_text() {
  grep -Fq -- "$2" "$1" || fail "$1 must contain: $2"
}

for file in \
  .github/workflows/request-private-source-bundle.yml \
  .github/workflows/request-goanime-source-bundle.yml \
  .github/workflows/build-private-source-bundle.yml \
  .github/workflows/build-private-semogsite-source-bundle.yml \
  .github/workflows/build-private-hydra-source-bundle.yml \
  .github/workflows/build-hydra.yml \
  keys/source-bundles-public.asc \
  scripts/assemble-source-bundle.sh \
  scripts/build-hydra-toolchain.sh \
  scripts/validate-source-bundle-request.py \
  triggers/private-source-bundle.json \
  triggers/semogsite-source-bundle.json \
  triggers/hydra-source-bundle.json \
  triggers/hydra-toolchain.json; do
  require_file "$file"
done

python3 scripts/validate-source-bundle-request.py triggers/private-source-bundle.json >/dev/null
python3 scripts/validate-source-bundle-request.py triggers/semogsite-source-bundle.json >/dev/null
python3 scripts/validate-source-bundle-request.py triggers/hydra-source-bundle.json >/dev/null

if printf '%s' '{"project":"other","mode":"full","ref":""}' |
   python3 scripts/validate-source-bundle-request.py - >/dev/null 2>&1; then
  fail "unknown projects must be rejected"
fi
if printf '%s' '{"project":"zapzap","mode":"ref","ref":"main~1"}' |
   python3 scripts/validate-source-bundle-request.py - >/dev/null 2>&1; then
  fail "Git revision expressions must be rejected"
fi
if printf '%s' '{"project":"zapzap","mode":"ref","ref":"development/android-build-recovery"}' |
   python3 scripts/validate-source-bundle-request.py - >/dev/null; then
  :
else
  fail "ordinary branch paths must be accepted"
fi
if printf '%s' '{"project":"semogsite","mode":"ref","ref":"develop/foundation-bootstrap"}' |
   python3 scripts/validate-source-bundle-request.py - >/dev/null; then
  :
else
  fail "SemogSite source requests must be accepted"
fi
if printf '%s' '{"project":"hydra","mode":"ref","ref":"main"}' |
   python3 scripts/validate-source-bundle-request.py - >/dev/null; then
  :
else
  fail "Hydra source requests must be accepted"
fi

python3 - <<'PY'
import json
from pathlib import Path

trigger = json.loads(Path("triggers/hydra-toolchain.json").read_text(encoding="utf-8"))
if set(trigger) != {"profile", "ref", "requested_at_utc", "reason"}:
    raise SystemExit("Hydra toolchain trigger keys changed")
if trigger["profile"] != "hydra":
    raise SystemExit("Hydra toolchain trigger must use profile=hydra")
if not isinstance(trigger["ref"], str) or not trigger["ref"]:
    raise SystemExit("Hydra toolchain trigger requires a non-empty ref")
PY

bash -n scripts/assemble-source-bundle.sh
bash -n scripts/build-hydra-toolchain.sh

export GNUPGHOME="$(mktemp -d)"
trap 'rm -rf "$GNUPGHOME"' EXIT
chmod 700 "$GNUPGHOME"
gpg --batch --import keys/source-bundles-public.asc >/dev/null 2>&1
fingerprint="$({
  gpg --batch --with-colons --fingerprint 2DE29DC31427CF0A911AB96175679291435059B0
} | awk -F: '$1 == "fpr" { print $10; exit }')"
[[ "$fingerprint" == "2DE29DC31427CF0A911AB96175679291435059B0" ]] ||
  fail "public key fingerprint mismatch"
[[ -z "$(gpg --batch --with-colons --list-secret-keys 2>/dev/null | awk -F: '$1 == "sec" { print $1 }')" ]] ||
  fail "tracked key material must not include a secret key"

request_workflow=.github/workflows/request-private-source-bundle.yml
goanime_request_workflow=.github/workflows/request-goanime-source-bundle.yml
legacy_build_workflow=.github/workflows/build-private-source-bundle.yml
semogsite_build_workflow=.github/workflows/build-private-semogsite-source-bundle.yml
hydra_build_workflow=.github/workflows/build-private-hydra-source-bundle.yml
hydra_toolchain_workflow=.github/workflows/build-hydra.yml
hydra_toolchain_builder=scripts/build-hydra-toolchain.sh

require_text "$request_workflow" "build/semogsite-source-bundles"
require_text "$request_workflow" "build/hydra-source-bundles"
require_text "$request_workflow" "triggers/semogsite-source-bundle.json"
require_text "$request_workflow" "triggers/hydra-source-bundle.json"
require_text "$request_workflow" "scripts/build-hydra-toolchain.sh"
require_text "$request_workflow" "persist-credentials: false"
require_text "$request_workflow" "validate-source-bundle-request.py"
if grep -Fq -- "      - build/source-bundles" "$request_workflow"; then
  fail "$request_workflow must not trigger for GoAnime requests"
fi

require_text "$goanime_request_workflow" "name: Request private source bundle"
require_text "$goanime_request_workflow" "build/source-bundles"
require_text "$goanime_request_workflow" "triggers/private-source-bundle.json"
require_text "$goanime_request_workflow" "persist-credentials: false"
require_text "$goanime_request_workflow" "validate-source-bundle-request.py"
require_text "$goanime_request_workflow" 'test "$(jq -r '\'' .project'\'' triggers/private-source-bundle.json)" = "goanime"'
require_text "$goanime_request_workflow" "EXPECTED_FINGERPRINT: 2DE29DC31427CF0A911AB96175679291435059B0"

require_text "$legacy_build_workflow" "workflow_run"
require_text "$legacy_build_workflow" "Request private source bundle"
require_text "$legacy_build_workflow" "github.event.workflow_run.head_branch == 'build/source-bundles'"
require_text "$legacy_build_workflow" "github.event.workflow_run.actor.login == github.repository_owner"
require_text "$legacy_build_workflow" "PRIVATE_REPOSITORIES_TOKEN"
require_text "$legacy_build_workflow" '"goanime": "Semogtw/goanime-mobile"'
require_text "$legacy_build_workflow" '"zapzap": "Semogtw/Zapzap"'
require_text "$legacy_build_workflow" "fetch-depth: 0"
require_text "$legacy_build_workflow" "persist-credentials: false"
require_text "$legacy_build_workflow" "lfs: false"
require_text "$legacy_build_workflow" "submodules: false"
require_text "$legacy_build_workflow" "split --bytes=400M"
require_text "$legacy_build_workflow" "part_count > 16"
require_text "$legacy_build_workflow" "Upload encrypted part 015"
require_text "$legacy_build_workflow" "retention-days: 1"
require_text "$legacy_build_workflow" "gpg --batch --yes --trust-model always"
require_text "$legacy_build_workflow" 'rm -rf "$package_dir" "$plaintext_archive" "$source_dir"'

require_text "$semogsite_build_workflow" "github.event.workflow_run.head_branch == 'build/semogsite-source-bundles'"
require_text "$semogsite_build_workflow" "github.event.workflow_run.actor.login == github.repository_owner"
require_text "$semogsite_build_workflow" "repository: Semogtw/SemogSite"
require_text "$semogsite_build_workflow" "PRIVATE_REPOSITORIES_TOKEN"
require_text "$semogsite_build_workflow" "project=semogsite"
require_text "$semogsite_build_workflow" "mode=ref"
require_text "$semogsite_build_workflow" "fetch-depth: 0"
require_text "$semogsite_build_workflow" "persist-credentials: false"
require_text "$semogsite_build_workflow" "lfs: false"
require_text "$semogsite_build_workflow" "submodules: false"
require_text "$semogsite_build_workflow" "private-source-semogsite-ref"
require_text "$semogsite_build_workflow" "retention-days: 1"
require_text "$semogsite_build_workflow" "gpg --batch --yes --trust-model always"
require_text "$semogsite_build_workflow" 'rm -rf "$package_dir" "$plaintext_archive" "$gpg_home" "$source_dir"'

require_text "$hydra_build_workflow" "github.event.workflow_run.head_branch == 'build/hydra-source-bundles'"
require_text "$hydra_build_workflow" "github.event.workflow_run.actor.login == github.repository_owner"
require_text "$hydra_build_workflow" "repository: Semogtw/HydraPersonalizado"
require_text "$hydra_build_workflow" "PRIVATE_REPOSITORIES_TOKEN"
require_text "$hydra_build_workflow" "project=hydra"
require_text "$hydra_build_workflow" "mode=ref"
require_text "$hydra_build_workflow" "fetch-depth: 0"
require_text "$hydra_build_workflow" "persist-credentials: false"
require_text "$hydra_build_workflow" "lfs: false"
require_text "$hydra_build_workflow" "submodules: false"
require_text "$hydra_build_workflow" "private-source-hydra-ref"
require_text "$hydra_build_workflow" "retention-days: 1"
require_text "$hydra_build_workflow" "gpg --batch --yes --trust-model always"
require_text "$hydra_build_workflow" 'rm -rf "$package_dir" "$plaintext_archive" "$gpg_home" "$source_dir"'

require_text "$hydra_toolchain_workflow" "repository: Semogtw/HydraPersonalizado"
require_text "$hydra_toolchain_workflow" "PRIVATE_REPOSITORIES_TOKEN"
require_text "$hydra_toolchain_workflow" "persist-credentials: false"
require_text "$hydra_toolchain_workflow" "lfs: false"
require_text "$hydra_toolchain_workflow" "submodules: false"
require_text "$hydra_toolchain_workflow" "bash scripts/build-hydra-toolchain.sh"
require_text "$hydra_toolchain_workflow" "scripts/build-hydra-toolchain.sh"
require_text "$hydra_toolchain_workflow" "retention-days: 1"
require_text "$hydra_toolchain_workflow" "Upload Hydra toolchain part 15"

require_text "$hydra_toolchain_builder" "yarn install --frozen-lockfile --non-interactive"
require_text "$hydra_toolchain_builder" "yarn --cwd \"\$project\" install"
require_text "$hydra_toolchain_builder" "verify_exact_input"
require_text "$hydra_toolchain_builder" "--offline"
require_text "$hydra_toolchain_builder" "CARGO_NET_OFFLINE=true"
require_text "$hydra_toolchain_builder" "ELECTRON_CACHE"
require_text "$hydra_toolchain_builder" "ELECTRON_BUILDER_CACHE"
require_text "$hydra_toolchain_builder" "npm_config_devdir"
require_text "$hydra_toolchain_builder" "fresh_home=\"\$(mktemp"
require_text "$hydra_toolchain_builder" "ELECTRON_MIRROR=\"http://127.0.0.1:9/\""
require_text "$hydra_toolchain_builder" 'rm -rf "$source_dir"'
require_text "$hydra_toolchain_builder" "split -b 400M"
require_text "$hydra_toolchain_builder" "part_count > 16"

if git grep -n -E '^-----BEGIN PGP PRIVATE KEY BLOCK-----$'; then
  fail "private OpenPGP key material is tracked"
fi
if git grep -n -- 'ghp_' -- ':!scripts/validate-private-source-workflows.sh'; then
  fail "classic GitHub token-looking material is tracked"
fi
if git grep -n -- 'github_pat_' -- ':!scripts/validate-private-source-workflows.sh'; then
  fail "fine-grained GitHub token-looking material is tracked"
fi

printf 'Private source workflow validation passed.\n'
