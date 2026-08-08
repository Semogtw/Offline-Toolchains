#!/usr/bin/env bash
set -euo pipefail

bundle_root="${1:?usage: sanitize-hydra-toolchain.sh BUNDLE_ROOT PARTS_DIR ARCHIVE_SHA_FILE}"
parts_dir="${2:?missing parts directory}"
archive_sha_file="${3:?missing archive sha file}"
archive="${archive_sha_file%.sha256}"
manifest="$bundle_root/MANIFEST.txt"
reference_dir="$bundle_root/reference-inputs"

required_value() {
  local key="$1"
  local value
  value="$(awk -F= -v key="$key" '$1 == key { print $2; exit }' "$manifest")"
  test -n "$value" || {
    echo "Hydra public toolchain manifest is missing $key" >&2
    exit 1
  }
  printf '%s\n' "$value"
}

package_sha256="$(required_value package_sha256)"
yarn_lock_sha256="$(required_value yarn_lock_sha256)"
native_lock_sha256="$(required_value hydra_native_cargo_lock_sha256)"
agent_lock_sha256="$(required_value game_agent_cargo_lock_sha256)"

# The cache itself contains public third-party packages, but the exact private
# package/lock files are confidential project metadata. Keep only fingerprints.
rm -rf "$reference_dir"
mkdir -p "$reference_dir"
cat > "$reference_dir/SHA256.txt" <<EOF
package.json=$package_sha256
yarn.lock=$yarn_lock_sha256
native/hydra-native/Cargo.lock=$native_lock_sha256
native/game-agent/Cargo.lock=$agent_lock_sha256
EOF

# The selected private branch/tag/SHA is not needed to restore the public
# dependency cache. Keep it out of the public manifest as well.
python3 - "$manifest" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = []
for line in path.read_text(encoding="utf-8").splitlines():
    if line.startswith("hydra_ref="):
        lines.append("hydra_ref=redacted")
    else:
        lines.append(line)
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

cat > "$bundle_root/scripts/install-offline.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
toolchain_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=activate.sh
source "$toolchain_root/scripts/activate.sh"

project="${1:-$PWD}"
project="$(cd "$project" && pwd)"
fingerprints="$toolchain_root/reference-inputs/SHA256.txt"
test -f "$fingerprints"

expected_sha() {
  local key="$1"
  local value
  value="$(awk -F= -v key="$key" '$1 == key { print $2; exit }' "$fingerprints")"
  test -n "$value" || {
    echo "Missing Hydra toolchain fingerprint: $key" >&2
    exit 1
  }
  printf '%s\n' "$value"
}

verify_exact_input() {
  local key="$1"
  local actual="$2"
  test -f "$actual" || {
    echo "Hydra toolchain input is missing: $actual" >&2
    exit 1
  }
  local expected actual_sha
  expected="$(expected_sha "$key")"
  actual_sha="$(sha256sum "$actual" | cut -d' ' -f1)"
  [[ "$expected" == "$actual_sha" ]] || {
    echo "Hydra toolchain input mismatch: $actual" >&2
    echo "Expected fingerprint: $expected" >&2
    echo "Actual fingerprint:   $actual_sha" >&2
    exit 1
  }
}

verify_exact_input package.json "$project/package.json"
verify_exact_input yarn.lock "$project/yarn.lock"
verify_exact_input native/hydra-native/Cargo.lock "$project/native/hydra-native/Cargo.lock"
verify_exact_input native/game-agent/Cargo.lock "$project/native/game-agent/Cargo.lock"

fresh_home="$(mktemp -d "${TMPDIR:-/tmp}/hydra-offline-home.XXXXXX")"
cleanup() {
  rm -rf "$fresh_home"
}
trap cleanup EXIT
export HOME="$fresh_home"

export npm_config_registry="http://127.0.0.1:9"
export YARN_REGISTRY="http://127.0.0.1:9"
export ELECTRON_MIRROR="http://127.0.0.1:9/"
export npm_config_disturl="http://127.0.0.1:9/"
export HTTP_PROXY="http://127.0.0.1:9"
export HTTPS_PROXY="http://127.0.0.1:9"
export ALL_PROXY="http://127.0.0.1:9"
export NO_PROXY="127.0.0.1,localhost"
export CARGO_NET_OFFLINE=true

yarn --cwd "$project" install --offline --frozen-lockfile --non-interactive
cargo fetch --offline --locked --manifest-path "$project/native/hydra-native/Cargo.toml"
cargo fetch --offline --locked --manifest-path "$project/native/game-agent/Cargo.toml"
EOF
chmod +x "$bundle_root/scripts/install-offline.sh"
bash -n "$bundle_root/scripts/install-offline.sh"

# Rebuild the archive and its split parts only after raw private inputs are gone.
rm -f "$archive" "$archive_sha_file"
rm -rf "$parts_dir"
mkdir -p "$parts_dir"
tar -C "$(dirname "$bundle_root")" -I 'zstd -T0 -8' \
  -cf "$archive" "$(basename "$bundle_root")"
sha256sum "$archive" > "$archive_sha_file"
split -b 400M -d -a 2 "$archive" "$parts_dir/hydra-toolchain-linux-x64.part-"
(
  cd "$parts_dir"
  sha256sum hydra-toolchain-linux-x64.part-* > SHA256SUMS.parts
)

part_count="$(find "$parts_dir" -maxdepth 1 -type f -name 'hydra-toolchain-linux-x64.part-*' | wc -l | tr -d ' ')"
test "$part_count" -ge 1
if (( part_count > 16 )); then
  echo "Hydra toolchain exceeds the 16-part transfer limit after sanitization." >&2
  exit 1
fi

archive_sha256="$(cut -d' ' -f1 "$archive_sha_file")"
cat > "$parts_dir/PARTS.txt" <<EOF
archive=$(basename "$archive")
archive_sha256=$archive_sha256
part_count=$part_count
part_size=400M
package_sha256=$package_sha256
yarn_lock_sha256=$yarn_lock_sha256
hydra_native_cargo_lock_sha256=$native_lock_sha256
game_agent_cargo_lock_sha256=$agent_lock_sha256
reassemble=cat hydra-toolchain-linux-x64.part-* > $(basename "$archive")
verify_parts=sha256sum -c SHA256SUMS.parts
extract=tar --zstd -xf $(basename "$archive")
EOF

cp "$manifest" "$parts_dir/MANIFEST.txt"
cp "$reference_dir/SHA256.txt" "$parts_dir/INPUT-SHA256.txt"
cp "$archive_sha_file" "$parts_dir/ARCHIVE.sha256"

echo "Hydra public toolchain sanitized: raw private package/lock inputs removed; parts=$part_count"
