#!/usr/bin/env bash
set -euo pipefail

builder="scripts/build-fichario-offline.sh"
workflow=".github/workflows/build-fichario.yml"

# The distributable workspace must stay gitless, but source-aware gates such as
# check-source-security.mjs require a real repository during smoke validation.
grep -Fq 'rm -rf \' "$builder"
grep -Fq '"$root/workspace/.git"' "$builder"
grep -Fq 'cp -a "$source_dir/." "$smoke/"' "$builder"
grep -Fq '"$smoke/node_modules"' "$builder"

# Validation failures must be recorded instead of aborting before the portable
# workspace can be archived. The workflow still finishes red after uploading it.
grep -Fq 'record_gate()' "$builder"
grep -Fq 'record_gate lint pnpm --dir "$smoke" lint' "$builder"
grep -Fq 'record_gate check pnpm --dir "$smoke" check' "$builder"
grep -Fq 'record_gate unit pnpm --dir "$smoke" test' "$builder"
grep -Fq 'record_gate build pnpm --dir "$smoke" build' "$builder"
grep -Fq 'record_gate source-offline pnpm --dir "$smoke" test:source:offline' "$builder"
grep -Fq 'record_gate e2e pnpm --dir "$smoke" test:e2e' "$builder"
grep -Fq 'validation_status=' "$builder"
grep -Fq 'validation_failures=' "$builder"
grep -Fq 'echo "validation_status=$validation_status"' "$builder"
grep -Fq 'if: always()' "$workflow"
grep -Fq 'Report validation failure after uploads' "$workflow"
grep -Fq "steps.bundle.outputs.validation_status == 'failed'" "$workflow"

echo "Fichário builder contract: PASS"
