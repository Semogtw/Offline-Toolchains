#!/usr/bin/env bash
set -euo pipefail

source_workflow=.github/workflows/record-goanime-source-receipt.yml
toolchain_workflow=.github/workflows/record-goanime-toolchain-receipt.yml

fail() {
  echo "Receipt workflow validation failed: $*" >&2
  exit 1
}

require_text() {
  grep -Fq -- "$2" "$1" || fail "$1 must contain: $2"
}

for workflow in "$source_workflow" "$toolchain_workflow"; do
  [[ -f "$workflow" ]] || fail "missing $workflow"
  require_text "$workflow" "workflow_run"
  require_text "$workflow" "github.event.workflow_run.conclusion == 'success'"
  require_text "$workflow" "github.event.workflow_run.actor.login == github.repository_owner"
  require_text "$workflow" "actions: read"
  require_text "$workflow" "contents: write"
  require_text "$workflow" "persist-credentials: true"
  require_text "$workflow" "artifact_id"
  require_text "$workflow" "run_id"
  require_text "$workflow" "expires_at"
  if grep -Eq 'PRIVATE_REPOSITORIES_TOKEN|PGP_PRIVATE|PRIVATE KEY|triggers/private-source-bundle\.json' "$workflow"; then
    fail "$workflow must not access private source credentials or mutate requests"
  fi
done

require_text "$source_workflow" "name: Record GoAnime source receipt"
require_text "$source_workflow" "Build encrypted private source bundle"
require_text "$source_workflow" "github.event.workflow_run.event == 'workflow_run'"
require_text "$source_workflow" "ref: build/source-bundles"
require_text "$source_workflow" "private-source-goanime-"
require_text "$source_workflow" "receipts/goanime-latest.json"
require_text "$source_workflow" "verify_goanime_source_receipt.py"
require_text "$source_workflow" "git push origin HEAD:build/source-bundles"

require_text "$toolchain_workflow" "name: Record GoAnime toolchain receipt"
require_text "$toolchain_workflow" "Build GoAnime offline cache"
require_text "$toolchain_workflow" "github.event.workflow_run.head_branch == 'main'"
require_text "$toolchain_workflow" "github.event.workflow_run.event == 'push'"
require_text "$toolchain_workflow" "github.event.workflow_run.event == 'workflow_dispatch'"
require_text "$toolchain_workflow" "ref: main"
require_text "$toolchain_workflow" "goanime-flutter-cache-linux-x64-"
require_text "$toolchain_workflow" "receipts/goanime-toolchain-latest.json"
require_text "$toolchain_workflow" "verify_goanime_toolchain_receipt.py"
require_text "$toolchain_workflow" "git push origin HEAD:main"

printf 'Receipt workflow validation passed.\n'
