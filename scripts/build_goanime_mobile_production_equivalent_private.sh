#!/usr/bin/env bash
set -euo pipefail

SOURCE_ROOT="${1:?GoAnime source checkout path is required}"
OUTPUT_DIR="${RUNNER_TEMP:?RUNNER_TEMP is required}/goanime-production-equivalent"
EXPECTED_SIGNING_SHA256="45a14fef593bf0d136502530691790ebb41a0b4b3e8e37dcb78e720099b25a08"

cd "$SOURCE_ROOT"

required=(
  FIREBASE_PROJECT_ID FIREBASE_WEB_API_KEY
  UPDATE_MANIFEST_URL UPDATE_APPCAST_URL ANIME_METADATA_SEED_MANIFEST_URL
  GOOGLE_SERVICES_JSON_BASE64
  ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD
  ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD
)
missing=()
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || missing+=("$name")
done
if (( ${#missing[@]} )); then
  printf 'Missing required private production configuration: %s\n' "${missing[*]}" >&2
  exit 1
fi

flutter config --no-analytics
flutter pub get
(cd packages/goanime_core && dart pub get)

# Discover the current season through AniList because Jikan list endpoints can
# intermittently return 504 from GitHub runners. The repository generator then
# enriches every discovered MAL ID with Jikan's per-title endpoints.
python3 - <<'PY'
import json
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

path = Path('tools/anime_metadata_seed_targets.json')
payload = json.loads(path.read_text(encoding='utf-8'))
targets = payload.setdefault('targets', [])
existing = {
    target.get('malId')
    for target in targets
    if isinstance(target, dict) and isinstance(target.get('malId'), int)
}
now = datetime.now(timezone.utc)
season = (
    'WINTER' if now.month <= 3 else
    'SPRING' if now.month <= 6 else
    'SUMMER' if now.month <= 9 else
    'FALL'
)
query = '''
query ($page: Int!, $year: Int!, $season: MediaSeason!) {
  Page(page: $page, perPage: 50) {
    pageInfo { hasNextPage }
    media(type: ANIME, seasonYear: $year, season: $season, isAdult: false, sort: POPULARITY_DESC) {
      idMal
      title { english romaji }
    }
  }
}
'''

discovered = set()
for page_number in range(1, 5):
    body = json.dumps({
        'query': query,
        'variables': {'page': page_number, 'year': now.year, 'season': season},
    }).encode('utf-8')
    document = None
    last_error = None
    for attempt in range(1, 4):
        try:
            request = urllib.request.Request(
                'https://graphql.anilist.co',
                data=body,
                headers={
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'User-Agent': 'GoAnime-Mobile-toolchain/1.0',
                },
                method='POST',
            )
            with urllib.request.urlopen(request, timeout=30) as response:
                document = json.loads(response.read().decode('utf-8'))
            break
        except Exception as error:
            last_error = error
            if attempt < 3:
                time.sleep(attempt * 2)
    if document is None:
        raise RuntimeError(f'AniList page {page_number} failed: {last_error}')
    if document.get('errors'):
        raise RuntimeError(f"AniList GraphQL errors: {document['errors']}")
    page = document['data']['Page']
    for media in page.get('media') or []:
        mal_id = media.get('idMal')
        if not isinstance(mal_id, int) or mal_id <= 0:
            continue
        discovered.add(mal_id)
        title_data = media.get('title') or {}
        title = title_data.get('english') or title_data.get('romaji') or f'MAL {mal_id}'
        if mal_id not in existing:
            targets.append({'malId': mal_id, 'title': str(title).strip()})
            existing.add(mal_id)
    if not page.get('pageInfo', {}).get('hasNextPage'):
        break

if len(discovered) < 20:
    raise RuntimeError(f'AniList returned only {len(discovered)} current-season MAL IDs')
payload['queries'] = []
path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(f'AniList discovery: {season.lower()} {now.year}, MAL IDs={len(discovered)}, total targets={len(targets)}')
PY

dart run tools/build_anime_metadata_seed.dart
cp dist/anime_metadata_cache/anime_metadata_seed.json assets/data/anime_metadata_seed.json
cp dist/anime_metadata_cache/broadcast_schedule.json assets/data/broadcast_schedule.json

python3 - <<'PY'
import json
from datetime import datetime, timezone
from pathlib import Path
seed = json.loads(Path('assets/data/anime_metadata_seed.json').read_text(encoding='utf-8'))
broadcast = json.loads(Path('assets/data/broadcast_schedule.json').read_text(encoding='utf-8'))
entries = seed.get('entries') or []
now = datetime.now(timezone.utc)
season = 'winter' if now.month <= 3 else 'spring' if now.month <= 6 else 'summer' if now.month <= 9 else 'fall'
current = [e for e in entries if e.get('year') == now.year and str(e.get('season') or '').strip().lower() == season and str(e.get('imageUrl') or '').strip()]
broadcasts = broadcast.get('entries') or {}
if len(entries) < 40:
    raise SystemExit(f'Jikan seed too small: {len(entries)}')
if len(current) < 10:
    raise SystemExit(f'Current season too small: {len(current)}')
if len(broadcasts) < 5:
    raise SystemExit(f'Broadcast snapshot too small: {len(broadcasts)}')
print(f'Fresh catalog validated: total={len(entries)} current={len(current)} broadcasts={len(broadcasts)} season={season} {now.year}')
Path('/tmp/goanime-jikan-summary.json').write_text(json.dumps({
    'generatedAt': seed.get('generatedAt'),
    'entries': len(entries),
    'currentSeasonEntries': len(current),
    'broadcasts': len(broadcasts),
    'season': season,
    'year': now.year,
}, indent=2) + '\n', encoding='utf-8')
PY

# Source gates run against the current checkout. Generated catalog assets and
# temporary target expansion are intentionally build-time-only changes.
if [[ -f tools/validate_project_health.ps1 ]]; then
  pwsh ./tools/validate_project_health.ps1
fi
dart format --output=none --set-exit-if-changed lib test packages tools
flutter analyze --no-pub
flutter test --no-pub --concurrency=2
(cd packages/goanime_core && dart test)
if [[ -f tools/validate_release_workflows.ps1 ]]; then
  pwsh ./tools/validate_release_workflows.ps1
elif [[ -f tools/validate_release_workflows.sh ]]; then
  bash ./tools/validate_release_workflows.sh
fi

# Restore native Firebase and production signing only inside this ephemeral
# private runner. Nothing is committed or copied into Offline-Toolchains.
printf '%s' "$GOOGLE_SERVICES_JSON_BASE64" | base64 --decode > android/app/google-services.json
printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 --decode > android/app/goanime-release.jks
cat > android/key.properties <<EOF
storePassword=$ANDROID_KEYSTORE_PASSWORD
keyPassword=$ANDROID_KEY_PASSWORD
keyAlias=$ANDROID_KEY_ALIAS
storeFile=goanime-release.jks
EOF
chmod 600 android/app/google-services.json android/app/goanime-release.jks android/key.properties

python3 - <<'PY'
import json
import os
from pathlib import Path
names = [
    'FIREBASE_PROJECT_ID', 'FIREBASE_WEB_API_KEY',
    'UPDATE_MANIFEST_URL', 'UPDATE_APPCAST_URL',
    'ANIME_METADATA_SEED_MANIFEST_URL', 'RUNTIME_DATABASE_MANIFEST_URL',
    'TMDB_API_KEY',
]
values = {name: os.environ.get(name, '') for name in names}
Path('/tmp/goanime-build-defines.json').write_text(
    json.dumps({name: value for name, value in values.items() if value}),
    encoding='utf-8',
)
Path('/tmp/goanime-config-presence.json').write_text(
    json.dumps({name: bool(value) for name, value in values.items()}, indent=2),
    encoding='utf-8',
)
PY

flutter build apk \
  --release \
  --target-platform android-arm64 \
  --no-pub \
  --dart-define-from-file=/tmp/goanime-build-defines.json

apk="build/app/outputs/flutter-apk/app-release.apk"
[[ -s "$apk" ]]
unzip -tq "$apk" >/dev/null
entries="$(unzip -Z1 "$apk" 'lib/*/libapp.so' || true)"
[[ "$entries" == 'lib/arm64-v8a/libapp.so' ]] || {
  echo "Expected only arm64-v8a libapp.so, found: $entries" >&2
  exit 1
}
if unzip -Z1 "$apk" | grep -q 'assets/flutter_assets/kernel_blob.bin'; then
  echo 'kernel_blob.bin found in release APK' >&2
  exit 1
fi

sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
apksigner="$(find "$sdk_root/build-tools" -type f -name apksigner | sort -V | tail -n1)"
aapt2="$(find "$sdk_root/build-tools" -type f -name aapt2 | sort -V | tail -n1)"
[[ -x "$apksigner" && -x "$aapt2" ]]

mkdir -p "$OUTPUT_DIR"
cp "$apk" "$OUTPUT_DIR/GoAnime-Mobile-production-equivalent-private-arm64.apk"
"$apksigner" verify --verbose --print-certs "$apk" > "$OUTPUT_DIR/apk-signature-report.txt"
signer_sha256="$(sed -n 's/^Signer #1 certificate SHA-256 digest: //p' "$OUTPUT_DIR/apk-signature-report.txt" | head -n1 | tr '[:upper:]' '[:lower:]')"
[[ "$signer_sha256" == "$EXPECTED_SIGNING_SHA256" ]] || {
  echo "Unexpected release signer SHA-256: $signer_sha256" >&2
  exit 1
}

"$aapt2" dump resources "$apk" > /tmp/goanime-final-resources.txt
for resource in google_app_id gcm_defaultSenderId google_api_key project_id; do
  grep -q ":string/$resource" /tmp/goanime-final-resources.txt || {
    echo "Missing Firebase Android resource: $resource" >&2
    exit 1
  }
done

# Verify packaged native Firebase components without logging configuration values.
unzip -p "$apk" classes.dex | strings > /tmp/goanime-classes-strings.txt
for marker in firebase/messaging firebase/crashlytics; do
  grep -qi "$marker" /tmp/goanime-classes-strings.txt || {
    echo "Missing native Firebase marker: $marker" >&2
    exit 1
  }
done

# Compile-time REST configuration must be present in Flutter AOT.
unzip -p "$apk" lib/arm64-v8a/libapp.so | strings > /tmp/goanime-aot-strings.txt
grep -q "$FIREBASE_PROJECT_ID" /tmp/goanime-aot-strings.txt
grep -q "$FIREBASE_WEB_API_KEY" /tmp/goanime-aot-strings.txt

sha256="$(sha256sum "$apk" | awk '{print $1}')"
size="$(stat -c '%s' "$apk")"
export APK_SHA256="$sha256" APK_SIZE="$size"

python3 - <<'PY'
import json
import os
from pathlib import Path
presence = json.loads(Path('/tmp/goanime-config-presence.json').read_text(encoding='utf-8'))
jikan = json.loads(Path('/tmp/goanime-jikan-summary.json').read_text(encoding='utf-8'))
manifest = {
    'schemaVersion': 1,
    'sourceCommit': os.environ.get('GITHUB_SHA', ''),
    'flutterMode': 'release',
    'abi': 'arm64-v8a',
    'applicationId': 'com.example.goanime_mobile',
    'signing': 'production-release-keystore',
    'signerSha256': '45a14fef593bf0d136502530691790ebb41a0b4b3e8e37dcb78e720099b25a08',
    'firebaseRestConfigured': True,
    'firebaseAndroidConfigured': True,
    'fcmConfigured': True,
    'crashlyticsConfigured': True,
    'clientConfigurationPresent': presence,
    'jikan': jikan,
    'distribution': 'private Actions artifact only; no GitHub Release, Play Store publication, Shorebird release, or update-manifest publication performed',
    'apkSha256': os.environ['APK_SHA256'],
    'apkSizeBytes': int(os.environ['APK_SIZE']),
}
Path(os.environ['RUNNER_TEMP'], 'goanime-production-equivalent', 'build-manifest.json').write_text(
    json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8'
)
PY
sha256sum "$OUTPUT_DIR/GoAnime-Mobile-production-equivalent-private-arm64.apk" > "$OUTPUT_DIR/GoAnime-Mobile-production-equivalent-private-arm64.apk.sha256"

# Always remove restored credentials before the workflow uploads its handoff.
rm -f android/app/google-services.json android/app/goanime-release.jks android/key.properties
rm -f /tmp/goanime-build-defines.json /tmp/goanime-config-presence.json /tmp/goanime-aot-strings.txt /tmp/goanime-classes-strings.txt /tmp/goanime-final-resources.txt
