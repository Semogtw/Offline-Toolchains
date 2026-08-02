#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?usage: build-hydra-toolchain.sh SOURCE_DIR BUNDLE_ROOT NODE_VERSION YARN_VERSION RUST_TOOLCHAIN}"
bundle_root="${2:?missing bundle root}"
node_version="${3:?missing Node version}"
yarn_version="${4:?missing Yarn version}"
rust_toolchain="${5:?missing Rust toolchain}"

source_dir="$(cd "$source_dir" && pwd)"
bundle_root="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$bundle_root")"
archive="${bundle_root%/*}/hydra-toolchain-linux-x64.tar.zst"
parts_dir="${bundle_root%/*}/hydra-toolchain-linux-x64-parts"
node_root="$(cd "$(dirname "$(dirname "$(readlink -f "$(command -v node)")")")" && pwd)"

cleanup_private_source() {
  rm -rf "$source_dir"
}
trap cleanup_private_source EXIT

rm -rf "$bundle_root" "$archive" "$archive.sha256" "$parts_dir"
mkdir -p \
  "$bundle_root/node" \
  "$bundle_root/yarn" \
  "$bundle_root/yarn-cache" \
  "$bundle_root/npm-cache" \
  "$bundle_root/electron-cache" \
  "$bundle_root/electron-builder-cache" \
  "$bundle_root/node-gyp-cache" \
  "$bundle_root/xdg-cache" \
  "$bundle_root/cargo-home/bin" \
  "$bundle_root/rustup-home" \
  "$bundle_root/reference-inputs" \
  "$bundle_root/scripts" \
  "$parts_dir"

cp -a "$node_root/." "$bundle_root/node/"

export PATH="$bundle_root/cargo-home/bin:$bundle_root/yarn/bin:$bundle_root/node/bin:$PATH"
export CARGO_HOME="$bundle_root/cargo-home"
export RUSTUP_HOME="$bundle_root/rustup-home"
export YARN_CACHE_FOLDER="$bundle_root/yarn-cache"
export npm_config_cache="$bundle_root/npm-cache"
export ELECTRON_CACHE="$bundle_root/electron-cache"
export ELECTRON_BUILDER_CACHE="$bundle_root/electron-builder-cache"
export npm_config_devdir="$bundle_root/node-gyp-cache"
export XDG_CACHE_HOME="$bundle_root/xdg-cache"
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
export CI=true

"$bundle_root/node/bin/npm" install \
  --global \
  --prefix "$bundle_root/yarn" \
  "yarn@$yarn_version"

cp "$(command -v rustup)" "$bundle_root/cargo-home/bin/rustup"
chmod +x "$bundle_root/cargo-home/bin/rustup"
for proxy in cargo cargo-clippy cargo-fmt clippy-driver rustc rustdoc rustfmt; do
  ln -s rustup "$bundle_root/cargo-home/bin/$proxy"
done

rustup toolchain install "$rust_toolchain" --profile minimal
rustup default "$rust_toolchain"

actual_node_version="$(node --version)"
actual_yarn_version="$(yarn --version)"
[[ "$actual_node_version" == "v$node_version" ]] || {
  echo "Expected Node v$node_version, found $actual_node_version" >&2
  exit 1
}
[[ "$actual_yarn_version" == "$yarn_version" ]] || {
  echo "Expected Yarn $yarn_version, found $actual_yarn_version" >&2
  exit 1
}

cd "$source_dir"
yarn install --frozen-lockfile --non-interactive
cargo fetch \
  --locked \
  --manifest-path native/hydra-native/Cargo.toml
cargo fetch \
  --locked \
  --manifest-path native/game-agent/Cargo.toml

yarn typecheck
yarn test

cp package.json "$bundle_root/reference-inputs/package.json"
cp yarn.lock "$bundle_root/reference-inputs/yarn.lock"
cp native/hydra-native/Cargo.lock \
  "$bundle_root/reference-inputs/hydra-native.Cargo.lock"
cp native/game-agent/Cargo.lock \
  "$bundle_root/reference-inputs/game-agent.Cargo.lock"

