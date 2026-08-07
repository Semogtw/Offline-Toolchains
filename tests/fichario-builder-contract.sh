#!/usr/bin/env bash
set -euo pipefail

builder="scripts/build-fichario-offline.sh"

# The distributable workspace must stay gitless, but source-aware gates such as
# check-source-security.mjs require a real repository during smoke validation.
grep -Fq 'rm -rf \' "$builder"
grep -Fq '"$root/workspace/.git"' "$builder"
grep -Fq 'cp -a "$source_dir/." "$smoke/"' "$builder"
grep -Fq '"$smoke/node_modules"' "$builder"
grep -Fq 'pnpm --dir "$smoke" test:source:offline' "$builder"

echo "Fichário builder contract: PASS"
