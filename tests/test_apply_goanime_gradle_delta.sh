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

bash "$root/scripts/apply-goanime-gradle-delta.sh" \
  "$tmp/delta" "$tmp/target"
test -f \
  "$tmp/target/offline-goanime-maven/example/group/artifact/1.0.0/artifact-1.0.0.pom"
test -f "$tmp/target/init.d/goanime-offline-maven.gradle"

# Applying the same delta twice must remain safe.
bash "$root/scripts/apply-goanime-gradle-delta.sh" \
  "$tmp/delta" "$tmp/target"
