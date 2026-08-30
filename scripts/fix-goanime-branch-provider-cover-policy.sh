#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-branch-provider-cover-policy-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/taimu_manga_provider_test.dart \
  > /tmp/taimu-cover-policy-red.log 2>&1
taimu_red_status=$?
flutter test --no-pub test/services/manga/providers/manhastro_manga_provider_test.dart \
  > /tmp/manhastro-cover-policy-red.log 2>&1
manhastro_red_status=$?
set -e
test "$taimu_red_status" -ne 0
test "$manhastro_red_status" -ne 0
grep -Fq 'drops cover URLs outside provider content policy' /tmp/taimu-cover-policy-red.log
grep -Fq 'drops cover URLs outside provider content policy' /tmp/manhastro-cover-policy-red.log
echo '[tdd] RED observed: Taimu and Manhastro expose cover URLs outside content policy'

python3 - <<'PY'
from pathlib import Path


taimu = Path('lib/services/manga/providers/taimu_manga_provider.dart')
text = taimu.read_text(encoding='utf-8')
old = "coverUrl: _httpsText(item['cover']),"
new = "coverUrl: _coverText(item['cover']),"
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu search cover shape: {text.count(old)}')
text = text.replace(old, new, 1)
old = "coverUrl: _httpsText(data['cover']) ?? occurrence.coverUrl,"
new = "coverUrl: _coverText(data['cover']) ?? _coverText(occurrence.coverUrl),"
if text.count(old) != 1:
    raise SystemExit(f'unexpected Taimu details cover shape: {text.count(old)}')
text = text.replace(old, new, 1)
anchor = """  Future<Map<String, dynamic>> _series(String mangaId) async {
"""
helper = """  String? _coverText(Object? value) {
    final uri = _httpsUri(value);
    if (uri == null || !_httpClient.policy.allowsContentHost(uri.host)) {
      return null;
    }
    return uri.toString();
  }

"""
if text.count(anchor) != 1:
    raise SystemExit(f'unexpected Taimu cover helper anchor: {text.count(anchor)}')
text = text.replace(anchor, helper + anchor, 1)
obsolete = "String? _httpsText(Object? value) => _httpsUri(value)?.toString();\n\n"
if text.count(obsolete) != 1:
    raise SystemExit(f'unexpected Taimu obsolete helper shape: {text.count(obsolete)}')
text = text.replace(obsolete, '', 1)
taimu.write_text(text, encoding='utf-8')

manhastro = Path('lib/services/manga/providers/manhastro_manga_provider.dart')
text = manhastro.read_text(encoding='utf-8')
old = "coverUrl: _normalizeUrl(item['imagem']),"
new = "coverUrl: _coverUrl(item['imagem']),"
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro search cover shape: {text.count(old)}')
text = text.replace(old, new, 1)
old = "coverUrl: _normalizeUrl(item['imagem']) ?? occurrence.coverUrl,"
new = "coverUrl: _coverUrl(item['imagem']) ?? _coverUrl(occurrence.coverUrl),"
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro details cover shape: {text.count(old)}')
text = text.replace(old, new, 1)
anchor = """  Future<Map<String, dynamic>> _catalogItem(String mangaId) async {
"""
helper = """  String? _coverUrl(Object? value) {
    final normalized = _normalizeUrl(value);
    if (normalized == null) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !_httpClient.policy.allowsContentHost(uri.host)) {
      return null;
    }
    return uri.toString();
  }

"""
if text.count(anchor) != 1:
    raise SystemExit(f'unexpected Manhastro cover helper anchor: {text.count(anchor)}')
text = text.replace(anchor, helper + anchor, 1)
manhastro.write_text(text, encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/taimu_manga_provider.dart \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/taimu_manga_provider.dart \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart
git diff --check

flutter test --no-pub \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/taimu_manga_provider_pagination_test.dart \
  test/services/manga/providers/taimu_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/taimu_manga_provider.dart \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/services/manga/providers/taimu_manga_provider.dart \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/taimu_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart
git diff --cached --check
git commit -m 'fix(manga): constrain branch provider cover hosts'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[branch-provider-cover-policy] published $published_sha"
popd >/dev/null

rm -rf private-source \
  /tmp/taimu-cover-policy-red.log \
  /tmp/manhastro-cover-policy-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