cat > "$bundle_root/scripts/activate.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
toolchain_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export HYDRA_TOOLCHAIN_ROOT="$toolchain_root"
export PATH="$toolchain_root/cargo-home/bin:$toolchain_root/yarn/bin:$toolchain_root/node/bin:$PATH"
export CARGO_HOME="$toolchain_root/cargo-home"
export RUSTUP_HOME="$toolchain_root/rustup-home"
export YARN_CACHE_FOLDER="$toolchain_root/yarn-cache"
export npm_config_cache="$toolchain_root/npm-cache"
export ELECTRON_CACHE="$toolchain_root/electron-cache"
export ELECTRON_BUILDER_CACHE="$toolchain_root/electron-builder-cache"
export npm_config_devdir="$toolchain_root/node-gyp-cache"
export XDG_CACHE_HOME="$toolchain_root/xdg-cache"
export npm_config_audit=false
export npm_config_fund=false
export npm_config_update_notifier=false
export CI=true
EOF

cat > "$bundle_root/scripts/install-offline.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
toolchain_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=activate.sh
source "$toolchain_root/scripts/activate.sh"

project="${1:-$PWD}"
project="$(cd "$project" && pwd)"

verify_exact_input() {
  local expected="$1"
  local actual="$2"
  test -f "$expected"
  test -f "$actual"
  local expected_sha actual_sha
  expected_sha="$(sha256sum "$expected" | cut -d' ' -f1)"
  actual_sha="$(sha256sum "$actual" | cut -d' ' -f1)"
  [[ "$expected_sha" == "$actual_sha" ]] || {
    echo "Hydra toolchain input mismatch: $actual" >&2
    echo "Expected: $expected_sha" >&2
    echo "Actual:   $actual_sha" >&2
    exit 1
  }
}

verify_exact_input \
  "$toolchain_root/reference-inputs/package.json" \
  "$project/package.json"
verify_exact_input \
  "$toolchain_root/reference-inputs/yarn.lock" \
  "$project/yarn.lock"
verify_exact_input \
  "$toolchain_root/reference-inputs/hydra-native.Cargo.lock" \
  "$project/native/hydra-native/Cargo.lock"
verify_exact_input \
  "$toolchain_root/reference-inputs/game-agent.Cargo.lock" \
  "$project/native/game-agent/Cargo.lock"

fresh_home="$(mktemp -d "${TMPDIR:-/tmp}/hydra-offline-home.XXXXXX")"
cleanup() {
  rm -rf "$fresh_home"
}
trap cleanup EXIT
export HOME="$fresh_home"

# Force every known package and binary download route to fail fast. Successful
# installation therefore proves that the portable caches are sufficient.
export npm_config_registry="http://127.0.0.1:9"
export YARN_REGISTRY="http://127.0.0.1:9"
export ELECTRON_MIRROR="http://127.0.0.1:9/"
export npm_config_disturl="http://127.0.0.1:9/"
export HTTP_PROXY="http://127.0.0.1:9"
export HTTPS_PROXY="http://127.0.0.1:9"
export ALL_PROXY="http://127.0.0.1:9"
export NO_PROXY="127.0.0.1,localhost"
export CARGO_NET_OFFLINE=true

yarn --cwd "$project" install \
  --offline \
  --frozen-lockfile \
  --non-interactive
cargo fetch \
  --offline \
  --locked \
  --manifest-path "$project/native/hydra-native/Cargo.toml"
cargo fetch \
  --offline \
  --locked \
  --manifest-path "$project/native/game-agent/Cargo.toml"
EOF

cat > "$bundle_root/scripts/doctor.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
toolchain_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=activate.sh
source "$toolchain_root/scripts/activate.sh"

node --version
yarn --version
rustc --version
cargo --version
python3 --version
pkg-config --modversion gtk4
pkg-config --modversion gtk4-layer-shell-0
for required_dir in \
  "$YARN_CACHE_FOLDER" \
  "$CARGO_HOME/registry" \
  "$ELECTRON_CACHE" \
  "$ELECTRON_BUILDER_CACHE" \
  "$npm_config_devdir" \
  "$XDG_CACHE_HOME"; do
  test -d "$required_dir" || {
    echo "Missing Hydra toolchain cache: $required_dir" >&2
    exit 1
  }
