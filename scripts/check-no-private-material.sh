#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

private_name_pattern='(^|/)([^/]*private[^/]*\.asc|id_(rsa|ed25519|ecdsa)(\.pub)?|[^/]*private[_-]?key[^/]*)$'
tracked_private_names="$(git ls-files | grep -E -i "$private_name_pattern" || true)"
if [[ -n "$tracked_private_names" ]]; then
  echo 'Tracked filenames look like private key material:' >&2
  printf '%s\n' "$tracked_private_names" >&2
  exit 1
fi

private_markers='BEGIN (PGP PRIVATE KEY BLOCK|OPENSSH PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY|DSA PRIVATE KEY)'
if git grep -n -I -E "$private_markers" -- . ':!scripts/check-no-private-material.sh'; then
  echo 'Tracked files contain a private-key marker.' >&2
  exit 1
fi

echo 'Private material gate passed.'
