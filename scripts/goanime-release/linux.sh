#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?source directory is required}"
cd "$source_dir"

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  clang cmake curl elfutils file flatpak flatpak-builder libfuse2t64 libgtk-3-dev \
  libjsoncpp-dev liblzma-dev libmpv-dev libsecret-1-0 libsecret-1-dev \
  libsoup-3.0-dev libwebkit2gtk-4.1-dev \
  gstreamer1.0-libav gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
  lld llvm ninja-build pkg-config

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
export PATH="$HOME/.cargo/bin:$PATH"

flatpak --user remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak --user install -y flathub org.gnome.Platform//50 org.gnome.Sdk//50

flutter pub get --enforce-lockfile

if [[ -z "${RUNTIME_DATABASE_MANIFEST_URL:-}" ]]; then
  RUNTIME_DATABASE_MANIFEST_URL="${UPDATE_MANIFEST_URL%/update.json}/runtime_database_manifest.json"
  export RUNTIME_DATABASE_MANIFEST_URL
fi

shorebird release \
  --platforms=linux \
  --flutter-version="$FLUTTER_VERSION" \
  --dart-define="FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID" \
  --dart-define="FIREBASE_WEB_API_KEY=$FIREBASE_WEB_API_KEY" \
  --dart-define="UPDATE_MANIFEST_URL=$UPDATE_MANIFEST_URL" \
  --dart-define="UPDATE_APPCAST_URL=$UPDATE_APPCAST_URL" \
  --dart-define="UPDATE_MANIFEST_PUBLIC_KEY_ID=$UPDATE_MANIFEST_PUBLIC_KEY_ID" \
  --dart-define="UPDATE_MANIFEST_PUBLIC_KEY_B64=$UPDATE_MANIFEST_PUBLIC_KEY_B64" \
  --dart-define=UPDATE_MANIFEST_SIGNATURE_REQUIRED=true \
  --dart-define="ANIME_METADATA_SEED_MANIFEST_URL=$ANIME_METADATA_SEED_MANIFEST_URL" \
  --dart-define="RUNTIME_DATABASE_MANIFEST_URL=$RUNTIME_DATABASE_MANIFEST_URL"

bash tools/package_linux_appimage.sh
flatpak-builder --force-clean --repo=build/flatpak-repo build/flatpak packaging/linux/com.goanime.desktop.yml
flatpak build-bundle \
  build/flatpak-repo \
  dist/linux-release/GoAnime-linux-x86_64.flatpak \
  com.goanime.desktop

test -s dist/linux-release/GoAnime-linux-x86_64.AppImage
test -s dist/linux-release/GoAnime-linux-x86_64.flatpak

gh release upload "$RELEASE_TAG" dist/linux-release/* \
  --repo "$GOANIME_REPOSITORY" \
  --clobber
