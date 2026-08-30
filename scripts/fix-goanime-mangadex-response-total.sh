#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-mangadex-response-total-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/mangadex_manga_provider_test.dart > /tmp/mangadex-total-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'search rejects missing upstream total' /tmp/mangadex-total-red.log
grep -Fq 'chapters reject missing upstream total' /tmp/mangadex-total-red.log
echo '[tdd] RED observed: MangaDex accepts missing pagination totals'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/mangadex_manga_provider.dart')
text = path.read_text(encoding='utf-8')
old = """    final total =
        _nonNegativeInt(payload['total']) ?? responseOffset + items.length;
"""
new = """    final total = _responseTotal(
      payload['total'],
      responseOffset: responseOffset,
      itemCount: rawItems.length,
      responseName: 'MangaDex search',
    );
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected MangaDex search total shape: {text.count(old)}')
text = text.replace(old, new, 1)
old = """      final total =
          _nonNegativeInt(payload['total']) ?? responseOffset + rawItems.length;
"""
new = """      final total = _responseTotal(
        payload['total'],
        responseOffset: responseOffset,
        itemCount: rawItems.length,
        responseName: 'MangaDex chapter',
      );
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected MangaDex chapter total shape: {text.count(old)}')
text = text.replace(old, new, 1)
anchor = """int _pageLimit(
  Object? value, {
  required int fallback,
  required String responseName,
}) {
"""
helper = """int _responseTotal(
  Object? value, {
  required int responseOffset,
  required int itemCount,
  required String responseName,
}) {
  final total = _nonNegativeInt(value);
  if (total == null || total < responseOffset + itemCount) {
    throw FormatException('$responseName response has invalid total.');
  }
  return total;
}

"""
if text.count(anchor) != 1:
    raise SystemExit(f'unexpected MangaDex helper anchor: {text.count(anchor)}')
text = text.replace(anchor, helper + anchor, 1)
path.write_text(text, encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart
git diff --check
flutter test --no-pub test/services/manga/providers/mangadex_manga_provider_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart
git diff --cached --check
git commit -m 'fix(manga): require MangaDex pagination totals'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[mangadex-response-total] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/mangadex-total-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
