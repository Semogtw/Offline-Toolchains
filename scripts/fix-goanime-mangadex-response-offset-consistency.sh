#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"

request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-mangadex-response-offset-consistency-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/mangadex_manga_provider_test.dart > /tmp/mangadex-offset-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'rejects mismatched search response offset' /tmp/mangadex-offset-red.log
grep -Fq 'rejects mismatched chapter response offset' /tmp/mangadex-offset-red.log
echo '[tdd] RED observed: MangaDex trusts mismatched response offsets'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/mangadex_manga_provider.dart')
text = path.read_text(encoding='utf-8')
old_search = """    final responseOffset = _nonNegativeInt(payload['offset']) ?? offset;
    final total =
        _nonNegativeInt(payload['total']) ?? responseOffset + items.length;
"""
new_search = """    final responseOffset = _responseOffset(
      payload['offset'],
      requestedOffset: offset,
      responseName: 'MangaDex search',
    );
    final total =
        _nonNegativeInt(payload['total']) ?? responseOffset + items.length;
"""
if text.count(old_search) != 1:
    raise SystemExit(f'unexpected MangaDex search offset shape: {text.count(old_search)}')
text = text.replace(old_search, new_search, 1)
old_chapter = """      final responseOffset = _nonNegativeInt(payload['offset']) ?? offset;
      final total =
          _nonNegativeInt(payload['total']) ?? responseOffset + rawItems.length;
"""
new_chapter = """      final responseOffset = _responseOffset(
        payload['offset'],
        requestedOffset: offset,
        responseName: 'MangaDex chapter',
      );
      final total =
          _nonNegativeInt(payload['total']) ?? responseOffset + rawItems.length;
"""
if text.count(old_chapter) != 1:
    raise SystemExit(f'unexpected MangaDex chapter offset shape: {text.count(old_chapter)}')
text = text.replace(old_chapter, new_chapter, 1)
anchor = """int _pageOffset(String? pageToken) {
  if (pageToken == null) return 0;
  final offset = _nonNegativeInt(pageToken);
  if (offset == null) {
    throw ArgumentError.value(
      pageToken,
      'pageToken',
      'Must be a non-negative integer offset.',
    );
  }
  return offset;
}

"""
helper = """int _responseOffset(
  Object? value, {
  required int requestedOffset,
  required String responseName,
}) {
  final responseOffset = _nonNegativeInt(value);
  if (responseOffset == null) return requestedOffset;
  if (responseOffset != requestedOffset) {
    throw FormatException(
      '$responseName response offset does not match requested offset '
      '$requestedOffset.',
    );
  }
  return responseOffset;
}

"""
if text.count(anchor) != 1:
    raise SystemExit(f'unexpected MangaDex page-offset helper shape: {text.count(anchor)}')
text = text.replace(anchor, anchor + helper, 1)
path.write_text(text, encoding='utf-8')
PY

dart format lib/services/manga/providers/mangadex_manga_provider.dart test/services/manga/providers/mangadex_manga_provider_test.dart
dart format --output=none --set-exit-if-changed lib/services/manga/providers/mangadex_manga_provider.dart test/services/manga/providers/mangadex_manga_provider_test.dart
git diff --check

flutter test --no-pub test/services/manga/providers/mangadex_manga_provider_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add lib/services/manga/providers/mangadex_manga_provider.dart test/services/manga/providers/mangadex_manga_provider_test.dart
git diff --cached --check
git commit -m 'fix(manga): validate MangaDex response offsets'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[mangadex-offset] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/mangadex-offset-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
