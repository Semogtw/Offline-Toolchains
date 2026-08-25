#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?source directory is required}"
cd "$source_dir"

if [[ "${GITHUB_REPOSITORY_OWNER:-}" != "Semogtw" ]]; then
  echo "::error::This privileged workflow is restricted to the repository owner."
  exit 1
fi

test -n "${GH_TOKEN:-}" || {
  echo "::error::GOANIME_RELEASE_TOKEN or PRIVATE_REPOSITORIES_TOKEN is required."
  exit 1
}

source_sha="$(git rev-parse HEAD)"
version="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+)\+([0-9]+).*$/\1/p' pubspec.yaml | head -n1)"
build_number="$(sed -nE 's/^version:[[:space:]]*([^+[:space:]]+)\+([0-9]+).*$/\2/p' pubspec.yaml | head -n1)"

test -n "$version" || {
  echo "::error::Unable to parse pubspec.yaml version."
  exit 1
}
test "${INPUT_VERSION:-}" = "$version" || {
  echo "::error::Requested version ${INPUT_VERSION:-<empty>} does not match pubspec.yaml version $version."
  exit 1
}

normalized_platforms="$(PLATFORMS="${PLATFORMS:-}" python3 - <<'PY'
import os

allowed = {"android", "windows", "linux"}
raw = os.environ.get("PLATFORMS", "")
parts = [part.strip().lower() for part in raw.split(",") if part.strip()]
if not parts:
    raise SystemExit("::error::At least one release platform is required.")
unknown = [part for part in parts if part not in allowed]
if unknown:
    raise SystemExit(
        "::error::Unsupported release platform(s): " + ", ".join(sorted(set(unknown)))
    )
seen = set()
normalized = []
for part in parts:
    if part not in seen:
        seen.add(part)
        normalized.append(part)
print(",".join(normalized))
PY
)"
PLATFORMS="$normalized_platforms"
export PLATFORMS

release_tag="release-v${version}"

pwsh -NoLogo -NoProfile -File ./tools/validate_release_workflows.ps1

if [[ -z "${RUNTIME_DATABASE_MANIFEST_URL:-}" ]]; then
  case "${UPDATE_MANIFEST_URL:-}" in
    */latest/update.json)
      RUNTIME_DATABASE_MANIFEST_URL="${UPDATE_MANIFEST_URL%/update.json}/runtime_database_manifest.json"
      export RUNTIME_DATABASE_MANIFEST_URL
      ;;
    *)
      echo "::error::RUNTIME_DATABASE_MANIFEST_URL is empty and UPDATE_MANIFEST_URL does not end with /latest/update.json."
      exit 1
      ;;
  esac
fi

required=(
  GH_TOKEN
  SHOREBIRD_TOKEN
  FIREBASE_PROJECT_ID
  FIREBASE_WEB_API_KEY
  UPDATE_MANIFEST_URL
  UPDATE_APPCAST_URL
  UPDATE_MANIFEST_PUBLIC_KEY_ID
  UPDATE_MANIFEST_PUBLIC_KEY_B64
  UPDATE_MANIFEST_SIGNING_PRIVATE_KEY
  ANIME_METADATA_SEED_MANIFEST_URL
  RUNTIME_DATABASE_MANIFEST_URL
  CLOUDFLARE_ACCOUNT_ID
  R2_ACCESS_KEY_ID
  R2_SECRET_ACCESS_KEY
  R2_BUCKET
)
for name in "${required[@]}"; do
  test -n "${!name:-}" || {
    echo "::error::$name secret is required."
    exit 1
  }
done

if [[ ",$PLATFORMS," == *",android,"* ]]; then
  for name in ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD; do
    test -n "${!name:-}" || {
      echo "::error::$name secret is required for Android releases."
      exit 1
    }
  done
fi

if [[ ",$PLATFORMS," == *",windows,"* ]]; then
  for name in AUTO_UPDATER_DSA_PUBLIC_KEY AUTO_UPDATER_DSA_PRIVATE_KEY; do
    test -n "${!name:-}" || {
      echo "::error::$name secret is required for Windows releases."
      exit 1
    }
  done
fi

UPDATE_MANIFEST_PUBLIC_KEY_B64="$UPDATE_MANIFEST_PUBLIC_KEY_B64" python3 - <<'PY'
import base64
import binascii
import os
import re

key_id = os.environ.get("UPDATE_MANIFEST_PUBLIC_KEY_ID", "").strip()
if not re.fullmatch(r"[A-Za-z0-9._-]{1,64}", key_id):
    raise SystemExit("::error::UPDATE_MANIFEST_PUBLIC_KEY_ID has an invalid format.")
try:
    key = base64.b64decode(
        os.environ["UPDATE_MANIFEST_PUBLIC_KEY_B64"].strip(),
        validate=True,
    )
except (binascii.Error, ValueError) as error:
    raise SystemExit(f"::error::UPDATE_MANIFEST_PUBLIC_KEY_B64 is invalid Base64: {error}")
if len(key) != 32:
    raise SystemExit("::error::UPDATE_MANIFEST_PUBLIC_KEY_B64 must decode to exactly 32 bytes.")
PY

notes_file="$(mktemp)"
trap 'rm -f "$notes_file"' EXIT
printf '%s\n' "${RELEASE_NOTES:-}" > "$notes_file"

if gh release view "$release_tag" --repo "$GOANIME_REPOSITORY" >/dev/null 2>&1; then
  is_draft="$(gh release view "$release_tag" --repo "$GOANIME_REPOSITORY" --json isDraft --jq .isDraft)"
  test "$is_draft" = "true" || {
    echo "::error::Release $release_tag is already published; refusing to overwrite it."
    exit 1
  }

  tag_type="$(gh api "repos/$GOANIME_REPOSITORY/git/ref/tags/$release_tag" --jq .object.type)"
  tag_sha="$(gh api "repos/$GOANIME_REPOSITORY/git/ref/tags/$release_tag" --jq .object.sha)"
  if [[ "$tag_type" == "tag" ]]; then
    tag_sha="$(gh api "repos/$GOANIME_REPOSITORY/git/tags/$tag_sha" --jq .object.sha)"
  fi
  test "$tag_sha" = "$source_sha" || {
    echo "::error::Existing draft $release_tag points to $tag_sha, but this run resolved $source_sha. Refusing a mixed-source release."
    exit 1
  }

  gh release edit "$release_tag" \
    --repo "$GOANIME_REPOSITORY" \
    --draft=true \
    --prerelease=false \
    --title "GoAnime v$version" \
    --notes-file "$notes_file"
else
  gh release create "$release_tag" \
    --repo "$GOANIME_REPOSITORY" \
    --target "$source_sha" \
    --draft \
    --prerelease=false \
    --title "GoAnime v$version" \
    --notes-file "$notes_file"
fi

{
  echo "source_sha=$source_sha"
  echo "release_tag=$release_tag"
  echo "version_name=$version"
  echo "build_number=$build_number"
  echo "platforms=$PLATFORMS"
} >> "$GITHUB_OUTPUT"
