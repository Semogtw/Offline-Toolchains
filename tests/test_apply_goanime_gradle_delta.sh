#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/delta/maven-repo/example/group/artifact/1.0.0"
printf 'test\n' > \
  "$tmp/delta/maven-repo/example/group/artifact/1.0.0/artifact-1.0.0.pom"
cp "$root/scripts/goanime-offline-maven.init.gradle" \
  "$tmp/delta/goanime-offline-maven.init.gradle"

engine_version="1.0.0-engine"
engine_cache="$tmp/target/caches/modules-2/files-2.1/io.flutter/flutter_embedding_debug/$engine_version"
mkdir -p "$engine_cache/jar-hash" "$engine_cache/pom-hash"
printf 'engine jar\n' > \
  "$engine_cache/jar-hash/flutter_embedding_debug-$engine_version.jar"
printf '<project/>\n' > \
  "$engine_cache/pom-hash/flutter_embedding_debug-$engine_version.pom"

bash "$root/scripts/apply-goanime-gradle-delta.sh" \
  "$tmp/delta" "$tmp/target"
test -f \
  "$tmp/target/offline-goanime-maven/example/group/artifact/1.0.0/artifact-1.0.0.pom"
test -f "$tmp/target/init.d/goanime-offline-maven.gradle"
test -f \
  "$tmp/target/offline-goanime-maven/io/flutter/flutter_embedding_debug/$engine_version/flutter_embedding_debug-$engine_version.jar"
test -f \
  "$tmp/target/offline-goanime-maven/io/flutter/flutter_embedding_debug/$engine_version/flutter_embedding_debug-$engine_version.pom"

# Applying the same delta twice must remain safe and preserve canonical files.
bash "$root/scripts/apply-goanime-gradle-delta.sh" \
  "$tmp/delta" "$tmp/target"
grep -Fqx 'engine jar' \
  "$tmp/target/offline-goanime-maven/io/flutter/flutter_embedding_debug/$engine_version/flutter_embedding_debug-$engine_version.jar"
