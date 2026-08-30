#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"

request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-taimu-response-page-consistency-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/taimu_manga_provider_test.dart > /tmp/taimu-page-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'rejects mismatched search response page' /tmp/taimu-page-red.log
grep -Fq 'rejects mismatched chapter response page' /tmp/taimu-page-red.log
echo '[tdd] RED observed: Taimu trusts mismatched upstream page numbers'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/taimu_manga_provider.dart')
text = path.read_text(encoding='utf-8')

old_search = """    final currentPage = _positiveInt(payload['page']) ?? page;
    final perPage = _positiveInt(payload['per_page']) ?? _pageSize;
"""
new_search = """    final currentPage = _responsePage(payload['page'], requestedPage: page);
    final perPage = _positiveInt(payload['per_page']) ?? _pageSize;
"""
if text.count(old_search) != 1:
    raise SystemExit(f'unexpected Taimu search page shape: {text.count(old_search)}')
text = text.replace(old_search, new_search, 1)

old_chapters = """      final hasMore = payload['has_more'] == true || payload['hasMore'] == true;
      if (!hasMore || rawItems.isEmpty) break;
      page = (_positiveInt(payload['page']) ?? page) + 1;
"""
new_chapters = """      _responsePage(payload['page'], requestedPage: page);
      final hasMore = payload['has_more'] == true || payload['hasMore'] == true;
      if (!hasMore || rawItems.isEmpty) break;
      page += 1;
"""
if text.count(old_chapters) != 1:
    raise SystemExit(f'unexpected Taimu chapter page shape: {text.count(old_chapters)}')
text = text.replace(old_chapters, new_chapters, 1)

anchor = """int _searchPage(String? pageToken) {
  if (pageToken == null) return 1;
  final page = _positiveInt(pageToken);
  if (page == null) {
    throw ArgumentError.value(
      pageToken,
      'pageToken',
      'Must be a positive integer.',
    );
  }
  return page;
}

"""
helper = """int _responsePage(Object? value, {required int requestedPage}) {
  final responsePage = _positiveInt(value);
  if (responsePage == null || responsePage != requestedPage) {
    throw FormatException(
      'Taimu response page does not match requested page $requestedPage.',
    );
  }
  return responsePage;
}

"""
if text.count(anchor) != 1:
    raise SystemExit(f'unexpected Taimu search helper shape: {text.count(anchor)}')
text = text.replace(anchor, anchor + helper, 1)
path.write_text(text, encoding='utf-8')
PY

dart format lib/services/manga/providers/taimu_manga_provider.dart test/services/manga/providers/taimu_manga_provider_test.dart
dart format --output=none --set-exit-if-changed lib/services/manga/providers/taimu_manga_provider.dart test/services/manga/providers/taimu_manga_provider_test.dart
git diff --check

flutter test --no-pub test/services/manga/providers/taimu_manga_provider_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add lib/services/manga/providers/taimu_manga_provider.dart test/services/manga/providers/taimu_manga_provider_test.dart
git diff --cached --check
git commit -m 'fix(manga): validate Taimu response page identity'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[taimu-page-consistency] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/taimu-page-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
