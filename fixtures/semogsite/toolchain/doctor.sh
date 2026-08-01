#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=activate.sh
source "$script_dir/activate.sh"

fail() {
  echo "SemogSite toolchain doctor: $*" >&2
  exit 1
}

[[ "$(node -p 'process.platform')" == "linux" ]] || fail "expected Linux"
[[ "$(node -p 'process.arch')" == "x64" ]] || fail "expected x64"
[[ "$(node -p 'process.versions.node.split(`.`)[0]')" == "22" ]] || fail "expected Node 22"
[[ -d "$PNPM_STORE_DIR" ]] || fail "missing pnpm store"
[[ -d "$PLAYWRIGHT_BROWSERS_PATH" ]] || fail "missing Playwright browser cache"
find "$PLAYWRIGHT_BROWSERS_PATH" -type f \
  \( -name chrome -o -name headless_shell -o -name chromium \) \
  -print -quit | grep -q . || fail "Chromium executable was not found"
find "$SEMOGSITE_NATIVE_ASSETS/better-sqlite3" -type f \
  -name better_sqlite3.node -print -quit | grep -q . || \
  fail "better-sqlite3 native asset was not found"

node --version
pnpm --version

if [[ $# -gt 0 ]]; then
  project_dir="$(cd "$1" && pwd)"
  [[ -f "$project_dir/package.json" ]] || fail "package.json not found in $project_dir"
  pnpm --dir "$project_dir" exec node -e "require('better-sqlite3'); console.log('better-sqlite3: ok')"
  pnpm --dir "$project_dir" exec vite --version
  pnpm --dir "$project_dir" exec vitest --version
  pnpm --dir "$project_dir" exec playwright --version
  pnpm --dir "$project_dir" exec wrangler --version
fi

echo "SemogSite toolchain doctor: PASS"
