#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-taimu-strict-items-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/taimu_manga_provider_strict_items_test.dart > /tmp/taimu-strict-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'search rejects malformed items instead of returning a partial page' /tmp/taimu-strict-red.log
grep -Fq 'series details reject missing required identity fields' /tmp/taimu-strict-red.log
grep -Fq 'chapters reject malformed items instead of returning a partial list' /tmp/taimu-strict-red.log
grep -Fq 'pages reject malformed entries instead of returning a partial manifest' /tmp/taimu-strict-red.log
echo '[tdd] RED observed: Taimu silently accepts malformed response items'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/taimu_manga_provider.dart')
text = path.read_text(encoding='utf-8')

old = """    final items = <MangaSourceOccurrence>[];
    for (final raw in rawItems) {
      final item = _map(raw);
      final id = _identifier(item);
      final title = _text(item?['title']);
      if (id == null || title == null || item?['adult'] == true) continue;
      items.add(
"""
new = """    final items = <MangaSourceOccurrence>[];
    for (final raw in rawItems) {
      final item = _map(raw);
      final id = _identifier(item);
      final title = _text(item?['title']);
      if (item == null || id == null || title == null) {
        throw const FormatException('Taimu library response has an invalid item.');
      }
      if (item['adult'] == true) continue;
      items.add(
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu search item shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """      for (final raw in rawItems) {
        final item = _map(raw);
        final id = _identifier(item);
        final number = _number(item?['number'] ?? item?['chapter']);
        if (id == null) continue;
        final title =
"""
new = """      for (final raw in rawItems) {
        final item = _map(raw);
        final id = _identifier(item);
        final number = _number(item?['number'] ?? item?['chapter']);
        if (item == null || id == null) {
          throw const FormatException('Taimu chapter response has an invalid item.');
        }
        final title =
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu chapter item shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """    final sortable = rawPages.whereType<Map<String, dynamic>>().toList()
      ..sort((left, right) {
        final leftNumber = _nonNegativeInt(left['number']) ?? 0;
        final rightNumber = _nonNegativeInt(right['number']) ?? 0;
        return leftNumber.compareTo(rightNumber);
      });
    final pages = <MangaPageRequest>[];
    final seen = <String>{};
    for (final raw in sortable) {
      final uri = _httpsUri(raw['url']);
      if (uri == null || !seen.add(uri.toString())) continue;
"""
new = """    final sortable = <Map<String, dynamic>>[];
    for (final raw in rawPages) {
      final item = _map(raw);
      if (item == null || _httpsUri(item['url']) == null) {
        throw const FormatException('Taimu chapter response has an invalid page.');
      }
      if (item.containsKey('number') && _nonNegativeInt(item['number']) == null) {
        throw const FormatException('Taimu chapter response has an invalid page number.');
      }
      sortable.add(item);
    }
    sortable.sort((left, right) {
      final leftNumber = _nonNegativeInt(left['number']) ?? 0;
      final rightNumber = _nonNegativeInt(right['number']) ?? 0;
      return leftNumber.compareTo(rightNumber);
    });
    final pages = <MangaPageRequest>[];
    final seen = <String>{};
    for (final raw in sortable) {
      final uri = _httpsUri(raw['url'])!;
      if (!seen.add(uri.toString())) continue;
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu page item shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """  Future<Map<String, dynamic>> _series(String mangaId) {
    return _jsonMap(_apiBase.resolve('series/$mangaId'));
  }
"""
new = """  Future<Map<String, dynamic>> _series(String mangaId) async {
    final data = await _jsonMap(_apiBase.resolve('series/$mangaId'));
    final identifier = _text(data['identifier']);
    final title = _text(data['title']);
    if (identifier == null || title == null || identifier != mangaId) {
      throw const FormatException('Taimu series response has invalid identity fields.');
    }
    return data;
  }
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu series boundary shape: {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')

materializer = Path('tools/manga/materialize_global_manga_availability_ci.sh')
lines = materializer.read_text(encoding='utf-8').splitlines()
needle = 'test/services/manga/providers/taimu_manga_provider_pagination_test.dart'
matches = [i for i, line in enumerate(lines) if needle in line]
if len(matches) != 4:
    raise SystemExit(f'unexpected Taimu materializer pagination-test count: {len(matches)}')
for index in reversed(matches):
    line = lines[index]
    indent = line[: len(line) - len(line.lstrip())]
    suffix = ' \\' if line.rstrip().endswith('\\') else ''
    lines.insert(
        index + 1,
        f'{indent}test/services/manga/providers/taimu_manga_provider_strict_items_test.dart{suffix}',
    )
materializer.write_text('\n'.join(lines) + '\n', encoding='utf-8')

gate = Path('test/tools/materialize_global_manga_availability_gate_test.dart')
lines = gate.read_text(encoding='utf-8').splitlines()
needle = 'test/services/manga/providers/taimu_manga_provider_pagination_test.dart'
matches = [i for i, line in enumerate(lines) if needle in line]
if len(matches) != 1:
    raise SystemExit(f'unexpected Taimu gate pagination-test count: {len(matches)}')
index = matches[0]
indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
lines.insert(
    index + 1,
    f"{indent}'test/services/manga/providers/taimu_manga_provider_strict_items_test.dart',",
)
gate.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/services/manga/providers/taimu_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/taimu_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/services/manga/providers/taimu_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
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
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/services/manga/providers/taimu_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart \
  tools/manga/materialize_global_manga_availability_ci.sh
git diff --cached --check
git commit -m 'fix(manga): reject malformed Taimu response items'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[taimu-strict-items] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/taimu-strict-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
