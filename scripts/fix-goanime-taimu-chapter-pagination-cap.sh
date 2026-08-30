#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-taimu-chapter-pagination-cap-fix/*.request' | head -n 1)"
test -n "$request"
read -r project target_branch expected_sha < "$request"
test "$project" = goanime
[[ "$target_branch" =~ ^[A-Za-z0-9._/-]{1,200}$ ]]
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
pushd private-source >/dev/null
flutter pub get --enforce-lockfile >/dev/null
(cd packages/goanime_core && dart pub get >/dev/null)

set +e
flutter test --no-pub test/services/manga/providers/taimu_manga_provider_test.dart > /tmp/taimu-cap-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'rejects chapter pagination that exceeds request cap' /tmp/taimu-cap-red.log
echo '[tdd] RED observed: Taimu silently truncates chapter pagination at request cap'

python3 - <<'PY'
from pathlib import Path
path = Path('lib/services/manga/providers/taimu_manga_provider.dart')
text = path.read_text(encoding='utf-8')
old = """    final result = <MangaSourceChapter>[];
    var page = 1;

    for (var requestCount = 0; requestCount < 100; requestCount++) {
"""
new = """    final result = <MangaSourceChapter>[];
    var page = 1;
    var paginationComplete = false;

    for (var requestCount = 0; requestCount < 100; requestCount++) {
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu chapter loop header: {text.count(old)}')
text = text.replace(old, new, 1)
old = """      final hasMore = payload['has_more'] == true || payload['hasMore'] == true;
      if (!hasMore || rawItems.isEmpty) break;
      page += 1;
    }

    result.sort((left, right) {
"""
new = """      final hasMore = payload['has_more'] == true || payload['hasMore'] == true;
      if (!hasMore || rawItems.isEmpty) {
        paginationComplete = true;
        break;
      }
      page += 1;
    }
    if (!paginationComplete) {
      throw const FormatException(
        'Taimu chapter pagination exceeded the 100-request safety cap.',
      );
    }

    result.sort((left, right) {
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu chapter loop tail: {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
PY

dart format lib/services/manga/providers/taimu_manga_provider.dart test/services/manga/providers/taimu_manga_provider_test.dart
dart format --output=none --set-exit-if-changed lib/services/manga/providers/taimu_manga_provider.dart test/services/manga/providers/taimu_manga_provider_test.dart
git diff --check
flutter test --no-pub test/services/manga/providers/taimu_manga_provider_test.dart
flutter analyze --no-pub lib/services/manga/providers/taimu_manga_provider.dart test/services/manga/providers/taimu_manga_provider_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add lib/services/manga/providers/taimu_manga_provider.dart test/services/manga/providers/taimu_manga_provider_test.dart
git diff --cached --check
git commit -m 'fix(manga): fail closed on Taimu chapter pagination cap'
published_sha="$(git rev-parse HEAD)"
remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[taimu-chapter-cap] published $published_sha"
popd >/dev/null
rm -rf private-source /tmp/taimu-cap-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
