#!/usr/bin/env bash
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT

delta="$root/goanime-lock-delta"
toolchain="$root/goanime-toolchain"
mkdir -p "$delta/pub-cache/hosted/pub.dev/alpha-1.0.0" \
  "$toolchain/pub-cache" "$toolchain/flutter/bin/cache/dart-sdk/bin" \
  "$toolchain/flutter/packages/flutter_tools"
printf '{"schema_version":1,"flutter_version":"3.44.1","dart_version":"3.12.1","package_count":1,"packages":{"alpha":"1.0.0"}}\n' \
  > "$delta/HOSTED-LOCK.json"
printf '#!/usr/bin/env python3\n' > "$delta/goanime-lock-cache.py"
printf '#!/usr/bin/env bash\nprintf "%%s" "${PUB_CACHE:-missing}" > "${REPAIR_LOG:?}"\n' \
  > "$delta/repair-portable-flutter.sh"
chmod +x "$delta/goanime-lock-cache.py" "$delta/repair-portable-flutter.sh"
printf '#!/usr/bin/env bash\nexport BASE_ACTIVATED=true\n' > "$toolchain/activate.sh"
chmod +x "$toolchain/activate.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$toolchain/flutter/bin/cache/dart-sdk/bin/dart"
chmod +x "$toolchain/flutter/bin/cache/dart-sdk/bin/dart"
printf 'name: flutter_tools\n' > "$toolchain/flutter/packages/flutter_tools/pubspec.yaml"

export REPAIR_LOG="$root/repair.log"
bash scripts/apply-goanime-lock-delta.sh "$delta" "$toolchain"
[[ -d "$toolchain/pub-cache/hosted/pub.dev/alpha-1.0.0" ]]
[[ -x "$toolchain/activate-exact.sh" ]]
grep -q 'HOSTED-LOCK.json' "$toolchain/activate-exact.sh"
[[ "$(cat "$REPAIR_LOG")" == "$toolchain/pub-cache" ]]

printf 'test_apply_goanime_lock_delta: PASS\n'
