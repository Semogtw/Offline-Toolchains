#!/usr/bin/env bash
set -euo pipefail

: "${NODE_VERSION:?NODE_VERSION is required}"
: "${PNPM_VERSION:?PNPM_VERSION is required}"
: "${DENO_VERSION:?DENO_VERSION is required}"
: "${SUPABASE_VERSION:?SUPABASE_VERSION is required}"
: "${REQUESTED_REF:?REQUESTED_REF is required}"
: "${SOURCE_SHA:?SOURCE_SHA is required}"
: "${TOOLCHAIN_SHA:?TOOLCHAIN_SHA is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

source_dir="${SOURCE_DIR:-fichario-source}"
root="$RUNNER_TEMP/fichario-offline"
archive="$RUNNER_TEMP/fichario-offline-linux-x64.tar.zst"
parts="$RUNNER_TEMP/fichario-offline-parts"
smoke="$RUNNER_TEMP/fichario-offline-smoke"
node_root="$(dirname "$(dirname "$(readlink -f "$(command -v node)")")")"
canonical_npm_registry="https://registry.npmjs.org/"
validation_status=passed
validation_failures=()

record_gate() {
  local name="$1"
  shift

  echo "--- validation gate: $name ---"
  if "$@"; then
    echo "validation gate passed: $name"
  else
    local exit_code=$?
    validation_status=failed
    validation_failures+=("$name:$exit_code")
    echo "validation gate failed: $name (exit $exit_code)" >&2
  fi
}

