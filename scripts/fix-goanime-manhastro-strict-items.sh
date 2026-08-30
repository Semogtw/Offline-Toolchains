#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-manhastro-strict-items-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart > /tmp/manhastro-strict-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'catalog rejects malformed entries instead of dropping them' /tmp/manhastro-strict-red.log
grep -Fq 'catalog rejects fractional numeric manga ids' /tmp/manhastro-strict-red.log
grep -Fq 'chapters reject malformed entries instead of returning a partial list' /tmp/manhastro-strict-red.log
grep -Fq 'pages reject malformed filenames instead of returning a partial manifest' /tmp/manhastro-strict-red.log
echo '[tdd] RED observed: Manhastro silently drops malformed response items'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/manhastro_manga_provider.dart')
text = path.read_text(encoding='utf-8')

old = """    final chapters = <MangaSourceChapter>[];
    for (final raw in rawItems) {
      final item = _map(raw);
      final id = _idText(item?['capitulo_id']);
      final name = _text(item?['capitulo_nome']);
      if (id == null || name == null) continue;
      chapters.add(
"""
new = """    final chapters = <MangaSourceChapter>[];
    for (final raw in rawItems) {
      final item = _map(raw);
      final id = _idText(item?['capitulo_id']);
      final name = _text(item?['capitulo_nome']);
      if (item == null || id == null || name == null) {
        throw const FormatException('Manhastro chapter response has an invalid item.');
      }
      chapters.add(
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro chapter item shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """    final pages = <MangaPageRequest>[];
    for (final raw in rawPages) {
      final file = _text(raw);
      if (file == null) continue;
      final uri = Uri.tryParse('$root/$hash/$file');
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      pages.add(
"""
new = """    final pages = <MangaPageRequest>[];
    for (final raw in rawPages) {
      final file = _text(raw);
      if (file == null) {
        throw const FormatException('Manhastro page response has an invalid filename.');
      }
      final uri = Uri.tryParse('$root/$hash/$file');
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('Manhastro page response has an invalid URL.');
      }
      pages.add(
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro page item shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """    final catalog = rawItems
        .map(_map)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    _catalogCache = catalog;
"""
new = """    final catalog = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      final item = _map(raw);
      if (item == null || _mangaId(item) == null || _displayTitle(item).isEmpty) {
        throw const FormatException('Manhastro catalog response has an invalid item.');
      }
      catalog.add(item);
    }
    _catalogCache = List<Map<String, dynamic>>.unmodifiable(catalog);
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro catalog item shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """String? _idText(Object? value) {
  if (value is num) return '${value.toInt()}';
  return _text(value);
}
"""
new = """String? _idText(Object? value) {
  if (value is num) {
    if (!value.isFinite) return null;
    final integer = value.toInt();
    return value == integer ? '$integer' : null;
  }
  return _text(value);
}
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro id helper shape: {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')

# Add the new test to every materializer list that already contains the main
# Manhastro provider test, preserving the local indentation and continuation.
materializer = Path('tools/manga/materialize_global_manga_availability_ci.sh')
lines = materializer.read_text(encoding='utf-8').splitlines()
needle = 'test/services/manga/providers/manhastro_manga_provider_response_test.dart'
matches = [i for i, line in enumerate(lines) if needle in line]
if len(matches) != 4:
    raise SystemExit(f'unexpected Manhastro materializer response-test count: {len(matches)}')
for index in reversed(matches):
    line = lines[index]
    indent = line[: len(line) - len(line.lstrip())]
    suffix = ' \\' if line.rstrip().endswith('\\') else ''
    lines.insert(
        index + 1,
        f'{indent}test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart{suffix}',
    )
materializer.write_text('\n'.join(lines) + '\n', encoding='utf-8')

gate = Path('test/tools/materialize_global_manga_availability_gate_test.dart')
lines = gate.read_text(encoding='utf-8').splitlines()
needle = 'test/services/manga/providers/manhastro_manga_provider_response_test.dart'
matches = [i for i, line in enumerate(lines) if needle in line]
if len(matches) != 1:
    raise SystemExit(f'unexpected Manhastro gate response-test count: {len(matches)}')
index = matches[0]
indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
lines.insert(
    index + 1,
    f"{indent}'test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart',",
)
gate.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
git diff --check
flutter test --no-pub \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart \
  tools/manga/materialize_global_manga_availability_ci.sh
git diff --cached --check
git commit -m 'fix(manga): reject malformed Manhastro response items'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[manhastro-strict-items] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/manhastro-strict-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
