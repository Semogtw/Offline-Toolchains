#!/usr/bin/env bash
set -euo pipefail

root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
flutter_root="$root/flutter"
mkdir -p "$flutter_root/bin/cache/dart-sdk/bin" "$flutter_root/packages/flutter_tools/.dart_tool"
printf 'name: flutter_tools\n' > "$flutter_root/packages/flutter_tools/pubspec.yaml"
log="$root/dart.log"
cat > "$flutter_root/bin/cache/dart-sdk/bin/dart" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${DART_CALL_LOG:?}"
mkdir -p "${FAKE_FLUTTER_ROOT:?}/packages/flutter_tools/.dart_tool"
printf '{"configVersion":2}\n' > "${FAKE_FLUTTER_ROOT:?}/packages/flutter_tools/.dart_tool/package_config.json"
EOF
chmod +x "$flutter_root/bin/cache/dart-sdk/bin/dart"
export DART_CALL_LOG="$log"
export FAKE_FLUTTER_ROOT="$flutter_root"

bash "$(dirname "$0")/repair-portable-flutter.sh" "$flutter_root"
[[ "$(wc -l < "$log")" -eq 1 ]]
grep -q 'pub --suppress-analytics --directory .*flutter_tools get --offline --example' "$log"

bash "$(dirname "$0")/repair-portable-flutter.sh" "$flutter_root"
[[ "$(wc -l < "$log")" -eq 1 ]]

moved="$root/moved-flutter"
mv "$flutter_root" "$moved"
export FAKE_FLUTTER_ROOT="$moved"
bash "$(dirname "$0")/repair-portable-flutter.sh" "$moved"
[[ "$(wc -l < "$log")" -eq 2 ]]

printf 'test_repair_portable_flutter: PASS\n'
