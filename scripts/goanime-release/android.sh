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

# GoAnime tracks the compressed SQLite in Git. Flutter embeds the raw DB;
# verify and materialize it on the trusted release runner, never on-device.
python3 tools/manga/materialize_manga_availability_asset.py
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
# The packaged Flutter asset must be raw SQLite, not a GZIP sidecar.
raw_asset='assets/flutter_assets/assets/data/manga_availability.db'
version_asset='assets/flutter_assets/assets/data/manga_availability.db.version'
# Capture listing once: grep -q in a pipe with pipefail could trigger SIGPIPE.
apk_entries="$(unzip -Z1 "$apk")"
grep -Fxq "$raw_asset" <<< "$apk_entries" || {
  echo "::error::Raw Manga SQLite asset missing from Android APK."
  exit 1
}
if grep -Fxq 'assets/flutter_assets/assets/data/manga_availability.db.gz' <<< "$apk_entries"; then
  echo "::error::Compressed Manga catalog must not be an APK asset."
  exit 1
fi
expected="$(cat assets/data/manga_availability.db.version)"
actual="$(unzip -p "$apk" "$raw_asset" | sha256sum | awk '{print $1}')"
test "$actual" = "$expected" || {
  echo "::error::Android APK Manga SQLite bytes mismatch the source version."
  exit 1
}
grep -Fxq "$version_asset" <<< "$apk_entries" || {
  echo "::error::Manga SQLite version marker missing from Android APK."
  exit 1
}
cp "$apk" "dist/android-release/$ANDROID_RELEASE_APK_NAME"
gh release upload "$RELEASE_TAG" dist/android-release/* \
  --repo "$GOANIME_REPOSITORY" \
  --clobber
