#!/usr/bin/env bash
set -euo pipefail

EXPECTED_FLEXIBLE_ADAPTER_SHA="c80135339bcff5f7f8c2c2380329dfc155b26232"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat <<'USAGE'
Usage: build_reference_runtime.sh --anikku-root DIR --goanime-source-root DIR \
  --harness-script FILE --output-dir DIR --goanime-source-sha SHA \
  --anikku-sha SHA --flexible-adapter-sha SHA --jdk-major N

Build the pinned Anikku debug and instrumentation APKs once and emit the
sanitized three-file reference-runtime artifact. The exact-source fallback is
selected only after bounded primary failures or an explicit validation flag.
USAGE
}

die() {
  echo "reference runtime build failed: $1" >&2
  exit 1
}

ANIKKU_ROOT=""
GOANIME_SOURCE_ROOT=""
HARNESS_SCRIPT=""
OUTPUT_DIR=""
GOANIME_SOURCE_SHA=""
ANIKKU_SHA=""
FLEXIBLE_ADAPTER_SHA=""
JDK_MAJOR=""
MAX_ATTEMPTS=3
FORCE_FLEXIBLE_ADAPTER_FALLBACK="${GOANIME_YUZONO_FORCE_FLEXIBLE_ADAPTER_FALLBACK:-0}"

while (($#)); do
  case "$1" in
    --anikku-root) ANIKKU_ROOT="$2"; shift 2 ;;
    --goanime-source-root) GOANIME_SOURCE_ROOT="$2"; shift 2 ;;
    --harness-script) HARNESS_SCRIPT="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --goanime-source-sha) GOANIME_SOURCE_SHA="$2"; shift 2 ;;
    --anikku-sha) ANIKKU_SHA="$2"; shift 2 ;;
    --flexible-adapter-sha) FLEXIBLE_ADAPTER_SHA="$2"; shift 2 ;;
    --jdk-major) JDK_MAJOR="$2"; shift 2 ;;
    --max-attempts) MAX_ATTEMPTS="$2"; shift 2 ;;
    --force-flexible-adapter-fallback)
      FORCE_FLEXIBLE_ADAPTER_FALLBACK=1
      shift
      ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; die "unknown option" ;;
  esac
done

for required in ANIKKU_ROOT GOANIME_SOURCE_ROOT HARNESS_SCRIPT OUTPUT_DIR GOANIME_SOURCE_SHA ANIKKU_SHA FLEXIBLE_ADAPTER_SHA JDK_MAJOR; do
  [[ -n "${!required}" ]] || die "$required is required"
done

