#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?source directory is required}"
cd "$source_dir"

cleanup() {
  if [[ -f tools/manga/configure_shorebird_edition.py ]]; then
    python3 tools/manga/configure_shorebird_edition.py --restore || true
  fi
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

# Endpoint dart-defines are hex-encoded so the compiled binary does not
# carry the plain URLs (the workers.dev host embeds a personal username).
# The app decodes them at runtime (decodeCompiledEndpoint).
encode_endpoint() { printf '%s' "$1" | od -An -tx1 | tr -d ' \n'; }
UPDATE_MANIFEST_URL_DEFINE="hex:$(encode_endpoint "$UPDATE_MANIFEST_URL")"
UPDATE_APPCAST_URL_DEFINE="hex:$(encode_endpoint "$UPDATE_APPCAST_URL")"
RUNTIME_DATABASE_MANIFEST_URL_DEFINE="hex:$(encode_endpoint "$RUNTIME_DATABASE_MANIFEST_URL")"

common_dart_defines=(
  --dart-define="FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID"
  --dart-define="FIREBASE_WEB_API_KEY=$FIREBASE_WEB_API_KEY"
  --dart-define="UPDATE_MANIFEST_URL=$UPDATE_MANIFEST_URL_DEFINE"
  --dart-define="UPDATE_APPCAST_URL=$UPDATE_APPCAST_URL_DEFINE"
  --dart-define="UPDATE_MANIFEST_PUBLIC_KEY_ID=$UPDATE_MANIFEST_PUBLIC_KEY_ID"
  --dart-define="UPDATE_MANIFEST_PUBLIC_KEY_B64=$UPDATE_MANIFEST_PUBLIC_KEY_B64"
  --dart-define=UPDATE_MANIFEST_SIGNATURE_REQUIRED=true
  --dart-define="ANIME_METADATA_SEED_MANIFEST_URL=$ANIME_METADATA_SEED_MANIFEST_URL"
  --dart-define="RUNTIME_DATABASE_MANIFEST_URL=$RUNTIME_DATABASE_MANIFEST_URL_DEFINE"
)

verify_android_apk() {
  local apk_path="$1"
  local label="$2"
  test -s "$apk_path" || {
    echo "::error::Expected ${label} arm64 APK was not produced."
    exit 1
  }
  local entries
  entries="$(unzip -Z1 "$apk_path" 'lib/*/libapp.so' || true)"
  test "$entries" = "lib/arm64-v8a/libapp.so" || {
    echo "::error::${label} APK must contain only arm64-v8a libapp.so. Found: $entries"
    exit 1
  }
  # The packaged Flutter asset must be raw SQLite, not a GZIP sidecar.
  local raw_asset='assets/flutter_assets/assets/data/manga_availability.db'
  local version_asset='assets/flutter_assets/assets/data/manga_availability.db.version'
  # Capture listing once: grep -q in a pipe with pipefail could trigger SIGPIPE.
  local apk_entries
  apk_entries="$(unzip -Z1 "$apk_path")"
  grep -Fxq "$raw_asset" <<< "$apk_entries" || {
    echo "::error::Raw Manga SQLite asset missing from ${label} APK."
    exit 1
  }
  if grep -Fxq 'assets/flutter_assets/assets/data/manga_availability.db.gz' <<< "$apk_entries"; then
    echo "::error::Compressed Manga catalog must not be an APK asset."
    exit 1
  fi
  local expected
  local actual
  expected="$(cat assets/data/manga_availability.db.version)"
  actual="$(unzip -p "$apk_path" "$raw_asset" | sha256sum | awk '{print $1}')"
  test "$actual" = "$expected" || {
    echo "::error::${label} APK Manga SQLite bytes mismatch the source version."
    exit 1
  }
  grep -Fxq "$version_asset" <<< "$apk_entries" || {
    echo "::error::Manga SQLite version marker missing from ${label} APK."
    exit 1
  }
}

shorebird release android \
  --flutter-version="$FLUTTER_VERSION" \
  --artifact apk \
  --target-platform="$ANDROID_TARGET_PLATFORM" \
  -- \
  "${common_dart_defines[@]}"

mkdir -p dist/android-release
apk="build/app/outputs/flutter-apk/app-release.apk"
verify_android_apk "$apk" "Android"
cp "$apk" "dist/android-release/$ANDROID_RELEASE_APK_NAME"

if [[ "${BUILD_MANGA_ONLY:-true}" == "true" && -n "${ANDROID_MANGA_ONLY_RELEASE_APK_NAME:-}" ]]; then
  if [[ -n "${SHOREBIRD_MANGA_ONLY_APP_ID:-}" ]]; then
    python3 tools/manga/configure_shorebird_edition.py \
      --app-id "$SHOREBIRD_MANGA_ONLY_APP_ID"
    shorebird release android \
      --flutter-version="$FLUTTER_VERSION" \
      --artifact apk \
      --target-platform="$ANDROID_TARGET_PLATFORM" \
      -- \
      --dart-define=GOANIME_MANGA_ONLY=true \
      "${common_dart_defines[@]}"
    python3 tools/manga/configure_shorebird_edition.py --restore
  else
    echo "::warning::SHOREBIRD_MANGA_ONLY_APP_ID is unset; building signed Manga-only APK without Shorebird OTA registration."
    flutter build apk \
      --release \
      --target-platform="$ANDROID_TARGET_PLATFORM" \
      --dart-define=GOANIME_MANGA_ONLY=true \
      "${common_dart_defines[@]}"
  fi
  verify_android_apk "$apk" "Manga-only Android"
  python3 tools/manga/verify_manga_only_apk.py "$apk"
  cp "$apk" "dist/android-release/$ANDROID_MANGA_ONLY_RELEASE_APK_NAME"
fi

gh release upload "$RELEASE_TAG" dist/android-release/* \
  --repo "$GOANIME_REPOSITORY" \
  --clobber
