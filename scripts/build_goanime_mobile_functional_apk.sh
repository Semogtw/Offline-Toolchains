#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:?private source checkout path is required}"
PATCH_HELPER="${2:?checkpoint patch helper path is required}"
OUTPUT_DIR="${RUNNER_TEMP:?RUNNER_TEMP is required}/goanime-mobile-apk"

cd "$SOURCE_ROOT"
flutter config --no-analytics
flutter pub get
(cd packages/goanime_core && dart pub get)

python3 "$PATCH_HELPER"
dart format \
  lib/services/download/download_queue_manager_hls.dart \
  lib/services/download/hls/hls_package_store.dart \
  lib/services/download/hls/hls_transfer_models.dart \
  lib/services/download/hls/filesystem_hls_package_store.dart \
  lib/services/download/hls/saf_hls_package_store.dart \
  lib/services/download/hls/hls_download_engine_support.dart \
  test
git diff --check

flutter test --no-pub test/services/download/hls/hls_checkpoint_reference_test.dart
flutter test --no-pub test/services/download/hls
python3 -m unittest discover -s tools/tests -p 'test_*.py'
python3 tools/validate_repository_guards.py
flutter analyze --no-pub
flutter test --no-pub
(cd packages/goanime_core && dart test)
bash ./tools/validate_release_workflows.sh
dart format --output=none --set-exit-if-changed lib test packages tools

python3 - <<'PY'
import subprocess

allowed_exact = {
    'lib/services/download/download_queue_manager_hls.dart',
    'lib/services/download/hls/hls_package_store.dart',
    'lib/services/download/hls/hls_transfer_models.dart',
    'lib/services/download/hls/filesystem_hls_package_store.dart',
    'lib/services/download/hls/saf_hls_package_store.dart',
    'lib/services/download/hls/hls_download_engine_support.dart',
}
changed = subprocess.check_output(
    ['git', 'diff', '--name-only'], text=True
).splitlines()
unexpected = [
    path for path in changed
    if path not in allowed_exact and not path.startswith('test/')
]
if unexpected:
    raise SystemExit(f'Unexpected source changes: {unexpected}')
if not changed:
    raise SystemExit('Expected the checkpoint migration to change source files.')
PY

SOURCE_BASE_SHA="$(git rev-parse HEAD)"
export SOURCE_BASE_SHA
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/services/download/download_queue_manager_hls.dart \
  lib/services/download/hls/hls_package_store.dart \
  lib/services/download/hls/hls_transfer_models.dart \
  lib/services/download/hls/filesystem_hls_package_store.dart \
  lib/services/download/hls/saf_hls_package_store.dart \
  lib/services/download/hls/hls_download_engine_support.dart \
  test
git commit -m 'fix(downloads): preserve opaque HLS checkpoint references [skip ci]'
SOURCE_SHA="$(git rev-parse HEAD)"
export SOURCE_SHA

if [[ -z "${RUNTIME_DATABASE_MANIFEST_URL:-}" && -n "${UPDATE_MANIFEST_URL:-}" ]]; then
  case "$UPDATE_MANIFEST_URL" in
    */latest/update.json)
      RUNTIME_DATABASE_MANIFEST_URL="${UPDATE_MANIFEST_URL%/update.json}/runtime_database_manifest.json"
      export RUNTIME_DATABASE_MANIFEST_URL
      ;;
  esac
fi

python3 - <<'PY'
import json
import os
from pathlib import Path

names = [
    'FIREBASE_PROJECT_ID',
    'FIREBASE_WEB_API_KEY',
    'UPDATE_MANIFEST_URL',
    'UPDATE_APPCAST_URL',
    'ANIME_METADATA_SEED_MANIFEST_URL',
    'RUNTIME_DATABASE_MANIFEST_URL',
]
values = {name: os.environ.get(name, '') for name in names}
Path('/tmp/goanime-build-defines.json').write_text(
    json.dumps({name: value for name, value in values.items() if value})
)
Path('/tmp/goanime-config-presence.json').write_text(
    json.dumps({name: bool(value) for name, value in values.items()}, indent=2)
)
PY

if [[ -n "${GOOGLE_SERVICES_JSON_BASE64:-}" ]]; then
  printf '%s' "$GOOGLE_SERVICES_JSON_BASE64" | base64 --decode > android/app/google-services.json
  GOOGLE_SERVICES_PRESENT=true
