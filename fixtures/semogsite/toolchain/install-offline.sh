#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=activate.sh
source "$script_dir/activate.sh"

project_dir="${1:-$PWD}"
shift || true
project_dir="$(cd "$project_dir" && pwd)"

install_args=(
  install
  --dir "$project_dir"
  --offline
  --ignore-scripts
  --store-dir "$PNPM_STORE_DIR"
  --config.confirmModulesPurge=false
)

if [[ -f "$project_dir/pnpm-lock.yaml" && "${SEMOGSITE_FROZEN_LOCKFILE:-1}" != "0" ]]; then
  install_args+=(--frozen-lockfile)
else
  install_args+=(--no-frozen-lockfile)
fi

pnpm "${install_args[@]}" "$@"
"$script_dir/hydrate-native-assets.sh" "$project_dir"

echo "SemogSite offline install completed in $project_dir"
echo "The dependency lifecycle scripts stayed disabled; the required better-sqlite3 binary was restored from the verified toolchain asset cache."