done
printf 'Hydra offline toolchain doctor: PASS\n'
EOF

chmod +x "$bundle_root/scripts/"*.sh

package_sha256="$(sha256sum package.json | cut -d' ' -f1)"
yarn_lock_sha256="$(sha256sum yarn.lock | cut -d' ' -f1)"
native_lock_sha256="$(sha256sum native/hydra-native/Cargo.lock | cut -d' ' -f1)"
agent_lock_sha256="$(sha256sum native/game-agent/Cargo.lock | cut -d' ' -f1)"

{
  echo "schema_version=2"
  echo "repository=${GITHUB_REPOSITORY:-Semogtw/Offline-Toolchains}"
  echo "hydra_repository=Semogtw/HydraPersonalizado"
  echo "hydra_ref=${HYDRA_REF:-unknown}"
  echo "runner=${RUNNER_OS:-Linux}-${RUNNER_ARCH:-X64}"
  echo "created_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "node_version=$(node --version)"
  echo "yarn_version=$(yarn --version)"
  echo "rustc_version=$(rustc --version)"
  echo "cargo_version=$(cargo --version)"
  echo "package_sha256=$package_sha256"
  echo "yarn_lock_sha256=$yarn_lock_sha256"
  echo "hydra_native_cargo_lock_sha256=$native_lock_sha256"
  echo "game_agent_cargo_lock_sha256=$agent_lock_sha256"
  echo "electron_cache=electron-cache"
  echo "electron_builder_cache=electron-builder-cache"
  echo "node_gyp_cache=node-gyp-cache"
  echo "activate=scripts/activate.sh"
  echo "offline_install=scripts/install-offline.sh"
  echo "doctor=scripts/doctor.sh"
} > "$bundle_root/MANIFEST.txt"

rm -rf \
  "$source_dir/node_modules" \
  "$source_dir/hydra-native" \
  "$source_dir/hydra-game-agent" \
  "$source_dir/native/hydra-native/target" \
  "$source_dir/native/game-agent/target"

"$bundle_root/scripts/install-offline.sh" "$source_dir"
(
  cd "$source_dir"
  yarn typecheck
  yarn test
)
"$bundle_root/scripts/doctor.sh"

rm -rf "$source_dir"
trap - EXIT

tar -C "$(dirname "$bundle_root")" -I 'zstd -T0 -8' \
  -cf "$archive" "$(basename "$bundle_root")"
sha256sum "$archive" > "$archive.sha256"
split -b 400M -d -a 2 \
  "$archive" \
  "$parts_dir/hydra-toolchain-linux-x64.part-"
(
  cd "$parts_dir"
  sha256sum hydra-toolchain-linux-x64.part-* > SHA256SUMS.parts
)

part_count="$(
  find "$parts_dir" -maxdepth 1 -type f \
    -name 'hydra-toolchain-linux-x64.part-*' | wc -l
)"
test "$part_count" -ge 1
if (( part_count > 16 )); then
  echo "Hydra toolchain exceeds the 16-part transfer limit." >&2
  exit 1
fi

{
  echo "archive=$(basename "$archive")"
  echo "archive_sha256=$(cut -d' ' -f1 "$archive.sha256")"
  echo "part_count=$part_count"
  echo "part_size=400M"
  echo "package_sha256=$package_sha256"
  echo "yarn_lock_sha256=$yarn_lock_sha256"
  echo "reassemble=cat hydra-toolchain-linux-x64.part-* > $(basename "$archive")"
  echo "verify_parts=sha256sum -c SHA256SUMS.parts"
  echo "extract=tar --zstd -xf $(basename "$archive")"
  echo
  ls -lh "$parts_dir"/hydra-toolchain-linux-x64.part-*
} > "$parts_dir/PARTS.txt"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "parts_dir=$parts_dir"
    echo "archive_sha=$archive.sha256"
    echo "bundle_root=$bundle_root"
    for index in $(seq -f '%02g' 0 15); do
      if [[ -f "$parts_dir/hydra-toolchain-linux-x64.part-$index" ]]; then
        echo "part_$index=true"
      fi
    done
  } >> "$GITHUB_OUTPUT"
fi

ls -lh "$archive" "$archive.sha256" "$parts_dir"/*
