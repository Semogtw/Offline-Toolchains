#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-manhastro-response-success-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/services/manga/providers/manhastro_manga_provider_response_test.dart > /tmp/manhastro-success-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'catalog rejects an explicit upstream failure response' /tmp/manhastro-success-red.log
grep -Fq 'catalog rejects a response missing the success contract' /tmp/manhastro-success-red.log
grep -Fq 'chapter list rejects an explicit upstream failure response' /tmp/manhastro-success-red.log
grep -Fq 'page manifest rejects an explicit upstream failure response' /tmp/manhastro-success-red.log
echo '[tdd] RED observed: Manhastro accepts failed API envelopes'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/manhastro_manga_provider.dart')
text = path.read_text(encoding='utf-8')
old = """    if (decoded is! Map) {
      throw const FormatException('Manhastro response is not a JSON object.');
    }
    return Map<String, dynamic>.from(decoded);
"""
new = """    if (decoded is! Map) {
      throw const FormatException('Manhastro response is not a JSON object.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    if (payload['success'] != true) {
      throw const FormatException('Manhastro API response was not successful.');
    }
    return payload;
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro JSON boundary shape: {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')

materializer = Path('tools/manga/materialize_global_manga_availability_ci.sh')
text = materializer.read_text(encoding='utf-8')
plain = '  test/services/manga/providers/manhastro_manga_provider_test.dart\n'
if text.count(plain) != 1:
    raise SystemExit(f'unexpected Manhastro plain materializer entry count: {text.count(plain)}')
text = text.replace(
    plain,
    plain + '  test/services/manga/providers/manhastro_manga_provider_response_test.dart\n',
    1,
)
continued = '  test/services/manga/providers/manhastro_manga_provider_test.dart \\\n'
if text.count(continued) != 3:
    raise SystemExit(f'unexpected Manhastro continued materializer entry count: {text.count(continued)}')
text = text.replace(
    continued,
    continued + '  test/services/manga/providers/manhastro_manga_provider_response_test.dart \\\n',
)
materializer.write_text(text, encoding='utf-8')

gate = Path('test/tools/materialize_global_manga_availability_gate_test.dart')
text = gate.read_text(encoding='utf-8')
lines = text.splitlines()
matches = [
    index
    for index, line in enumerate(lines)
    if "test/services/manga/providers/manhastro_manga_provider_test.dart" in line
]
if len(matches) != 1:
    raise SystemExit(f'unexpected Manhastro gate entry count: {len(matches)}')
index = matches[0]
indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
lines.insert(
    index + 1,
    f"{indent}'test/services/manga/providers/manhastro_manga_provider_response_test.dart',",
)
gate.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
git diff --check
flutter test --no-pub \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart \
  tools/manga/materialize_global_manga_availability_ci.sh
git diff --cached --check
git commit -m 'fix(manga): reject failed Manhastro API responses'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[manhastro-response-success] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/manhastro-success-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
