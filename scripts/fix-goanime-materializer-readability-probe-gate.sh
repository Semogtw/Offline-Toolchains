#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-materializer-readability-probe-gate-fix/*.request' | head -n 1)"
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
flutter test --no-pub test/tools/materialize_global_manga_availability_gate_test.dart > /tmp/materializer-readability-probe-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'materializer gate covers branch provider and readability contracts' /tmp/materializer-readability-probe-red.log
echo '[tdd] RED observed: materializer omits readability probe boundary tests'

python3 - <<'PY'
from pathlib import Path

path = Path('tools/manga/materialize_global_manga_availability_ci.sh')
text = path.read_text(encoding='utf-8')


def extend_block(source, start, end, anchor, additions):
    start_index = source.find(start)
    if start_index < 0:
        raise SystemExit(f'start marker not found: {start!r}')
    content_start = start_index + len(start)
    end_index = source.find(end, content_start)
    if end_index < 0:
        raise SystemExit(f'end marker not found: {end!r}')
    block = source[content_start:end_index]
    if block.count(anchor) != 1:
        raise SystemExit(f'anchor count in block is {block.count(anchor)}: {anchor!r}')
    for addition in additions:
        if addition.strip() in block:
            raise SystemExit(f'addition already present in block: {addition!r}')
    block = block.replace(anchor, anchor + ''.join(additions), 1)
    return source[:content_start] + block + source[end_index:]


source_plain = ['  lib/services/manga/manga_remote_content_probe.dart\n']
test_plain = [
    '  test/services/manga/manga_remote_content_probe_test.dart\n',
    '  test/services/manga/manga_remote_content_probe_policy_test.dart\n',
]
source_shell = [line.rstrip('\n') + ' \\\n' for line in source_plain]
test_shell = [line.rstrip('\n') + ' \\\n' for line in test_plain]

text = extend_block(
    text,
    'files=(\n',
    ')\n\ndart format',
    '  lib/services/manga/manga_http_client.dart\n',
    source_plain,
)
text = extend_block(
    text,
    'files=(\n',
    ')\n\ndart format',
    '  test/services/manga/manga_http_client_persistence_test.dart\n',
    test_plain,
)
text = extend_block(
    text,
    'flutter analyze --no-pub \\\n',
    '\n\nflutter test --no-pub --concurrency=1',
    '  lib/services/manga/manga_http_client.dart \\\n',
    source_shell,
)
text = extend_block(
    text,
    'flutter analyze --no-pub \\\n',
    '\n\nflutter test --no-pub --concurrency=1',
    '  test/services/manga/manga_http_client_persistence_test.dart \\\n',
    test_shell,
)
text = extend_block(
    text,
    'flutter test --no-pub --concurrency=1 \\\n',
    '\n\nrm -rf "$OUT_DIR"',
    '  test/services/manga/manga_http_client_persistence_test.dart \\\n',
    test_shell,
)
text = extend_block(
    text,
    'git add -- \\\n',
    '\n\nif git diff --cached --quiet',
    '  lib/services/manga/manga_http_client.dart \\\n',
    source_shell,
)
text = extend_block(
    text,
    'git add -- \\\n',
    '\n\nif git diff --cached --quiet',
    '  test/services/manga/manga_http_client_persistence_test.dart \\\n',
    test_shell,
)
path.write_text(text, encoding='utf-8')
PY

dart format test/tools/materialize_global_manga_availability_gate_test.dart
dart format --output=none --set-exit-if-changed test/tools/materialize_global_manga_availability_gate_test.dart
bash -n tools/manga/materialize_global_manga_availability_ci.sh
git diff --check
flutter test --no-pub --concurrency=1 \
  test/tools/materialize_global_manga_availability_gate_test.dart \
  test/services/manga/manga_remote_content_probe_test.dart \
  test/services/manga/manga_remote_content_probe_policy_test.dart
flutter analyze --no-pub \
  lib/services/manga/manga_remote_content_probe.dart \
  test/services/manga/manga_remote_content_probe_test.dart \
  test/services/manga/manga_remote_content_probe_policy_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add \
  tools/manga/materialize_global_manga_availability_ci.sh \
  test/tools/materialize_global_manga_availability_gate_test.dart
git diff --cached --check
git commit -m 'ci(manga): cover readability probe in materializer gate'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[materializer-readability-probe-gate] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/materializer-readability-probe-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
