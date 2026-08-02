#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <delta-root> <target-gradle-user-home>" >&2
  exit 64
fi

delta_root="$(cd "$1" && pwd)"
target="$2"
source_repo="$delta_root/maven-repo"
source_init="$delta_root/goanime-offline-maven.init.gradle"

test -d "$source_repo"
test -f "$source_init"
mkdir -p "$target/offline-goanime-maven" "$target/init.d"
cp -a "$source_repo/." "$target/offline-goanime-maven/"
install -m 0644 "$source_init" "$target/init.d/goanime-offline-maven.gradle"

echo "GoAnime Gradle delta applied to $target"
