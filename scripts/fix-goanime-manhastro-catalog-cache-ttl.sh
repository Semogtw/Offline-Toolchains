#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-manhastro-catalog-cache-ttl-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/manhastro_manga_provider_cache_test.dart > /tmp/manhastro-cache-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'catalog cache refreshes after thirty minutes' /tmp/manhastro-cache-red.log
echo '[tdd] RED observed: Manhastro catalog cache never expires'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/manhastro_manga_provider.dart')
text = path.read_text(encoding='utf-8')
old = """final class ManhastroMangaProvider implements MangaSourceProvider {
  ManhastroMangaProvider({required MangaHttpClient httpClient})
    : _httpClient = httpClient;

  static const String sourceIdValue = 'ptbr.manhastro';
  static const int _pageSize = 30;
"""
new = """final class ManhastroMangaProvider implements MangaSourceProvider {
  ManhastroMangaProvider({
    required MangaHttpClient httpClient,
    DateTime Function()? now,
  }) : _httpClient = httpClient,
       _now = now ?? DateTime.now;

  static const String sourceIdValue = 'ptbr.manhastro';
  static const int _pageSize = 30;
  static const Duration _catalogCacheTtl = Duration(minutes: 30);
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro constructor shape: {text.count(old)}')
text = text.replace(old, new, 1)
old = """  final MangaHttpClient _httpClient;
  List<Map<String, dynamic>>? _catalogCache;
"""
new = """  final MangaHttpClient _httpClient;
  final DateTime Function() _now;
  List<Map<String, dynamic>>? _catalogCache;
  DateTime? _catalogCachedAt;
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro cache field shape: {text.count(old)}')
text = text.replace(old, new, 1)
old = """  Future<List<Map<String, dynamic>>> _catalog() async {
    final cached = _catalogCache;
    if (cached != null) return cached;
    final payload = await _jsonMap(_apiBase.resolve('dados'));
"""
new = """  Future<List<Map<String, dynamic>>> _catalog() async {
    final cached = _catalogCache;
    final cachedAt = _catalogCachedAt;
    final now = _now();
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _catalogCacheTtl) {
      return cached;
    }
    final payload = await _jsonMap(_apiBase.resolve('dados'));
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro cache lookup shape: {text.count(old)}')
text = text.replace(old, new, 1)
old = """    _catalogCache = List<Map<String, dynamic>>.unmodifiable(catalog);
    return catalog;
"""
new = """    final frozen = List<Map<String, dynamic>>.unmodifiable(catalog);
    _catalogCache = frozen;
    _catalogCachedAt = _now();
    return frozen;
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro cache store shape: {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')

materializer = Path('tools/manga/materialize_global_manga_availability_ci.sh')
lines = materializer.read_text(encoding='utf-8').splitlines()
needle = 'test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart'
matches = [i for i, line in enumerate(lines) if needle in line]
if len(matches) != 4:
    raise SystemExit(f'unexpected Manhastro strict-test materializer count: {len(matches)}')
for index in reversed(matches):
    line = lines[index]
    indent = line[: len(line) - len(line.lstrip())]
    suffix = ' \\' if line.rstrip().endswith('\\') else ''
    lines.insert(
        index + 1,
        f'{indent}test/services/manga/providers/manhastro_manga_provider_cache_test.dart{suffix}',
    )
materializer.write_text('\n'.join(lines) + '\n', encoding='utf-8')

gate = Path('test/tools/materialize_global_manga_availability_gate_test.dart')
lines = gate.read_text(encoding='utf-8').splitlines()
needle = 'test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart'
matches = [i for i, line in enumerate(lines) if needle in line]
if len(matches) != 1:
    raise SystemExit(f'unexpected Manhastro strict-test gate count: {len(matches)}')
index = matches[0]
indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
lines.insert(
    index + 1,
    f"{indent}'test/services/manga/providers/manhastro_manga_provider_cache_test.dart',",
)
gate.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
git diff --check
flutter test --no-pub \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart \
  tools/manga/materialize_global_manga_availability_ci.sh
git diff --cached --check
git commit -m 'fix(manga): expire Manhastro catalog cache'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[manhastro-catalog-cache-ttl] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/manhastro-cache-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
