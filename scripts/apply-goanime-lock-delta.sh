#!/usr/bin/env bash
set -euo pipefail

delta_root="${1:-}"
toolchain_root="${2:-}"
if [[ -z "$delta_root" || -z "$toolchain_root" ]]; then
  printf 'Usage: %s <delta-root> <goanime-toolchain-root>\n' "$0" >&2
  exit 2
fi

delta_root="$(cd "$delta_root" && pwd)"
toolchain_root="$(cd "$toolchain_root" && pwd)"

[[ -d "$delta_root/pub-cache" && ! -L "$delta_root/pub-cache" ]] || {
  printf 'ERROR: delta Pub cache is missing or unsafe: %s\n' "$delta_root/pub-cache" >&2
  exit 1
}
[[ -d "$toolchain_root/pub-cache" && ! -L "$toolchain_root/pub-cache" ]] || {
  printf 'ERROR: toolchain Pub cache is missing or unsafe: %s\n' "$toolchain_root/pub-cache" >&2
  exit 1
}
[[ -d "$toolchain_root/flutter" && ! -L "$toolchain_root/flutter" ]] || {
  printf 'ERROR: toolchain Flutter directory is missing or unsafe: %s\n' "$toolchain_root/flutter" >&2
  exit 1
}
for file in HOSTED-LOCK.json goanime-lock-cache.py repair-portable-flutter.sh; do
  [[ -f "$delta_root/$file" && ! -L "$delta_root/$file" ]] || {
    printf 'ERROR: delta file is missing or unsafe: %s\n' "$delta_root/$file" >&2
    exit 1
  }
done

cp -a "$delta_root/pub-cache/." "$toolchain_root/pub-cache/"
install -m 0644 "$delta_root/HOSTED-LOCK.json" "$toolchain_root/HOSTED-LOCK.json"
install -m 0755 "$delta_root/goanime-lock-cache.py" "$toolchain_root/goanime-lock-cache.py"
install -m 0755 "$delta_root/repair-portable-flutter.sh" "$toolchain_root/repair-portable-flutter.sh"

cat > "$toolchain_root/activate-exact.sh" <<'EOFACTIVATE'
#!/usr/bin/env bash
set -euo pipefail
toolchain_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$toolchain_root/activate.sh"
"$toolchain_root/repair-portable-flutter.sh" "$FLUTTER_ROOT"
python3 "$toolchain_root/goanime-lock-cache.py" verify-cache \
  --manifest "$toolchain_root/HOSTED-LOCK.json" \
  --pub-cache "$PUB_CACHE"
EOFACTIVATE
chmod +x "$toolchain_root/activate-exact.sh"

PUB_CACHE="$toolchain_root/pub-cache" \
  "$toolchain_root/repair-portable-flutter.sh" "$toolchain_root/flutter"
python3 "$toolchain_root/goanime-lock-cache.py" verify-cache \
  --manifest "$toolchain_root/HOSTED-LOCK.json" \
  --pub-cache "$toolchain_root/pub-cache"

printf 'GoAnime exact Pub cache applied to %s\n' "$toolchain_root"
