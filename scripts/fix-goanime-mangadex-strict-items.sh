#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-mangadex-strict-items-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/mangadex_manga_provider_strict_items_test.dart > /tmp/mangadex-strict-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'search rejects malformed resources instead of returning a partial page' /tmp/mangadex-strict-red.log
grep -Fq 'details reject a mismatched resource identity' /tmp/mangadex-strict-red.log
grep -Fq 'chapters reject malformed resources instead of returning a partial list' /tmp/mangadex-strict-red.log
grep -Fq 'chapters reject an unexpected translation language' /tmp/mangadex-strict-red.log
grep -Fq 'AtHome rejects malformed filenames instead of returning a partial manifest' /tmp/mangadex-strict-red.log
grep -Fq 'pagination rejects fractional integer metadata' /tmp/mangadex-strict-red.log
echo '[tdd] RED observed: MangaDex accepts malformed response resources'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/mangadex_manga_provider.dart')
text = path.read_text(encoding='utf-8')

old = """    final items = <MangaSourceOccurrence>[];
    for (final raw in rawItems) {
      final item = _map(raw);
      final id = _text(item?['id']);
      final attributes = _map(item?['attributes']);
      final title = _localizedText(attributes?['title']);
      if (id == null || title == null) continue;
      items.add(
"""
new = """    final items = <MangaSourceOccurrence>[];
    for (final raw in rawItems) {
      final item = _map(raw);
      final id = _text(item?['id']);
      final attributes = _map(item?['attributes']);
      final title = _localizedText(attributes?['title']);
      if (item == null || id == null || attributes == null || title == null) {
        throw const FormatException('MangaDex search response has an invalid resource.');
      }
      items.add(
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected MangaDex search resource shape: {text.count(old)}')
text = text.replace(old, new, 1)
text = text.replace("coverUrl: _coverUrl(id, item?['relationships']),", "coverUrl: _coverUrl(id, item['relationships']),", 1)

old = """    final data = _map(payload['data']);
    final attributes = _map(data?['attributes']);
    if (data == null || attributes == null) {
      throw const FormatException('MangaDex details response is invalid.');
    }
"""
new = """    final data = _map(payload['data']);
    final attributes = _map(data?['attributes']);
    final responseId = _text(data?['id']);
    if (data == null ||
        attributes == null ||
        responseId != occurrence.mangaId) {
      throw const FormatException('MangaDex details response is invalid.');
    }
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected MangaDex details identity shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """      for (final raw in rawItems) {
        final item = _map(raw);
        final id = _text(item?['id']);
        final attributes = _map(item?['attributes']);
        if (id == null || attributes == null) continue;
        final number = _number(attributes['chapter']);
"""
new = """      for (final raw in rawItems) {
        final item = _map(raw);
        final id = _text(item?['id']);
        final attributes = _map(item?['attributes']);
        if (item == null || id == null || attributes == null) {
          throw const FormatException('MangaDex chapter response has an invalid resource.');
        }
        if (_text(attributes['translatedLanguage'])?.toLowerCase() != 'pt-br') {
          throw const FormatException(
            'MangaDex chapter response has an unexpected translation language.',
          );
        }
        final number = _number(attributes['chapter']);
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected MangaDex chapter resource shape: {text.count(old)}')
text = text.replace(old, new, 1)
text = text.replace("_relationshipNames(item?['relationships'], 'scanlation_group')", "_relationshipNames(item['relationships'], 'scanlation_group')", 1)

old = """    final pages = <MangaPageRequest>[];
    for (final raw in rawPages) {
      final file = _text(raw);
      if (file == null) continue;
      final uri = Uri.tryParse('$root/data/$hash/$file');
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      pages.add(
"""
new = """    final pages = <MangaPageRequest>[];
    for (final raw in rawPages) {
      final file = _text(raw);
      if (file == null) {
        throw const FormatException('MangaDex AtHome response has an invalid filename.');
      }
      final uri = Uri.tryParse('$root/data/$hash/$file');
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('MangaDex AtHome response has an invalid page URL.');
      }
      pages.add(
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected MangaDex AtHome page shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """int? _nonNegativeInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  return parsed != null && parsed >= 0 ? parsed : null;
}
"""
new = """int? _nonNegativeInt(Object? value) {
  int? parsed;
  if (value is num) {
    if (!value.isFinite) return null;
    final integer = value.toInt();
    if (value != integer) return null;
    parsed = integer;
  } else {
    parsed = int.tryParse('$value');
  }
  return parsed != null && parsed >= 0 ? parsed : null;
}
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected MangaDex integer parser shape: {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')

materializer = Path('tools/manga/materialize_global_manga_availability_ci.sh')
lines = materializer.read_text(encoding='utf-8').splitlines()
needle = 'test/services/manga/providers/mangadex_manga_provider_test.dart'
matches = [i for i, line in enumerate(lines) if needle in line]
if len(matches) != 4:
    raise SystemExit(f'unexpected MangaDex materializer test count: {len(matches)}')
for index in reversed(matches):
    line = lines[index]
    indent = line[: len(line) - len(line.lstrip())]
    suffix = ' \\' if line.rstrip().endswith('\\') else ''
    lines.insert(
        index + 1,
        f'{indent}test/services/manga/providers/mangadex_manga_provider_strict_items_test.dart{suffix}',
    )
materializer.write_text('\n'.join(lines) + '\n', encoding='utf-8')

gate = Path('test/tools/materialize_global_manga_availability_gate_test.dart')
lines = gate.read_text(encoding='utf-8').splitlines()

def insert_before_unique(anchor, new_line):
    if any(new_line.strip() == line.strip() for line in lines):
        return
    matches = [i for i, line in enumerate(lines) if anchor in line]
    if len(matches) != 1:
        raise SystemExit(f'unexpected gate anchor {anchor}: {len(matches)}')
    index = matches[0]
    indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
    lines.insert(index, indent + new_line.strip())

insert_before_unique(
    'lib/services/manga/providers/taimu_manga_provider.dart',
    "'lib/services/manga/providers/mangadex_manga_provider.dart',",
)
insert_before_unique(
    'test/services/manga/providers/taimu_manga_provider_test.dart',
    "'test/services/manga/providers/mangadex_manga_provider_test.dart',",
)
insert_before_unique(
    'test/services/manga/providers/taimu_manga_provider_test.dart',
    "'test/services/manga/providers/mangadex_manga_provider_strict_items_test.dart',",
)
gate.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart \
  test/services/manga/providers/mangadex_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart \
  test/services/manga/providers/mangadex_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
git diff --check
flutter test --no-pub \
  test/services/manga/providers/mangadex_manga_provider_test.dart \
  test/services/manga/providers/mangadex_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart \
  test/services/manga/providers/mangadex_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/services/manga/providers/mangadex_manga_provider.dart \
  test/services/manga/providers/mangadex_manga_provider_test.dart \
  test/services/manga/providers/mangadex_manga_provider_strict_items_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart \
  tools/manga/materialize_global_manga_availability_ci.sh
git diff --cached --check
git commit -m 'fix(manga): reject malformed MangaDex response resources'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[mangadex-strict-items] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/mangadex-strict-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
