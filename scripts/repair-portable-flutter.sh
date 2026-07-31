#!/usr/bin/env bash
set -euo pipefail

flutter_root="${1:-${FLUTTER_ROOT:-}}"
if [[ -z "$flutter_root" ]]; then
  printf 'ERROR: pass FLUTTER_ROOT as the first argument or environment variable\n' >&2
  exit 2
fi
flutter_root="$(cd "$flutter_root" && pwd)"
dart="$flutter_root/bin/cache/dart-sdk/bin/dart"
flutter_tools="$flutter_root/packages/flutter_tools"
stamp="$flutter_root/bin/cache/.offline-toolchains-portable-root"

[[ -x "$dart" ]] || {
  printf 'ERROR: bundled Dart executable not found: %s\n' "$dart" >&2
  exit 1
}
[[ -f "$flutter_tools/pubspec.yaml" ]] || {
  printf 'ERROR: flutter_tools pubspec not found: %s\n' "$flutter_tools/pubspec.yaml" >&2
  exit 1
}

if [[ -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$flutter_root" ]]; then
  exit 0
fi

rm -rf "$flutter_tools/.dart_tool"
"$dart" pub --suppress-analytics \
  --directory "$flutter_tools" \
  get --offline --example
printf '%s\n' "$flutter_root" > "$stamp"
