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
grep -Fq 'record_gate edge-offline "$root/bin/check-edge-offline" "$smoke"' "$builder"

# The Fichário profile is also the fallback checkout/gate runner for development
# sessions without a usable local environment. Database migrations and pgTAP are
# part of the consumer's verify:full contract, so the public hub must exercise
# them instead of silently documenting them as unavailable.
grep -Fq 'record_gate database pnpm --dir "$smoke" test:db:local' "$builder"
grep -Fq 'database_gate=executed' "$builder"
! grep -Fq 'database_gate_note=Supabase CLI is included; local DB tests still require Docker' "$builder"
grep -Fq 'postgresql-client' "$workflow"

# Supabase CLI 2.111.0 is a paired shim + legacy Go binary. The official release
# tarball must be checksum-verified and both executables must stay co-located in
# the runner and portable bundle so delegated commands such as `db reset` work.
grep -Fq 'supabase_${SUPABASE_VERSION}_linux_amd64.tar.gz' "$workflow"
grep -Fq 'checksums.txt' "$workflow"
grep -Fq 'sha256sum --check' "$workflow"
grep -Fq 'supabase-go' "$workflow"
grep -Fq '"$root/supabase/bin/supabase-go"' "$builder"
grep -Fq 'export SUPABASE_GO_BINARY="$root/supabase/bin/supabase-go"' "$builder"

grep -Fq 'validation_status=' "$builder"
grep -Fq 'validation_failures=' "$builder"
grep -Fq 'echo "validation_status=$validation_status"' "$builder"
grep -Fq 'if: always()' "$workflow"
grep -Fq 'Report validation failure after uploads' "$workflow"
grep -Fq "steps.bundle.outputs.validation_status == 'failed'" "$workflow"

echo "Fichário builder contract: PASS"
