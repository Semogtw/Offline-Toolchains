#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-taimu-pagination-metadata-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/taimu_manga_provider_pagination_test.dart > /tmp/taimu-pagination-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'search rejects missing pagination continuation metadata' /tmp/taimu-pagination-red.log
grep -Fq 'search rejects conflicting continuation metadata' /tmp/taimu-pagination-red.log
grep -Fq 'chapters reject missing pagination continuation metadata' /tmp/taimu-pagination-red.log
grep -Fq 'chapters reject conflicting continuation metadata' /tmp/taimu-pagination-red.log
echo '[tdd] RED observed: Taimu accepts ambiguous pagination metadata'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/taimu_manga_provider.dart')
text = path.read_text(encoding='utf-8')
old = """    final currentPage = _responsePage(payload['page'], requestedPage: page);
    final perPage = _positiveInt(payload['per_page']) ?? _pageSize;
    final total = _nonNegativeInt(payload['total']);
    final hasMore =
        payload['has_more'] == true ||
        payload['hasMore'] == true ||
        (total != null && currentPage * perPage < total);
"""
new = """    final currentPage = _responsePage(payload['page'], requestedPage: page);
    final perPage = _responsePerPage(
      payload['per_page'],
      fallback: _pageSize,
      responseName: 'Taimu search',
    );
    final hasMore = _paginationHasMore(
      payload,
      currentPage: currentPage,
      perPage: perPage,
      itemCount: rawItems.length,
      responseName: 'Taimu search',
    );
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu search pagination shape: {text.count(old)}')
text = text.replace(old, new, 1)
old = """      _responsePage(payload['page'], requestedPage: page);
      final hasMore = payload['has_more'] == true || payload['hasMore'] == true;
      if (!hasMore || rawItems.isEmpty) {
"""
new = """      final currentPage = _responsePage(payload['page'], requestedPage: page);
      final perPage = _responsePerPage(
        payload['per_page'],
        fallback: _chapterPageSize,
        responseName: 'Taimu chapter',
      );
      final hasMore = _paginationHasMore(
        payload,
        currentPage: currentPage,
        perPage: perPage,
        itemCount: rawItems.length,
        responseName: 'Taimu chapter',
      );
      if (!hasMore || rawItems.isEmpty) {
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu chapter pagination shape: {text.count(old)}')
text = text.replace(old, new, 1)
anchor = """int _responsePage(Object? value, {required int requestedPage}) {
  final responsePage = _positiveInt(value);
  if (responsePage == null || responsePage != requestedPage) {
    throw FormatException(
      'Taimu response page does not match requested page $requestedPage.',
    );
  }
  return responsePage;
}

"""
helpers = """int _responsePerPage(
  Object? value, {
  required int fallback,
  required String responseName,
}) {
  if (value == null) return fallback;
  final perPage = _positiveInt(value);
  if (perPage == null) {
    throw FormatException('$responseName response has invalid per_page.');
  }
  return perPage;
}

bool _paginationHasMore(
  Map<String, dynamic> payload, {
  required int currentPage,
  required int perPage,
  required int itemCount,
  required String responseName,
}) {
  bool? explicit;
  for (final key in const <String>['has_more', 'hasMore']) {
    if (!payload.containsKey(key)) continue;
    final raw = payload[key];
    if (raw is! bool) {
      throw FormatException('$responseName response has invalid $key.');
    }
    if (explicit != null && explicit != raw) {
      throw FormatException(
        '$responseName response has conflicting continuation flags.',
      );
    }
    explicit = raw;
  }

  bool? fromTotal;
  if (payload.containsKey('total')) {
    final total = _nonNegativeInt(payload['total']);
    final minimumTotal = (currentPage - 1) * perPage + itemCount;
    if (total == null || total < minimumTotal) {
      throw FormatException('$responseName response has invalid total.');
    }
    fromTotal = currentPage * perPage < total;
  }

  if (explicit != null && fromTotal != null && explicit != fromTotal) {
    throw FormatException(
      '$responseName response has conflicting pagination metadata.',
    );
  }
  final hasMore = explicit ?? fromTotal;
  if (hasMore == null) {
    throw FormatException(
      '$responseName response has no pagination continuation metadata.',
    );
  }
  return hasMore;
}

"""
if text.count(anchor) != 1:
    raise SystemExit(f'unexpected Taimu pagination helper anchor: {text.count(anchor)}')
text = text.replace(anchor, anchor + helpers, 1)
path.write_text(text, encoding='utf-8')

materializer = Path('tools/manga/materialize_global_manga_availability_ci.sh')
text = materializer.read_text(encoding='utf-8')
plain = '  test/services/manga/providers/taimu_manga_provider_test.dart\n'
if text.count(plain) != 1:
    raise SystemExit(f'unexpected Taimu plain materializer entry count: {text.count(plain)}')
text = text.replace(
    plain,
    plain + '  test/services/manga/providers/taimu_manga_provider_pagination_test.dart\n',
    1,
)
continued = '  test/services/manga/providers/taimu_manga_provider_test.dart \\\n'
if text.count(continued) != 3:
    raise SystemExit(f'unexpected Taimu continued materializer entry count: {text.count(continued)}')
text = text.replace(
    continued,
    continued + '  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \\\n',
)
materializer.write_text(text, encoding='utf-8')

gate = Path('test/tools/materialize_global_manga_availability_gate_test.dart')
text = gate.read_text(encoding='utf-8')
entry = "        'test/services/manga/providers/taimu_manga_provider_test.dart',\n"
if text.count(entry) != 1:
    raise SystemExit(f'unexpected Taimu gate entry count: {text.count(entry)}')
text = text.replace(
    entry,
    entry + "        'test/services/manga/providers/taimu_manga_provider_pagination_test.dart',\n",
    1,
)
gate.write_text(text, encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
git diff --check
flutter test --no-pub \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart \
  tools/manga/materialize_global_manga_availability_ci.sh
git diff --cached --check
git commit -m 'fix(manga): fail closed on ambiguous Taimu pagination'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[taimu-pagination-metadata] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/taimu-pagination-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
