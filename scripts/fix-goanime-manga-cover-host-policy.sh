#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-manga-cover-host-policy-fix/*.request' | head -n 1)"
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

rm -rf private-source /tmp/manga-cover-host-policy-red.log
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
flutter test --no-pub --concurrency=1 \
  test/services/manga/providers/manga_provider_cover_host_policy_test.dart \
  > /tmp/manga-cover-host-policy-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'Taimu cover URLs stay inside provider content policy' /tmp/manga-cover-host-policy-red.log
grep -Fq 'Manhastro cover URLs stay inside provider content policy' /tmp/manga-cover-host-policy-red.log
echo '[tdd] RED observed: provider cover URLs can escape content-host policy'

python3 - <<'PY'
from pathlib import Path

# Taimu: reuse the provider policy that already protects reader content.
taimu = Path('lib/services/manga/providers/taimu_manga_provider.dart')
text = taimu.read_text(encoding='utf-8')
if text.count("coverUrl: _httpsText(item['cover']),") != 1:
    raise SystemExit('unexpected Taimu search cover shape')
text = text.replace(
    "coverUrl: _httpsText(item['cover']),",
    "coverUrl: _coverUrl(item['cover']),",
    1,
)
if text.count("coverUrl: _httpsText(data['cover']) ?? occurrence.coverUrl,") != 1:
    raise SystemExit('unexpected Taimu details cover shape')
text = text.replace(
    "coverUrl: _httpsText(data['cover']) ?? occurrence.coverUrl,",
    "coverUrl: _coverUrl(data['cover']) ?? _coverUrl(occurrence.coverUrl),",
    1,
)
marker = """  Future<Map<String, dynamic>> _series(String mangaId) async {
"""
helper = """  String? _coverUrl(Object? value) {
    final uri = _httpsUri(value);
    if (uri == null || !_httpClient.policy.allowsContentHost(uri.host)) {
      return null;
    }
    return uri.toString();
  }

""" + marker
if text.count(marker) != 1:
    raise SystemExit('unexpected Taimu series helper marker')
text = text.replace(marker, helper, 1)
old = "String? _httpsText(Object? value) => _httpsUri(value)?.toString();\n\n"
if text.count(old) != 1:
    raise SystemExit('unexpected Taimu _httpsText helper shape')
text = text.replace(old, '', 1)
taimu.write_text(text, encoding='utf-8')

# Manhastro: normalized cover references must also stay on policy-approved hosts.
manhastro = Path('lib/services/manga/providers/manhastro_manga_provider.dart')
text = manhastro.read_text(encoding='utf-8')
if text.count("coverUrl: _normalizeUrl(item['imagem']),") != 1:
    raise SystemExit('unexpected Manhastro search cover shape')
text = text.replace(
    "coverUrl: _normalizeUrl(item['imagem']),",
    "coverUrl: _coverUrl(item['imagem']),",
    1,
)
if text.count("coverUrl: _normalizeUrl(item['imagem']) ?? occurrence.coverUrl,") != 1:
    raise SystemExit('unexpected Manhastro details cover shape')
text = text.replace(
    "coverUrl: _normalizeUrl(item['imagem']) ?? occurrence.coverUrl,",
    "coverUrl: _coverUrl(item['imagem']) ?? _coverUrl(occurrence.coverUrl),",
    1,
)
marker = """  Future<Map<String, dynamic>> _catalogItem(String mangaId) async {
"""
helper = """  String? _coverUrl(Object? value) {
    final normalized = _normalizeUrl(value);
    if (normalized == null) return null;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !_httpClient.policy.allowsContentHost(uri.host)) {
      return null;
    }
    return normalized;
  }

""" + marker
if text.count(marker) != 1:
    raise SystemExit('unexpected Manhastro catalog-item helper marker')
text = text.replace(marker, helper, 1)
manhastro.write_text(text, encoding='utf-8')

# Keep the new boundary test in every permanent materializer phase.
materializer = Path('tools/manga/materialize_global_manga_availability_ci.sh')
lines = materializer.read_text(encoding='utf-8').splitlines()
needle = 'test/services/manga/providers/manhastro_manga_provider_pagination_test.dart'
new_path = 'test/services/manga/providers/manga_provider_cover_host_policy_test.dart'
if any(new_path in line for line in lines):
    raise SystemExit('cover-host policy test is already present in materializer')
matches = [i for i, line in enumerate(lines) if needle in line]
if len(matches) != 4:
    raise SystemExit(f'unexpected Manhastro pagination materializer count: {len(matches)}')
for index in reversed(matches):
    line = lines[index]
    indent = line[: len(line) - len(line.lstrip())]
    suffix = ' \\' if line.rstrip().endswith('\\') else ''
    lines.insert(index + 1, f'{indent}{new_path}{suffix}')
materializer.write_text('\n'.join(lines) + '\n', encoding='utf-8')

gate = Path('test/tools/materialize_global_manga_availability_gate_test.dart')
gate_text = gate.read_text(encoding='utf-8')
needle = "      'test/services/manga/providers/manhastro_manga_provider_pagination_test.dart',\n"
insert = needle + "      'test/services/manga/providers/manga_provider_cover_host_policy_test.dart',\n"
if gate_text.count(needle) != 1:
    raise SystemExit(f'unexpected Manhastro pagination gate shape: {gate_text.count(needle)}')
if 'manga_provider_cover_host_policy_test.dart' in gate_text:
    raise SystemExit('cover-host policy test is already present in structural gate')
gate.write_text(gate_text.replace(needle, insert, 1), encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/taimu_manga_provider.dart \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manga_provider_cover_host_policy_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/taimu_manga_provider.dart \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manga_provider_cover_host_policy_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
git diff --check

flutter test --no-pub --concurrency=1 \
  test/services/manga/providers/manga_provider_cover_host_policy_test.dart \
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
  test/services/manga/providers/manga_provider_cover_host_policy_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add -- \
  lib/services/manga/providers/taimu_manga_provider.dart \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manga_provider_cover_host_policy_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart \
  tools/manga/materialize_global_manga_availability_ci.sh
git diff --cached --check
git commit -m 'fix(manga): enforce cover content-host policy'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[manga-cover-host-policy] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/manga-cover-host-policy-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
