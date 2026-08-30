#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-manhastro-live-pagination-fix/*.request' | head -n 1)"
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

rm -rf private-source /tmp/manhastro-live-pagination-red.log
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
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart \
  > /tmp/manhastro-live-pagination-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'search sends live page/filter and follows continuation metadata' /tmp/manhastro-live-pagination-red.log
echo '[tdd] RED observed: Manhastro still treats /dados as an unpaginated local catalog'

python3 - <<'PY'
from pathlib import Path
import json

provider = Path('lib/services/manga/providers/manhastro_manga_provider.dart')
text = provider.read_text(encoding='utf-8')
old = "  static const int _pageSize = 30;"
new = "  static const int _pageSize = 100;"
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro page-size shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """  List<Map<String, dynamic>>? _catalogCache;
  DateTime? _catalogCachedAt;
"""
new = """  List<Map<String, dynamic>>? _catalogCache;
  DateTime? _catalogCachedAt;
  final Map<String, _ManhastroSearchCacheEntry> _searchCache =
      <String, _ManhastroSearchCacheEntry>{};
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro cache-field shape: {text.count(old)}')
text = text.replace(old, new, 1)

start_marker = "  @override\n  Future<MangaSearchPage> search(MangaSearchRequest request) async {\n"
end_marker = "\n  @override\n  Future<MangaSourceDetails> details(MangaSourceOccurrence occurrence) async {\n"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0 or text.find(start_marker, start + 1) >= 0:
    raise SystemExit('unexpected Manhastro search method shape')
new_search = """  @override
  Future<MangaSearchPage> search(MangaSearchRequest request) async {
    final page = _searchPage(request.pageToken);
    final query = request.query.trim();
    final cacheKey = '$page\\u0000$query';
    final cached = _searchCache[cacheKey];
    final now = _now();
    if (cached != null &&
        now.difference(cached.cachedAt) < _catalogCacheTtl) {
      return cached.page;
    }

    final uri = _apiBase.resolve('dados').replace(
      queryParameters: <String, String>{
        'page': '$page',
        'per_page': '$_pageSize',
        if (query.isNotEmpty) 'nome': query,
      },
    );
    final payload = await _jsonMap(uri);
    final rawItems = payload['data'];
    if (rawItems is! List) {
      throw const FormatException('Manhastro catalog response has no data.');
    }

    final items = <MangaSourceOccurrence>[];
    for (final raw in rawItems) {
      final item = _map(raw);
      if (item == null) {
        throw const FormatException(
          'Manhastro catalog response has an invalid item.',
        );
      }
      final id = _mangaId(item);
      if (id == null) {
        throw const FormatException(
          'Manhastro catalog response has an invalid manga id.',
        );
      }
      final title = _displayTitle(item);
      if (title.isEmpty) {
        continue;
      }
      items.add(
        MangaSourceOccurrence(
          sourceId: sourceId,
          mangaId: id,
          title: title,
          coverUrl: _normalizeUrl(item['imagem']),
        ),
      );
    }

    final meta = _map(payload['meta']);
    if (meta == null) {
      throw const FormatException(
        'Manhastro catalog response has no pagination metadata.',
      );
    }
    final currentPage = _positiveInt(meta['current_page']);
    final perPage = _positiveInt(meta['per_page']);
    final total = _nonNegativeInt(meta['total']);
    final lastPage = _positiveInt(meta['last_page']);
    final hasMore = meta['has_more'];
    if (currentPage == null ||
        currentPage != page ||
        perPage == null ||
        perPage != _pageSize ||
        total == null ||
        lastPage == null ||
        hasMore is! bool) {
      throw const FormatException(
        'Manhastro catalog response has invalid pagination metadata.',
      );
    }
    if (rawItems.length > perPage) {
      throw const FormatException(
        'Manhastro catalog response exceeds its page size.',
      );
    }
    final expectedLastPage = total == 0
        ? 1
        : (total + perPage - 1) ~/ perPage;
    final minimumTotal = (currentPage - 1) * perPage + rawItems.length;
    final expectedHasMore = currentPage < lastPage;
    if (currentPage > lastPage ||
        lastPage != expectedLastPage ||
        total < minimumTotal ||
        hasMore != expectedHasMore ||
        (hasMore && rawItems.isEmpty)) {
      throw const FormatException(
        'Manhastro catalog response has contradictory pagination metadata.',
      );
    }

    final result = MangaSearchPage(
      items: List<MangaSourceOccurrence>.unmodifiable(items),
      nextPageToken: hasMore ? '${currentPage + 1}' : null,
    );
    _searchCache[cacheKey] = _ManhastroSearchCacheEntry(
      page: result,
      cachedAt: _now(),
    );
    return result;
  }
"""
text = text[:start] + new_search + text[end:]

normalize_start = text.find("String _normalize(String value) {\n")
normalize_end = text.find("String? _normalizeUrl(Object? value) {\n", normalize_start)
if normalize_start < 0 or normalize_end < 0:
    raise SystemExit('unexpected Manhastro normalize helper shape')
text = text[:normalize_start] + text[normalize_end:]

nullable_compare = """int _nullableIntCompare(int? left, int? right) =>
    (left ?? 0).compareTo(right ?? 0);

