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
target_repo="$target/offline-goanime-maven"
engine_cache="$target/caches/modules-2/files-2.1/io.flutter"

test -d "$source_repo"
test -f "$source_init"
mkdir -p "$target_repo" "$target/init.d"
cp -a "$source_repo/." "$target_repo/"
install -m 0644 "$source_init" "$target/init.d/goanime-offline-maven.gradle"

python3 - "$engine_cache" "$target_repo/io/flutter" <<'PY'
from __future__ import annotations

import hashlib
import shutil
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
allowed_suffixes = {'.aar', '.jar', '.module', '.pom'}
copied = 0

if source.is_dir():
    for artifact_dir in sorted(path for path in source.iterdir() if path.is_dir()):
        for version_dir in sorted(path for path in artifact_dir.iterdir() if path.is_dir()):
            destination = target / artifact_dir.name / version_dir.name
            for candidate in sorted(version_dir.rglob('*')):
                if not candidate.is_file() or candidate.suffix not in allowed_suffixes:
                    continue
                destination.mkdir(parents=True, exist_ok=True)
                output = destination / candidate.name
                if output.exists():
                    if hashlib.sha256(output.read_bytes()).digest() != hashlib.sha256(
                        candidate.read_bytes()
                    ).digest():
                        raise SystemExit(f'conflicting Flutter Maven artifact: {output}')
                    continue
                shutil.copy2(candidate, output)
                copied += 1

print(f'Flutter engine Maven artifacts exposed: {copied}')
PY

echo "GoAnime Gradle delta applied to $target"
