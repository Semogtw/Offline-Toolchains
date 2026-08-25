#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?source directory is required}"
cd "$source_dir"

cleanup() {
  rm -f android/app/goanime-release.jks android/key.properties
}
trap cleanup EXIT

mkdir -p android/app
echo "$ANDROID_KEYSTORE_BASE64" | base64 --decode > android/app/goanime-release.jks
{
  echo "storePassword=$ANDROID_KEYSTORE_PASSWORD"
  echo "keyPassword=$ANDROID_KEY_PASSWORD"
  echo "keyAlias=$ANDROID_KEY_ALIAS"
  echo "storeFile=goanime-release.jks"
} > android/key.properties

flutter pub get --enforce-lockfile

if [[ -z "${RUNTIME_DATABASE_MANIFEST_URL:-}" ]]; then
  RUNTIME_DATABASE_MANIFEST_URL="${UPDATE_MANIFEST_URL%/update.json}/runtime_database_manifest.json"
  export RUNTIME_DATABASE_MANIFEST_URL
fi

shorebird release android \
  --flutter-version="$FLUTTER_VERSION" \
  --artifact apk \
  --target-platform="$ANDROID_TARGET_PLATFORM" \
  -- \
  --dart-define="FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID" \
  --dart-define="FIREBASE_WEB_API_KEY=$FIREBASE_WEB_API_KEY" \
  --dart-define="UPDATE_MANIFEST_URL=$UPDATE_MANIFEST_URL" \
  --dart-define="UPDATE_APPCAST_URL=$UPDATE_APPCAST_URL" \
  --dart-define="UPDATE_MANIFEST_PUBLIC_KEY_ID=$UPDATE_MANIFEST_PUBLIC_KEY_ID" \
  --dart-define="UPDATE_MANIFEST_PUBLIC_KEY_B64=$UPDATE_MANIFEST_PUBLIC_KEY_B64" \
  --dart-define=UPDATE_MANIFEST_SIGNATURE_REQUIRED=true \
  --dart-define="ANIME_METADATA_SEED_MANIFEST_URL=$ANIME_METADATA_SEED_MANIFEST_URL" \
  --dart-define="RUNTIME_DATABASE_MANIFEST_URL=$RUNTIME_DATABASE_MANIFEST_URL"

mkdir -p dist/android-release
apk="build/app/outputs/flutter-apk/app-release.apk"
test -s "$apk" || {
  echo "::error::Expected Android arm64 APK was not produced."
  exit 1
}
entries="$(unzip -Z1 "$apk" 'lib/*/libapp.so' || true)"
test "$entries" = "lib/arm64-v8a/libapp.so" || {
  echo "::error::Android APK must contain only arm64-v8a libapp.so. Found: $entries"
  exit 1
}
cp "$apk" "dist/android-release/$ANDROID_RELEASE_APK_NAME"
gh release upload "$RELEASE_TAG" dist/android-release/* \
  --repo "$GOANIME_REPOSITORY" \
  --clobber
