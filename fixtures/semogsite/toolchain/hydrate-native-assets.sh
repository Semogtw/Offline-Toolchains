#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=activate.sh
source "$script_dir/activate.sh"

project_dir="${1:-$PWD}"
project_dir="$(cd "$project_dir" && pwd)"
virtual_store="$project_dir/node_modules/.pnpm"

if [[ ! -d "$virtual_store" ]]; then
  echo "SemogSite native hydration: $virtual_store does not exist" >&2
  exit 1
fi

mapfile -t better_sqlite_packages < <(
  find "$virtual_store" -type d \
    -path '*/node_modules/better-sqlite3' \
    -prune \
    -print
)

if [[ ${#better_sqlite_packages[@]} -eq 0 ]]; then
  echo "SemogSite native hydration: better-sqlite3 is not installed; nothing to hydrate"
  exit 0
fi

abi="$(node -p 'process.versions.modules')"
hydrated=0

for package_dir in "${better_sqlite_packages[@]}"; do
  version="$(node -p "JSON.parse(require('node:fs').readFileSync(process.argv[1], 'utf8')).version" "$package_dir/package.json")"
  asset="$SEMOGSITE_NATIVE_ASSETS/better-sqlite3/$version/node-v$abi-linux-x64/better_sqlite3.node"
  destination="$package_dir/build/Release/better_sqlite3.node"

  if [[ ! -f "$asset" ]]; then
    echo "SemogSite native hydration: missing asset for better-sqlite3 $version, ABI $abi" >&2
    echo "Expected: $asset" >&2
    exit 1
  fi

  install -D -m 0755 "$asset" "$destination"
  hydrated=$((hydrated + 1))
done

echo "SemogSite native hydration: restored $hydrated better-sqlite3 binary/binaries for Node ABI $abi"