"""
if text.count(nullable_compare) != 1:
    raise SystemExit(f'unexpected nullable-int helper shape: {text.count(nullable_compare)}')
text = text.replace(nullable_compare, '', 1)

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
  } else if (value is String) {
    parsed = int.tryParse(value.trim());
  }
  return parsed != null && parsed >= 0 ? parsed : null;
}
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected non-negative integer helper shape: {text.count(old)}')
text = text.replace(old, new, 1)

class_marker = """}

Map<String, dynamic>? _map(Object? value) {
"""
cache_class = """}

final class _ManhastroSearchCacheEntry {
  const _ManhastroSearchCacheEntry({required this.page, required this.cachedAt});

  final MangaSearchPage page;
  final DateTime cachedAt;
}

Map<String, dynamic>? _map(Object? value) {
"""
if text.count(class_marker) != 1:
    raise SystemExit(f'unexpected provider closing marker shape: {text.count(class_marker)}')
text = text.replace(class_marker, cache_class, 1)
provider.write_text(text, encoding='utf-8')

fixture_path = Path('test/fixtures/manga/providers/manhastro/fixture.json')
fixture = json.loads(fixture_path.read_text(encoding='utf-8'))
catalog = fixture.get('catalog')
if not isinstance(catalog, dict) or not isinstance(catalog.get('data'), list):
    raise SystemExit('unexpected Manhastro fixture catalog shape')
catalog['meta'] = {
    'current_page': 1,
    'per_page': 100,
    'total': len(catalog['data']),
    'last_page': 1,
    'has_more': False,
}
fixture_path.write_text(json.dumps(fixture, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

cache_test = Path('test/services/manga/providers/manhastro_manga_provider_cache_test.dart')
cache_text = cache_test.read_text(encoding='utf-8')
old = """      'data': <Object?>[
        <String, Object?>{
          'manga_id': 42,
          'titulo_brasil': title,
          'titulo': title,
          'views_mes': 1,
        },
      ],
"""
new = """      'data': <Object?>[
        <String, Object?>{
          'manga_id': 42,
          'titulo_brasil': title,
          'titulo': title,
          'views_mes': 1,
        },
      ],
      'meta': <String, Object?>{
        'current_page': 1,
        'per_page': 100,
        'total': 1,
        'last_page': 1,
        'has_more': false,
      },
"""
if cache_text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro cache fixture shape: {cache_text.count(old)}')
cache_test.write_text(cache_text.replace(old, new, 1), encoding='utf-8')

materializer = Path('tools/manga/materialize_global_manga_availability_ci.sh')
lines = materializer.read_text(encoding='utf-8').splitlines()
needle = 'test/services/manga/providers/manhastro_manga_provider_cache_test.dart'
new_path = 'test/services/manga/providers/manhastro_manga_provider_pagination_test.dart'
if any(new_path in line for line in lines):
    raise SystemExit('Manhastro pagination test is already present in materializer')
matches = [i for i, line in enumerate(lines) if needle in line]
if len(matches) != 4:
    raise SystemExit(f'unexpected Manhastro cache-test materializer count: {len(matches)}')
for index in reversed(matches):
    line = lines[index]
    indent = line[: len(line) - len(line.lstrip())]
    suffix = ' \\' if line.rstrip().endswith('\\') else ''
    lines.insert(index + 1, f'{indent}{new_path}{suffix}')
materializer.write_text('\n'.join(lines) + '\n', encoding='utf-8')

gate = Path('test/tools/materialize_global_manga_availability_gate_test.dart')
gate_text = gate.read_text(encoding='utf-8')
needle = "      'test/services/manga/providers/manhastro_manga_provider_cache_test.dart',\n"
insert = needle + "      'test/services/manga/providers/manhastro_manga_provider_pagination_test.dart',\n"
if gate_text.count(needle) != 1:
    raise SystemExit(f'unexpected Manhastro cache-test gate shape: {gate_text.count(needle)}')
if 'manhastro_manga_provider_pagination_test.dart' in gate_text:
    raise SystemExit('Manhastro pagination test is already present in gate')
gate.write_text(gate_text.replace(needle, insert, 1), encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
git diff --check

flutter test --no-pub --concurrency=1 \
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart
flutter analyze --no-pub \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart

git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git add -- \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/fixtures/manga/providers/manhastro/fixture.json \
  test/services/manga/providers/manhastro_manga_provider_test.dart \
  test/services/manga/providers/manhastro_manga_provider_response_test.dart \
  test/services/manga/providers/manhastro_manga_provider_strict_items_test.dart \
  test/services/manga/providers/manhastro_manga_provider_cache_test.dart \
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart \
  test/tools/materialize_global_manga_availability_gate_test.dart \
  tools/manga/materialize_global_manga_availability_ci.sh
git diff --cached --check
git commit -m 'fix(manga): follow Manhastro catalog pagination'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[manhastro-live-pagination] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/manhastro-live-pagination-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
