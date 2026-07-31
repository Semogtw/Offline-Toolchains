#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: assemble-artifact.sh DOWNLOAD_DIR OUTPUT.tar.zst [ARTIFACT_SET_ID]" >&2
  exit 2
fi
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
args=("$1" "$2")
if [[ $# -eq 3 ]]; then args+=(--artifact-set-id "$3"); fi
exec python3 "$script_dir/assemble_artifact.py" "${args[@]}"
