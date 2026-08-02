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
  .github/workflows/build-private-source-bundle.yml \
  .github/workflows/build-private-semogsite-source-bundle.yml \
  keys/source-bundles-public.asc \
  scripts/assemble-source-bundle.sh \
  scripts/validate-source-bundle-request.py \
  triggers/private-source-bundle.json \
  triggers/semogsite-source-bundle.json; do
  require_file "$file"
done

python3 scripts/validate-source-bundle-request.py triggers/private-source-bundle.json >/dev/null
python3 scripts/validate-source-bundle-request.py triggers/semogsite-source-bundle.json >/dev/null

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

bash -n scripts/assemble-source-bundle.sh

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
legacy_build_workflow=.github/workflows/build-private-source-bundle.yml
semogsite_build_workflow=.github/workflows/build-private-semogsite-source-bundle.yml

require_text "$request_workflow" "build/source-bundles"
require_text "$request_workflow" "build/semogsite-source-bundles"
require_text "$request_workflow" "triggers/semogsite-source-bundle.json"
require_text "$request_workflow" "persist-credentials: false"
require_text "$request_workflow" "validate-source-bundle-request.py"

require_text "$legacy_build_workflow" "workflow_run"
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
