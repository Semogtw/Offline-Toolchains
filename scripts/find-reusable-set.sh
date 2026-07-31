#!/usr/bin/env bash
set -euo pipefail

profile=""
package=""
lock_mode=""
lock_fingerprint=""
workflow_commit=""
receipt_dir=""
output_file=""
force_rebuild="false"
while (($#)); do
  case "$1" in
    --profile) profile="$2"; shift 2 ;;
    --package) package="$2"; shift 2 ;;
    --lock-mode) lock_mode="$2"; shift 2 ;;
    --lock-fingerprint) lock_fingerprint="$2"; shift 2 ;;
    --workflow-commit) workflow_commit="$2"; shift 2 ;;
    --receipt-dir) receipt_dir="$2"; shift 2 ;;
    --github-output) output_file="$2"; shift 2 ;;
    --force-rebuild) force_rebuild="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
for value in "$profile" "$package" "$lock_mode" "$lock_fingerprint" "$workflow_commit" "$receipt_dir" "$output_file"; do
  [[ -n "$value" ]] || { echo 'missing required reuse argument' >&2; exit 2; }
done
mkdir -p "$receipt_dir"
fp_json="$(python3 scripts/artifact_fingerprint.py \
  --profile "$profile" --package "$package" \
  --lock-mode "$lock_mode" --lock-fingerprint "$lock_fingerprint" \
  --workflow-commit "$workflow_commit")"
set_fingerprint="$(jq -r .set_fingerprint <<<"$fp_json")"
builder_fingerprint="$(jq -r .builder_fingerprint <<<"$fp_json")"
{
  echo "set_fingerprint=$set_fingerprint"
  echo "builder_fingerprint=$builder_fingerprint"
  echo "receipt_dir=$receipt_dir"
} >> "$output_file"
if [[ "$force_rebuild" == true ]]; then
  echo 'reused=false' >> "$output_file"
  exit 0
fi
: "${GH_TOKEN:?GH_TOKEN is required}"
gh api --paginate "/repos/$GITHUB_REPOSITORY/actions/artifacts?per_page=100" \
  --jq '.artifacts[]' | jq -s '{artifacts:.}' > "$RUNNER_TEMP/all-artifacts.json"
candidates="$(python3 scripts/catalog_artifacts.py candidate-manifests \
  --artifacts-json "$RUNNER_TEMP/all-artifacts.json" \
  --profile "$profile" --set-fingerprint "$set_fingerprint")"
reused=false
while IFS= read -r artifact_id; do
  [[ -n "$artifact_id" ]] || continue
  rm -rf "$RUNNER_TEMP/reuse-manifest" "$RUNNER_TEMP/reuse.zip"
  mkdir -p "$RUNNER_TEMP/reuse-manifest"
  gh api -H 'Accept: application/vnd.github+json' \
    "/repos/$GITHUB_REPOSITORY/actions/artifacts/$artifact_id/zip" > "$RUNNER_TEMP/reuse.zip"
  unzip -qq "$RUNNER_TEMP/reuse.zip" -d "$RUNNER_TEMP/reuse-manifest"
  manifest_path="$(find "$RUNNER_TEMP/reuse-manifest" -name artifact-set.json -type f -print -quit)"
  [[ -n "$manifest_path" ]] || continue
  verification="$(python3 scripts/catalog_artifacts.py verify-reusable \
    --artifacts-json "$RUNNER_TEMP/all-artifacts.json" --manifest "$manifest_path")"
  if [[ "$verification" != null ]]; then
    python3 - "$manifest_path" "$verification" "$receipt_dir/receipt.json" <<'PY'
import json, sys
manifest=json.load(open(sys.argv[1],encoding='utf-8'))
reuse=json.loads(sys.argv[2])
json.dump({'schema_version':1,'result':'reused','manifest':manifest,'artifact_ids':reuse['artifact_ids']},open(sys.argv[3],'w',encoding='utf-8'),indent=2,sort_keys=True)
PY
    reused=true
    break
  fi
done < <(jq -r '.[].id' <<<"$candidates")
echo "reused=$reused" >> "$output_file"
