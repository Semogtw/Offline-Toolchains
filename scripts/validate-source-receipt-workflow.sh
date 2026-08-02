#!/usr/bin/env bash
set -euo pipefail

workflow=.github/workflows/record-goanime-source-receipt.yml

fail() {
  echo "Source receipt workflow validation failed: $*" >&2
  exit 1
}

require_text() {
  grep -Fq -- "$2" "$1" || fail "$1 must contain: $2"
}

[[ -f "$workflow" ]] || fail "missing $workflow"

require_text "$workflow" "name: Record GoAnime source receipt"
require_text "$workflow" "workflow_run"
require_text "$workflow" "Build encrypted private source bundle"
require_text "$workflow" "github.event.workflow_run.conclusion == 'success'"
require_text "$workflow" "github.event.workflow_run.event == 'workflow_dispatch'"
require_text "$workflow" "actions: read"
require_text "$workflow" "contents: write"
require_text "$workflow" "ref: build/source-bundles"
require_text "$workflow" "persist-credentials: true"
require_text "$workflow" "private-source-goanime-"
require_text "$workflow" "receipts/goanime-latest.json"
require_text "$workflow" "git diff --quiet -- receipts/goanime-latest.json"
require_text "$workflow" "git push origin HEAD:build/source-bundles"
require_text "$workflow" "artifact_id"
require_text "$workflow" "run_id"
require_text "$workflow" "expires_at"

if grep -Eq 'PRIVATE_REPOSITORIES_TOKEN|PGP_PRIVATE|PRIVATE KEY|triggers/private-source-bundle\.json' "$workflow"; then
  fail "receipt workflow must not access private source credentials or mutate requests"
fi

printf 'Source receipt workflow validation passed.\n'
