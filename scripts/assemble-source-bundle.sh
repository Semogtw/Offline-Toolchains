#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: assemble-source-bundle.sh DOWNLOAD_DIR OUTPUT.gpg" >&2
  exit 2
fi

download_dir="$(cd "$1" && pwd)"
output="$2"
[[ -d "$download_dir" ]] || { echo "Download directory not found." >&2; exit 1; }
[[ ! -e "$output" ]] || { echo "Output already exists." >&2; exit 1; }

for command in find python3 sha256sum sort unzip; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done

temp_root="$(mktemp -d)"
collected="$temp_root/collected"
mkdir -p "$collected"
trap 'rm -rf "$temp_root"' EXIT

while IFS= read -r -d '' archive; do
  unzip -q -o "$archive" -d "$collected"
done < <(find "$download_dir" -maxdepth 2 -type f -name '*.zip' -print0 | sort -z)

while IFS= read -r -d '' file; do
  [[ "$file" == *.zip ]] && continue
  cp -f "$file" "$collected/$(basename "$file")"
done < <(find "$download_dir" -maxdepth 2 -type f -print0)

for required in TRANSFER.json SHA256SUMS.parts ENCRYPTED.sha256; do
  [[ -f "$collected/$required" ]] || { echo "Missing transfer file: $required" >&2; exit 1; }
done

part_count="$(python3 - "$collected/TRANSFER.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    transfer = json.load(stream)
count = transfer.get("part_count")
if transfer.get("schema_version") != 1 or not isinstance(count, int) or not 1 <= count <= 16:
    raise SystemExit("invalid transfer manifest")
print(count)
PY
)"

for (( index = 0; index < part_count; index++ )); do
  printf -v suffix '%03d' "$index"
  [[ -f "$collected/private-source.gpg.part-$suffix" ]] || { echo "Missing part $suffix." >&2; exit 1; }
done

(cd "$collected" && sha256sum -c SHA256SUMS.parts)
find "$collected" -maxdepth 1 -type f -name 'private-source.gpg.part-*' -printf '%f\n' |
  sort -V |
  while IFS= read -r part; do cat "$collected/$part"; done > "$output"

expected_line="$(cat "$collected/ENCRYPTED.sha256")"
expected_hash="${expected_line%% *}"
printf '%s  %s\n' "$expected_hash" "$output" | sha256sum -c -
printf 'Assembled verified ciphertext: %s\n' "$output"
