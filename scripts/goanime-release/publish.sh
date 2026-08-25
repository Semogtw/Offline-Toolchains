#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?source directory is required}"
cd "$source_dir"

rm -rf dist
mkdir -p dist
gh release download "$RELEASE_TAG" \
  --repo "$GOANIME_REPOSITORY" \
  --dir dist \
  --clobber \
  --pattern '*'

flutter pub get --enforce-lockfile
dart pub deps --json > "$RUNNER_TEMP/goanime-pub-deps.json"
python3 tools/generate_release_sbom.py \
  --deps-json "$RUNNER_TEMP/goanime-pub-deps.json" \
  --output dist/goanime-sbom.json \
  --source-revision "$SOURCE_SHA" \
  --flutter-version "$FLUTTER_VERSION" \
  --dart-version "$(dart --version 2>&1)"

key_path="$RUNNER_TEMP/goanime-update-manifest-ed25519.pem"
cleanup() {
  rm -f "$key_path"
}
trap cleanup EXIT
printf '%s\n' "$UPDATE_MANIFEST_SIGNING_PRIVATE_KEY" > "$key_path"

metadata_args=(
  -NoLogo
  -NoProfile
  -File tools/generate_update_metadata.ps1
  -Version "$VERSION_NAME"
  -BuildNumber "$BUILD_NUMBER"
  -TagName "$RELEASE_TAG"
  -ReleaseNotes "$RELEASE_NOTES"
  -ManifestSigningKeyPath "$key_path"
  -ManifestSigningKeyId "$UPDATE_MANIFEST_PUBLIC_KEY_ID"
  -ManifestSigningPublicKeyBase64 "$UPDATE_MANIFEST_PUBLIC_KEY_B64"
)
if [[ -n "${WINDOWS_DSA_SIGNATURE:-}" ]]; then
  metadata_args+=(-WindowsDsaSignature "$WINDOWS_DSA_SIGNATURE")
fi
if [[ -n "${UPDATE_ASSET_URL_TEMPLATE:-}" ]]; then
  metadata_args+=(-AssetUrlTemplate "$UPDATE_ASSET_URL_TEMPLATE")
fi
if [[ -n "${UPDATE_RELEASE_PAGE_URL:-}" ]]; then
  release_page_url="${UPDATE_RELEASE_PAGE_URL//\{tag\}/$RELEASE_TAG}"
  metadata_args+=(-ReleasePageUrl "$release_page_url")
fi

pwsh "${metadata_args[@]}"

checksum_line="$(grep -E '  update\.json$' dist/SHA256SUMS.txt | head -n1 || true)"
test -n "$checksum_line" || {
  echo "::error::SHA256SUMS.txt does not contain update.json."
  exit 1
}
expected_checksum="${checksum_line%% *}"
actual_checksum="$(sha256sum dist/update.json | awk '{print $1}')"
test "${expected_checksum,,}" = "${actual_checksum,,}" || {
  echo "::error::Signed update.json checksum does not match SHA256SUMS.txt."
  exit 1
}

python -m pip install --user awscli
export PATH="$HOME/.local/bin:$PATH"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
endpoint="https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com"

# Stage immutable release-specific objects first. The public latest channel is
# intentionally not touched until the GitHub release is visible.
aws s3 sync dist \
  "s3://${R2_BUCKET}/releases/${RELEASE_TAG}" \
  --endpoint-url "$endpoint" \
  --delete
aws s3api head-object \
  --bucket "$R2_BUCKET" \
  --key "releases/${RELEASE_TAG}/update.json" \
  --endpoint-url "$endpoint" >/dev/null

metadata_files=(dist/update.json dist/SHA256SUMS.txt dist/goanime-sbom.json)
if [[ -f dist/appcast.xml ]]; then
  metadata_files+=(dist/appcast.xml)
fi
gh release upload "$RELEASE_TAG" "${metadata_files[@]}" \
  --repo "$GOANIME_REPOSITORY" \
  --clobber

test "$(
  gh release view "$RELEASE_TAG" \
    --repo "$GOANIME_REPOSITORY" \
    --json isDraft \
    --jq .isDraft
)" = "true"

gh release view "$RELEASE_TAG" \
  --repo "$GOANIME_REPOSITORY" \
  --json assets \
  --jq '.assets[].name' > "$RUNNER_TEMP/goanime-release-assets.txt"

grep -Fxq 'update.json' "$RUNNER_TEMP/goanime-release-assets.txt"
grep -Fxq 'SHA256SUMS.txt' "$RUNNER_TEMP/goanime-release-assets.txt"
grep -Fxq 'goanime-sbom.json' "$RUNNER_TEMP/goanime-release-assets.txt"

notes_file="$(mktemp)"
printf '%s\n' "$RELEASE_NOTES" > "$notes_file"
gh release edit "$RELEASE_TAG" \
  --repo "$GOANIME_REPOSITORY" \
  --draft=false \
  --prerelease=false \
  --latest \
  --title "GoAnime v$VERSION_NAME" \
  --notes-file "$notes_file"
rm -f "$notes_file"

# Only after GitHub is public do installed clients see the new R2 latest pointer.
aws s3 cp dist/update.json \
  "s3://${R2_BUCKET}/latest/update.json" \
  --endpoint-url "$endpoint"
if [[ -f dist/appcast.xml ]]; then
  aws s3 cp dist/appcast.xml \
    "s3://${R2_BUCKET}/latest/appcast.xml" \
    --endpoint-url "$endpoint"
fi
aws s3 cp dist/SHA256SUMS.txt \
  "s3://${R2_BUCKET}/latest/SHA256SUMS.txt" \
  --endpoint-url "$endpoint"
aws s3api head-object \
  --bucket "$R2_BUCKET" \
  --key latest/update.json \
  --endpoint-url "$endpoint" >/dev/null
