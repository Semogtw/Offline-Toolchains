#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-taimu-empty-page-continuation-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/taimu_manga_provider_pagination_test.dart > /tmp/taimu-empty-page-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'chapters reject empty page that claims more results' /tmp/taimu-empty-page-red.log
echo '[tdd] RED observed: Taimu accepts empty chapter page while continuation claims more results'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/taimu_manga_provider.dart')
text = path.read_text(encoding='utf-8')
old = """      final hasMore = _paginationHasMore(
        payload,
        currentPage: currentPage,
        perPage: perPage,
        itemCount: rawItems.length,
        responseName: 'Taimu chapter',
      );
      if (!hasMore || rawItems.isEmpty) {
        paginationComplete = true;
        break;
      }
      page += 1;
"""
new = """      final hasMore = _paginationHasMore(
        payload,
        currentPage: currentPage,
        perPage: perPage,
        itemCount: rawItems.length,
        responseName: 'Taimu chapter',
      );
      if (rawItems.isEmpty && hasMore) {
        throw const FormatException(
          'Taimu chapter response is empty while pagination claims more results.',
        );
      }
      if (!hasMore) {
        paginationComplete = true;
        break;
      }
      page += 1;
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu chapter completion shape: {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart
git diff --check

flutter test --no-pub \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/services/manga/providers/taimu_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/services/manga/providers/taimu_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart
git diff --cached --check
git commit -m 'fix(manga): reject contradictory empty Taimu chapter pages'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[taimu-empty-page-continuation] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/taimu-empty-page-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