[[ "$GOANIME_SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || die "GoAnime source identity is invalid"
[[ "$ANIKKU_SHA" =~ ^[0-9a-f]{40}$ ]] || die "Anikku identity is invalid"
[[ "$FLEXIBLE_ADAPTER_SHA" == "$EXPECTED_FLEXIBLE_ADAPTER_SHA" ]] || die "FlexibleAdapter fallback identity is not the allowed full SHA"
[[ "$JDK_MAJOR" == 17 ]] || die "JDK major must be 17"
[[ "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || die "max attempts is invalid"
case "$FORCE_FLEXIBLE_ADAPTER_FALLBACK" in
  0|1|false|true) ;;
  *) die "fallback mode is invalid" ;;
esac

[[ -d "$ANIKKU_ROOT" && -x "$ANIKKU_ROOT/gradlew" ]] || die "Anikku checkout is unavailable"
[[ -f "$HARNESS_SCRIPT" ]] || die "probe harness is unavailable"
[[ -d "$GOANIME_SOURCE_ROOT" ]] || die "GoAnime checkout is unavailable"
actual_jdk_major="$(java -version 2>&1 | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p' | head -n 1)"
[[ "$actual_jdk_major" == "$JDK_MAJOR" ]] || die "JDK identity mismatch"

actual_goanime_sha="$(git -C "$GOANIME_SOURCE_ROOT" rev-parse HEAD 2>/dev/null || true)"
[[ "$actual_goanime_sha" == "$GOANIME_SOURCE_SHA" ]] || die "GoAnime source identity mismatch"
actual_anikku_sha="$(git -C "$ANIKKU_ROOT" rev-parse HEAD 2>/dev/null || true)"
[[ "$actual_anikku_sha" == "$ANIKKU_SHA" ]] || die "Anikku identity mismatch"

mkdir -p "$OUTPUT_DIR"
[[ -z "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]] || die "output directory must be empty"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/goanime-yuzono-reference.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT
build_log="$temporary_root/gradle.log"

run_gradle() {
  if "$@" >"$build_log" 2>&1; then
    return 0
  fi
  echo "reference runtime Gradle attempt failed; diagnostic output was withheld" >&2
  return 1
}

python3 "$HARNESS_SCRIPT" --anikku-root "$ANIKKU_ROOT"

build_attempt=0
primary_succeeded=0
if [[ "$FORCE_FLEXIBLE_ADAPTER_FALLBACK" != "1" && "$FORCE_FLEXIBLE_ADAPTER_FALLBACK" != "true" ]]; then
  for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    build_attempt="$attempt"
    echo "reference runtime primary build attempt $attempt/$MAX_ATTEMPTS"
    gradle_args=( :app:assembleDebug :app:assembleDebugAndroidTest --no-daemon --console=plain )
    if (( attempt > 1 )); then
      gradle_args+=( --refresh-dependencies )
    fi
    if (cd "$ANIKKU_ROOT" && run_gradle ./gradlew "${gradle_args[@]}"); then
      primary_succeeded=1
      break
    fi
  done
else
  echo "reference runtime exact-source fallback explicitly requested for validation"
fi

fallback_used=false
if (( primary_succeeded == 0 )); then
  if [[ "$FORCE_FLEXIBLE_ADAPTER_FALLBACK" != "1" && "$FORCE_FLEXIBLE_ADAPTER_FALLBACK" != "true" ]] && ! grep -Eiq 'FlexibleAdapter|flexible-adapter|jitpack' "$build_log"; then
    die "pinned Anikku build failed outside the allowed FlexibleAdapter fallback boundary"
  fi
  fallback_used=true
  build_attempt=$((MAX_ATTEMPTS + 1))
  fallback_root="$temporary_root/flexible-adapter"
  fallback_checkout="$fallback_root/source"
  fallback_maven_repo="$fallback_root/maven-repository"
  fallback_init_script="$fallback_root/audit-fallback.init.gradle"

  echo "preparing exact FlexibleAdapter fallback source"
  git clone --quiet --no-checkout --filter=blob:none https://github.com/arkon/FlexibleAdapter.git "$fallback_checkout" >/dev/null 2>&1 || die "FlexibleAdapter source checkout failed"
  git -C "$fallback_checkout" fetch --quiet --depth=1 origin "$FLEXIBLE_ADAPTER_SHA" >/dev/null 2>&1 || die "FlexibleAdapter exact SHA fetch failed"
  git -C "$fallback_checkout" checkout --quiet --detach "$FLEXIBLE_ADAPTER_SHA" >/dev/null 2>&1 || die "FlexibleAdapter exact SHA checkout failed"
  fallback_head="$(git -C "$fallback_checkout" rev-parse HEAD 2>/dev/null || true)"
  [[ "$fallback_head" == "$FLEXIBLE_ADAPTER_SHA" ]] || die "FlexibleAdapter exact SHA verification failed"
  fallback_tree="$(git -C "$fallback_checkout" rev-parse HEAD^{tree} 2>/dev/null || true)"

  echo "building exact FlexibleAdapter fallback library"
  fallback_gradle_args=( :flexible-adapter:assembleRelease --no-daemon --console=plain )
  (cd "$fallback_checkout" && run_gradle ./gradlew "${fallback_gradle_args[@]}" ) || die "FlexibleAdapter fallback build failed"
  fallback_aar="$(find "$fallback_checkout" -type f -path '*/build/outputs/aar/flexible-adapter*.aar' -print 2>/dev/null | sort | head -n 1)"
  [[ -n "$fallback_aar" ]] || die "FlexibleAdapter fallback AAR is missing"
  fallback_aar_sha="$(sha256sum "$fallback_aar" | awk '{print $1}')"
  [[ "$fallback_aar_sha" =~ ^[0-9a-f]{64}$ ]] || die "FlexibleAdapter fallback AAR digest is invalid"

  mkdir -p "$fallback_maven_repo/com/github/arkon/FlexibleAdapter/flexible-adapter/${FLEXIBLE_ADAPTER_SHA:0:8}"
  cp "$fallback_aar" "$fallback_maven_repo/com/github/arkon/FlexibleAdapter/flexible-adapter/${FLEXIBLE_ADAPTER_SHA:0:8}/flexible-adapter-${FLEXIBLE_ADAPTER_SHA:0:8}.aar"
  python3 - "$fallback_maven_repo" "$FLEXIBLE_ADAPTER_SHA" <<'PY'
from pathlib import Path
import sys

repository, revision = sys.argv[1:]
version = revision[:8]
directory = Path(repository) / "com" / "github" / "arkon" / "FlexibleAdapter" / "flexible-adapter" / version
(directory / f"flexible-adapter-{version}.pom").write_text(
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    "<project xmlns=\"http://maven.apache.org/POM/4.0.0\">\n"
    "  <modelVersion>4.0.0</modelVersion>\n"
    "  <groupId>com.github.arkon.FlexibleAdapter</groupId>\n"
    "  <artifactId>flexible-adapter</artifactId>\n"
    f"  <version>{version}</version>\n"
    "  <packaging>aar</packaging>\n"
    "</project>\n",
    encoding="utf-8",
)
PY
  GOANIME_AUDIT_MAVEN_REPO="$fallback_maven_repo" python3 - "$fallback_init_script" <<'PY'
from pathlib import Path
import sys

Path(sys.argv[1]).write_text(
    "gradle.settingsEvaluated { settings ->\n"
    "    def repositories = settings.dependencyResolutionManagement.repositories\n"
    "    def localFallback = repositories.maven {\n"
    "        name = 'goanimeAuditFlexibleAdapter'\n"
    "        url = uri(System.getenv('GOANIME_AUDIT_MAVEN_REPO'))\n"
    "    }\n"
    "    repositories.remove(localFallback)\n"
    "    repositories.addFirst(localFallback)\n"
    "}\n",
    encoding="utf-8",
)
PY
  echo "flexible_adapter_fallback_source_sha=$fallback_head"
  echo "flexible_adapter_fallback_source_tree=$fallback_tree"
  echo "flexible_adapter_fallback_aar_sha256=$fallback_aar_sha"

  fallback_gradle_args=( :app:assembleDebug :app:assembleDebugAndroidTest --no-daemon --console=plain --init-script "$fallback_init_script" )
  (cd "$ANIKKU_ROOT" && run_gradle ./gradlew "${fallback_gradle_args[@]}" ) || die "Anikku exact-source fallback build failed"
fi

echo "fallbackUsed=$fallback_used"

find_apk() {
  local base="$1"
  local preferred
  preferred="$(find "$base" -type f \( -name '*x86_64*.apk' -o -name '*universal*.apk' \) -print 2>/dev/null | sort | head -n 1)"
  if [[ -n "$preferred" ]]; then
    printf '%s\n' "$preferred"
    return 0
  fi
  find "$base" -type f -name '*.apk' -print 2>/dev/null | sort | head -n 1
}

app_apk="$(find_apk "$ANIKKU_ROOT/app/build/outputs/apk/debug")"
test_apk="$(find_apk "$ANIKKU_ROOT/app/build/outputs/apk/androidTest")"
[[ -n "$app_apk" ]] || die "Anikku debug APK is missing"
[[ -n "$test_apk" ]] || die "Anikku androidTest APK is missing"
cp "$app_apk" "$OUTPUT_DIR/anikku-app-debug.apk"
cp "$test_apk" "$OUTPUT_DIR/anikku-app-debug-androidTest.apk"

python3 "$SCRIPT_DIR/write_reference_manifest.py" \
  --output "$OUTPUT_DIR/reference-runtime-manifest.json" \
  --goanime-source-sha "$GOANIME_SOURCE_SHA" \
  --anikku-sha "$ANIKKU_SHA" \
  --flexible-adapter-sha "$FLEXIBLE_ADAPTER_SHA" \
  --app-apk "$OUTPUT_DIR/anikku-app-debug.apk" \
  --test-apk "$OUTPUT_DIR/anikku-app-debug-androidTest.apk" \
  --jdk-major "$JDK_MAJOR" \
  --build-attempt "$build_attempt" \
  $(if [[ "$fallback_used" == true ]]; then echo --fallback-used; else echo --no-fallback-used; fi)

python3 "$SCRIPT_DIR/verify_reference_manifest.py" \
  --manifest "$OUTPUT_DIR/reference-runtime-manifest.json" \
  --app-apk "$OUTPUT_DIR/anikku-app-debug.apk" \
  --test-apk "$OUTPUT_DIR/anikku-app-debug-androidTest.apk" \
  --goanime-source-sha "$GOANIME_SOURCE_SHA" \
  --anikku-sha "$ANIKKU_SHA" \
  --flexible-adapter-sha "$FLEXIBLE_ADAPTER_SHA" \
  --jdk-major "$JDK_MAJOR"

[[ "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq 3 ]] || die "reference runtime artifact has unexpected files"
[[ -z "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]] || die "reference runtime artifact has unexpected directories"
echo "reference runtime artifact contains one app APK, one test APK and one manifest"
