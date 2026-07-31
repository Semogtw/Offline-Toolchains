#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Workflow security validation failed: $*" >&2
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
  keys/source-bundles-public.asc \
  scripts/assemble-source-bundle.sh \
  scripts/validate-source-bundle-request.py \
  triggers/private-source-bundle.json; do
  require_file "$file"
done

python3 scripts/validate-source-bundle-request.py triggers/private-source-bundle.json >/dev/null

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
build_workflow=.github/workflows/build-private-source-bundle.yml

require_text "$request_workflow" "build/source-bundles"
require_text "$request_workflow" "persist-credentials: false"
require_text "$request_workflow" "validate-source-bundle-request.py"

require_text "$build_workflow" "workflow_run"
require_text "$build_workflow" "github.event.workflow_run.head_branch == 'build/source-bundles'"
require_text "$build_workflow" "github.event.workflow_run.actor.login == github.repository_owner"
require_text "$build_workflow" "PRIVATE_REPOSITORIES_TOKEN"
require_text "$build_workflow" '"goanime": "Semogtw/goanime-mobile"'
require_text "$build_workflow" '"zapzap": "Semogtw/Zapzap"'
require_text "$build_workflow" "fetch-depth: 0"
require_text "$build_workflow" "persist-credentials: false"
require_text "$build_workflow" "lfs: false"
require_text "$build_workflow" "submodules: false"
require_text "$build_workflow" "split --bytes=400M"
require_text "$build_workflow" "part_count > 16"
require_text "$build_workflow" "Upload encrypted part 015"
require_text "$build_workflow" "retention-days: 1"
require_text "$build_workflow" "gpg --batch --yes --trust-model always"
require_text "$build_workflow" 'rm -rf "$package_dir" "$plaintext_archive" "$source_dir"'

# Artifact Platform v2 guards.
for file in \
  .github/workflows/request-toolchain-build.yml \
  .github/workflows/build-exact-toolchain.yml \
  .github/workflows/report-toolchain-runs.yml \
  .github/actions/upload-artifact-set/action.yml \
  schemas/artifact-set-v2.schema.json \
  schemas/toolchain-request-v1.schema.json \
  scripts/build_artifact_set.py \
  scripts/restore_workspace.py \
  scripts/validate-toolchain-request.py \
  triggers/toolchain-build.json; do
  require_file "$file"
done

toolchain_request=.github/workflows/request-toolchain-build.yml
exact_builder=.github/workflows/build-exact-toolchain.yml
reporter=.github/workflows/report-toolchain-runs.yml
uploader=.github/actions/upload-artifact-set/action.yml
request_schema=schemas/toolchain-request-v1.schema.json

require_text "$toolchain_request" "build/toolchains"
require_text "$toolchain_request" "validate-toolchain-request.py"
require_text "$toolchain_request" "python3 -m unittest discover -s tests -v"
if grep -Fq -- 'secrets.' "$toolchain_request"; then
  fail "unprivileged toolchain request workflow must not receive secrets"
fi

require_text "$exact_builder" "workflow_run"
require_text "$exact_builder" "github.event.workflow_run.head_branch == 'build/toolchains'"
require_text "$exact_builder" "github.event.workflow_run.actor.login == github.repository_owner"
require_text "$exact_builder" "PRIVATE_REPOSITORIES_TOKEN"
require_text "$exact_builder" "Semogtw/goanime-mobile"
require_text "$exact_builder" "Semogtw/Zapzap"
require_text "$exact_builder" "fetch-depth: 0"
require_text "$exact_builder" "persist-credentials: false"
require_text "$exact_builder" "lfs: false"
require_text "$exact_builder" "submodules: false"
require_text "$exact_builder" "flutter pub get --offline --enforce-lockfile"
require_text "$exact_builder" "./gradlew --no-daemon --offline"
require_text "$exact_builder" "rm -rf private-source request-source"
require_text "$exact_builder" "Upload toolchain receipt"
require_text "$exact_builder" "uses: ./.github/actions/upload-artifact-set"

require_text "$uploader" "retention-days: 1"
require_text "$uploader" "compression-level: 0"
require_text "$uploader" "Upload part 15"
require_text "$uploader" "fromJSON(inputs.part-count) > 15"
require_text scripts/build_artifact_set.py "DEFAULT_PART_SIZE = 400 * 1024 * 1024"
require_text schemas/artifact-set-v2.schema.json '"const": 2'
require_text "$request_schema" '"additionalProperties": false'
if grep -Eq '"(repository|token|command|ref)"[[:space:]]*:' "$request_schema"; then
  fail "toolchain request schema must not accept repository, token, command or ref"
fi

require_text "$reporter" "actions: write"
require_text "$reporter" "issues: write"
require_text "$reporter" "source-bundle artifacts are excluded"
require_text scripts/catalog_artifacts.py "private-source-"

python3 scripts/validate-toolchain-request.py \
  triggers/toolchain-build.json --profiles profiles >/dev/null
python3 scripts/validate-workflows.py .github/workflows >/dev/null

if git grep -n -E '^-----BEGIN PGP PRIVATE KEY BLOCK-----$'; then
  fail "private OpenPGP key material is tracked"
fi
if git grep -n -- 'ghp_' -- ':!scripts/validate-private-source-workflows.sh'; then
  fail "classic GitHub token-looking material is tracked"
fi
if git grep -n -- 'github_pat_' -- ':!scripts/validate-private-source-workflows.sh'; then
  fail "fine-grained GitHub token-looking material is tracked"
fi
if git grep -n -E 'PRIVATE_REPOSITORIES_TOKEN[[:space:]]*=' -- ':!scripts/validate-private-source-workflows.sh'; then
  fail "assigned private repository token material is tracked"
fi

printf 'Workflow security validation passed.\n'