validation_failures_csv() {
  if ((${#validation_failures[@]} == 0)); then
    printf '%s' 'none'
    return
  fi

  local IFS=,
  printf '%s' "${validation_failures[*]}"
}

rm -rf "$root" "$archive" "$archive.sha256" "$parts" "$smoke"
mkdir -p \
  "$root/node" \
  "$root/pnpm" \
  "$root/pnpm-store" \
  "$root/playwright-browsers" \
  "$root/deno/bin" \
  "$root/deno/cache" \
  "$root/supabase/bin" \
  "$root/workspace" \
  "$root/bin" \
  "$parts"

cp -a "$node_root/." "$root/node/"
"$root/node/bin/npm" install --global --prefix "$root/pnpm" "pnpm@$PNPM_VERSION"
install -m 0755 "$(command -v deno)" "$root/deno/bin/deno"
install -m 0755 "$(command -v supabase)" "$root/supabase/bin/supabase"
install -m 0755 "$(command -v supabase-go)" "$root/supabase/bin/supabase-go"

export PATH="$root/pnpm/bin:$root/node/bin:$root/deno/bin:$root/supabase/bin:$PATH"
export SUPABASE_GO_BINARY="$root/supabase/bin/supabase-go"
export PNPM_STORE_DIR="$root/pnpm-store"
export PLAYWRIGHT_BROWSERS_PATH="$root/playwright-browsers"
export DENO_DIR="$root/deno/cache"
export DENO_NO_UPDATE_CHECK=1
export npm_config_registry="$canonical_npm_registry"
export NPM_CONFIG_REGISTRY="$canonical_npm_registry"
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false

pnpm --dir "$source_dir" install \
  --frozen-lockfile \
  --store-dir "$PNPM_STORE_DIR"
pnpm --dir "$source_dir" exec playwright install chromium

# Populate Deno's npm cache while network access is available. A source-level
# failure is recorded, but does not prevent packaging the otherwise useful
# workspace and toolchain.
record_gate edge-cache pnpm --dir "$source_dir" test:functions:check

cp -a "$source_dir/." "$root/workspace/"
rm -rf \
  "$root/workspace/.git" \
  "$root/workspace/node_modules" \
  "$root/workspace/.svelte-kit" \
  "$root/workspace/build" \
  "$root/workspace/playwright-report" \
  "$root/workspace/test-results"

cat > "$root/bin/activate" <<'ACTIVATE'
#!/usr/bin/env bash
toolchain_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$toolchain_root/pnpm/bin:$toolchain_root/node/bin:$toolchain_root/deno/bin:$toolchain_root/supabase/bin:$PATH"
export SUPABASE_GO_BINARY="$toolchain_root/supabase/bin/supabase-go"
export PNPM_STORE_DIR="$toolchain_root/pnpm-store"
export PLAYWRIGHT_BROWSERS_PATH="$toolchain_root/playwright-browsers"
export DENO_DIR="$toolchain_root/deno/cache"
export DENO_NO_UPDATE_CHECK=1
export npm_config_registry="https://registry.npmjs.org/"
export NPM_CONFIG_REGISTRY="https://registry.npmjs.org/"
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
ACTIVATE

cat > "$root/bin/install-offline" <<'INSTALL_OFFLINE'
#!/usr/bin/env bash
set -euo pipefail
toolchain_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${1:-$toolchain_root/workspace}"
# shellcheck source=/dev/null
source "$toolchain_root/bin/activate"
export npm_config_registry="http://127.0.0.1:9"
export NPM_CONFIG_REGISTRY="http://127.0.0.1:9"
pnpm --dir "$workspace" install \
  --offline \
  --frozen-lockfile \
  --store-dir "$PNPM_STORE_DIR"
INSTALL_OFFLINE

cat > "$root/bin/check-edge-offline" <<'CHECK_EDGE_OFFLINE'
#!/usr/bin/env bash
set -euo pipefail
toolchain_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${1:-$toolchain_root/workspace}"
# shellcheck source=/dev/null
source "$toolchain_root/bin/activate"

# Keep the canonical package identity while making every network attempt fail.
# A missing Deno npm cache entry therefore turns this smoke test red.
export HTTP_PROXY="http://127.0.0.1:9"
export HTTPS_PROXY="http://127.0.0.1:9"
export ALL_PROXY="http://127.0.0.1:9"
export NO_PROXY="127.0.0.1,localhost"

module_count=0
while IFS= read -r module; do
  module_count=$((module_count + 1))
  deno check --no-config "$workspace/$module"
done < <(sed -n 's/^deno check --no-config //p' "$workspace/tools/checks/check-edge-functions.sh")
if (( module_count == 0 )); then
  echo 'No Edge Function modules were discovered in check-edge-functions.sh.' >&2
  exit 1
fi
echo "Offline Edge Function checks completed ($module_count modules)."
CHECK_EDGE_OFFLINE

cat > "$root/bin/doctor" <<'DOCTOR'
#!/usr/bin/env bash
set -euo pipefail
toolchain_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace="${1:-$toolchain_root/workspace}"
# shellcheck source=/dev/null
source "$toolchain_root/bin/activate"
node --version
pnpm --version
deno --version
supabase --version
"$SUPABASE_GO_BINARY" --version
test -f "$workspace/pnpm-lock.yaml"
test -d "$PNPM_STORE_DIR"
test -d "$PLAYWRIGHT_BROWSERS_PATH"
test -d "$DENO_DIR"
find "$DENO_DIR" -type f -print -quit | grep -q .
pnpm --dir "$workspace" exec playwright --version
"$toolchain_root/bin/check-edge-offline" "$workspace"
echo "Fichário offline workspace doctor: PASS"
DOCTOR

chmod +x \
  "$root/bin/activate" \
  "$root/bin/install-offline" \
  "$root/bin/check-edge-offline" \
  "$root/bin/doctor"

# Validate from a clean copy of the real checkout so source-aware gates that use
# git ls-files still see repository metadata. The distributable workspace above
# intentionally stays gitless.
cp -a "$source_dir/." "$smoke/"
rm -rf \
  "$smoke/node_modules" \
  "$smoke/.svelte-kit" \
  "$smoke/build" \
  "$smoke/playwright-report" \
  "$smoke/test-results"
record_gate offline-install "$root/bin/install-offline" "$smoke"
# shellcheck source=/dev/null
source "$root/bin/activate"

# Continue through every source gate even when one fails. This makes the bundle
# useful for repair work while MANIFEST.txt and workflow status stay explicit
# about what did not validate.
export npm_config_registry="http://127.0.0.1:9"
export NPM_CONFIG_REGISTRY="http://127.0.0.1:9"
record_gate lint pnpm --dir "$smoke" lint
record_gate check pnpm --dir "$smoke" check
record_gate unit pnpm --dir "$smoke" test
record_gate build pnpm --dir "$smoke" build
record_gate source-offline pnpm --dir "$smoke" test:source:offline
record_gate e2e pnpm --dir "$smoke" test:e2e
export npm_config_registry="$canonical_npm_registry"
export NPM_CONFIG_REGISTRY="$canonical_npm_registry"
record_gate edge-offline "$root/bin/check-edge-offline" "$smoke"
record_gate database pnpm --dir "$smoke" test:db:local
record_gate doctor "$root/bin/doctor" "$smoke"

failures="$(validation_failures_csv)"
package_sha="$(sha256sum "$root/workspace/package.json" | cut -d' ' -f1)"
lock_sha="$(sha256sum "$root/workspace/pnpm-lock.yaml" | cut -d' ' -f1)"
{
  echo "schema_version=3"
  echo "source_repository=Semogtw/FicharioVirtual"
  echo "source_ref=$REQUESTED_REF"
  echo "source_commit=$SOURCE_SHA"
  echo "toolchain_commit=$TOOLCHAIN_SHA"
  echo "created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "node_version=$(node --version)"
  echo "pnpm_version=$(pnpm --version)"
  echo "deno_version=$(deno --version | head -n 1)"
  echo "supabase_version=$(supabase --version)"
  echo "npm_registry=$canonical_npm_registry"
  echo "package_sha256=$package_sha"
  echo "lock_sha256=$lock_sha"
  echo "validation_status=$validation_status"
  echo "validation_failures=$failures"
  echo "database_gate=executed"
  echo "pnpm_store=packaged"
  echo "playwright=chromium_packaged"
  echo "deno_cache=packaged_best_effort"
} > "$root/MANIFEST.txt"

tar -C "$RUNNER_TEMP" -I 'zstd -T0 -8' -cf "$archive" fichario-offline
(
  cd "$RUNNER_TEMP"
  sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256"
)
split -b 350M -d -a 2 "$archive" "$parts/fichario-offline-linux-x64.part-"
(
  cd "$parts"
  sha256sum fichario-offline-linux-x64.part-* > SHA256SUMS.parts
)

part_count="$(find "$parts" -maxdepth 1 -type f -name 'fichario-offline-linux-x64.part-*' | wc -l)"
test "$part_count" -ge 1
test "$part_count" -le 6
{
  echo "archive=$(basename "$archive")"
  echo "archive_sha256=$(cut -d' ' -f1 "$archive.sha256")"
  echo "part_count=$part_count"
  echo "validation_status=$validation_status"
  echo "validation_failures=$failures"
  echo "reassemble=cat fichario-offline-linux-x64.part-* > $(basename "$archive")"
  echo "verify_parts=sha256sum -c SHA256SUMS.parts"
  echo "extract=tar --zstd -xf $(basename "$archive")"
} > "$parts/PARTS.txt"

{
  echo "parts=$parts"
  echo "archive_sha=$archive.sha256"
  echo "root=$root"
  echo "validation_status=$validation_status"
  echo "validation_failures=$failures"
  for index in 00 01 02 03 04 05; do
    if [[ -f "$parts/fichario-offline-linux-x64.part-$index" ]]; then
      echo "part_$index=true"
    fi
  done
} >> "$GITHUB_OUTPUT"