else
  GOOGLE_SERVICES_PRESENT=false
fi
export GOOGLE_SERVICES_PRESENT

signing_present=0
for name in \
  ANDROID_KEYSTORE_BASE64 \
  ANDROID_KEYSTORE_PASSWORD \
  ANDROID_KEY_ALIAS \
  ANDROID_KEY_PASSWORD; do
  [[ -n "${!name:-}" ]] && signing_present=$((signing_present + 1))
done

if [[ $signing_present -eq 4 ]]; then
  printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > android/app/goanime-release.jks
  {
    echo "storePassword=$ANDROID_KEYSTORE_PASSWORD"
    echo "keyPassword=$ANDROID_KEY_PASSWORD"
    echo "keyAlias=$ANDROID_KEY_ALIAS"
    echo "storeFile=goanime-release.jks"
  } > android/key.properties
  APK_SIGNING=release-keystore
elif [[ $signing_present -eq 0 ]]; then
  APK_SIGNING=debug-fallback
else
  echo 'Android signing secrets are only partially configured.' >&2
  exit 1
fi
export APK_SIGNING

flutter build apk \
  --release \
  --target-platform android-arm64 \
  --no-pub \
  --dart-define-from-file=/tmp/goanime-build-defines.json

mkdir -p "$OUTPUT_DIR"
apk="$(find build/app/outputs -type f -name '*.apk' -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
[[ -n "$apk" && -f "$apk" ]] || {
  echo 'No APK was produced.' >&2
  exit 1
}
cp "$apk" "$OUTPUT_DIR/GoAnime-Mobile-functional-arm64.apk"
unzip -t "$OUTPUT_DIR/GoAnime-Mobile-functional-arm64.apk" >/dev/null

entries="$(unzip -Z1 "$OUTPUT_DIR/GoAnime-Mobile-functional-arm64.apk" 'lib/*/libapp.so' || true)"
[[ "$entries" == 'lib/arm64-v8a/libapp.so' ]] || {
  echo "Expected only arm64-v8a libapp.so, found: $entries" >&2
  exit 1
}

sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
apksigner="$(find "$sdk_root/build-tools" -type f -name apksigner | sort -V | tail -n1)"
[[ -x "$apksigner" ]] || {
  echo 'apksigner was not found.' >&2
  exit 1
}
"$apksigner" verify --verbose --print-certs \
  "$OUTPUT_DIR/GoAnime-Mobile-functional-arm64.apk" \
  > "$OUTPUT_DIR/apk-signature-report.txt"

python3 - <<'PY'
import json
import os
from pathlib import Path

presence = json.loads(Path('/tmp/goanime-config-presence.json').read_text())
manifest = {
    'artifact': 'GoAnime-Mobile-functional-arm64.apk',
    'sourceBaseCommit': os.environ['SOURCE_BASE_SHA'],
    'verifiedWorkspaceCommit': os.environ['SOURCE_SHA'],
    'workspaceCommitPublished': False,
    'flutterVersion': os.environ.get('FLUTTER_VERSION', '3.44.1'),
    'abi': 'arm64-v8a',
    'buildMode': 'release',
    'applicationId': 'com.example.goanime_mobile',
    'signing': os.environ['APK_SIGNING'],
    'googleServicesJson': os.environ['GOOGLE_SERVICES_PRESENT'] == 'true',
    'clientConfigurationPresent': presence,
    'intentionallyExcludedFromApk': [
        'PRIVATE_REPOSITORIES_TOKEN',
        'CLOUDFLARE_ACCOUNT_ID',
        'R2_ACCESS_KEY_ID',
        'R2_SECRET_ACCESS_KEY',
        'SHOREBIRD_TOKEN',
        'GitHub tokens',
        'private signing key material',
    ],
}
output = Path(os.environ['RUNNER_TEMP']) / 'goanime-mobile-apk'
(output / 'build-manifest.json').write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + '\n'
)
PY

sha256sum "$OUTPUT_DIR/GoAnime-Mobile-functional-arm64.apk" \
  > "$OUTPUT_DIR/GoAnime-Mobile-functional-arm64.apk.sha256"

rm -f \
  android/app/google-services.json \
  android/app/goanime-release.jks \
  android/key.properties
