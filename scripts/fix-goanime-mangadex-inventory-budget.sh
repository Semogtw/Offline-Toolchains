#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"

request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-mangadex-inventory-budget-fix/*.request' | head -n 1)"
test -n "$request"
read -r project target_branch expected_sha < "$request"
test "$project" = goanime
[[ "$target_branch" =~ ^[A-Za-z0-9._/-]{1,200}$ ]]
[[ "$target_branch" != /* ]]
[[ "$target_branch" != */ ]]
[[ "$target_branch" != *..* ]]
[[ "$expected_sha" =~ ^[0-9a-f]{40}$ ]]

auth="$(printf 'x-access-token:%s' "$PRIVATE_REPOSITORIES_TOKEN" | base64 -w0)"
remote_url='https://github.com/Semogtw/goanime-mobile.git'
remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"

rm -rf private-source
mkdir private-source
git -C private-source init -q
git -C private-source remote add origin "$remote_url"
git -C private-source -c http.extraheader="AUTHORIZATION: basic $auth" fetch -q --depth=2 origin "$expected_sha"
git -C private-source checkout -q --detach FETCH_HEAD
test "$(git -C private-source rev-parse HEAD)" = "$expected_sha"

pushd private-source >/dev/null
flutter pub get --enforce-lockfile >/dev/null
(cd packages/goanime_core && dart pub get >/dev/null)

set +e
flutter test --no-pub test/tools/mangadex_inventory_partition_budget_guard_test.dart > /tmp/mangadex-budget-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'MangaDex inventory fails closed before an unvisited partition' /tmp/mangadex-budget-red.log
echo '[tdd] RED observed: unvisited MangaDex partition can be skipped at exhausted page budget'

python3 - <<'PY'
from pathlib import Path

path = Path('tools/manga/inventory_manga_catalog.dart')
text = path.read_text(encoding='utf-8')
old = """  for (final contentRating in _mangaDexInventoryContentRatings) {
    String? pageToken;
    while (pages < maxPages) {
"""
new = """  for (final contentRating in _mangaDexInventoryContentRatings) {
    if (pages >= maxPages) {
      status = 'partial';
      stopReason = 'max_pages_reached';
      break;
    }
    String? pageToken;
    while (pages < maxPages) {
"""
count = text.count(old)
if count != 1:
    raise SystemExit(f'unexpected MangaDex partition loop shape: {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
PY

dart format tools/manga/inventory_manga_catalog.dart test/tools/mangadex_inventory_partition_budget_guard_test.dart
dart format --output=none --set-exit-if-changed tools/manga/inventory_manga_catalog.dart test/tools/mangadex_inventory_partition_budget_guard_test.dart
git diff --check

flutter test --no-pub --concurrency=1 \
  test/tools/mangadex_inventory_partition_budget_guard_test.dart \
  test/tools/manga_inventory_search_retry_test.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart \
  test/tools/inventory_manga_catalog_selection_test.dart

flutter analyze --no-pub \
  tools/manga/inventory_manga_catalog.dart \
  tools/manga/manga_inventory_search_retry.dart \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/tools/mangadex_inventory_partition_budget_guard_test.dart \
  test/tools/manga_inventory_search_retry_test.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart \
  test/tools/inventory_manga_catalog_selection_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add tools/manga/inventory_manga_catalog.dart test/tools/mangadex_inventory_partition_budget_guard_test.dart
git diff --cached --check
git commit -m 'fix(manga): fail closed across MangaDex partitions'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[mangadex-budget] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/mangadex-budget-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
