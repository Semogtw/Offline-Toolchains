#!/usr/bin/env bash
set -euo pipefail

: "${PRIVATE_REPOSITORIES_TOKEN:?PRIVATE_REPOSITORIES_TOKEN is required}"
request="$(git diff-tree --no-commit-id --name-only --diff-filter=A -r HEAD^ HEAD -- 'triggers/goanime-manhastro-details-by-id-fix/*.request' | head -n 1)"
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

rm -rf private-source /tmp/manhastro-details-red.log
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
  > /tmp/manhastro-details-red.log 2>&1
red_status=$?
set -e
test "$red_status" -ne 0
grep -Fq 'details resolves uncached occurrence through manga_id filter' /tmp/manhastro-details-red.log
grep -Fq 'details reuses a freshly searched catalog item' /tmp/manhastro-details-red.log
echo '[tdd] RED observed: Manhastro details still depend on the legacy first-page catalog'

python3 - <<'PY'
from pathlib import Path

path = Path('lib/services/manga/providers/manhastro_manga_provider.dart')
text = path.read_text(encoding='utf-8')

old = """  List<Map<String, dynamic>>? _catalogCache;
  DateTime? _catalogCachedAt;
  final Map<String, _ManhastroSearchCacheEntry> _searchCache =
      <String, _ManhastroSearchCacheEntry>{};
"""
new = """  final Map<String, _ManhastroSearchCacheEntry> _searchCache =
      <String, _ManhastroSearchCacheEntry>{};
  final Map<String, _ManhastroCatalogItemCacheEntry> _catalogItemCache =
      <String, _ManhastroCatalogItemCacheEntry>{};
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro cache fields: {text.count(old)}')
text = text.replace(old, new, 1)

old = """    final items = <MangaSourceOccurrence>[];
    for (final raw in rawItems) {
"""
new = """    final items = <MangaSourceOccurrence>[];
    final catalogItems = <String, Map<String, dynamic>>{};
    for (final raw in rawItems) {
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro search item-list shape: {text.count(old)}')
text = text.replace(old, new, 1)

old = """      if (title.isEmpty) {
        continue;
      }
      items.add(
"""
new = """      if (title.isEmpty) {
        continue;
      }
      catalogItems[id] = Map<String, dynamic>.unmodifiable(item);
      items.add(
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro catalogable-item shape: {text.count(old)}')
text = text.replace(old, new, 1)

start_marker = "    final meta = _map(payload['meta']);\n"
end_marker = "\n    final result = MangaSearchPage(\n"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0 or text.find(start_marker, start + 1) >= 0:
    raise SystemExit('unexpected Manhastro inline pagination validator shape')
replacement = """    final hasMore = _catalogHasMore(
      payload,
      requestedPage: page,
      pageSize: _pageSize,
      itemCount: rawItems.length,
    );
"""
text = text[:start] + replacement + text[end:]
text = text.replace(
    "      nextPageToken: hasMore ? '${currentPage + 1}' : null,",
    "      nextPageToken: hasMore ? '${page + 1}' : null,",
    1,
)

old = """    _searchCache[cacheKey] = _ManhastroSearchCacheEntry(
      page: result,
      cachedAt: _now(),
    );
"""
new = """    final cachedAt = _now();
    for (final entry in catalogItems.entries) {
      _catalogItemCache[entry.key] = _ManhastroCatalogItemCacheEntry(
        item: entry.value,
        cachedAt: cachedAt,
      );
    }
    _searchCache[cacheKey] = _ManhastroSearchCacheEntry(
      page: result,
      cachedAt: cachedAt,
    );
"""
if text.count(old) != 1:
    raise SystemExit(f'unexpected Manhastro search cache store shape: {text.count(old)}')
text = text.replace(old, new, 1)

catalog_start = text.find("  Future<List<Map<String, dynamic>>> _catalog() async {\n")
json_start = text.find("  Future<Map<String, dynamic>> _jsonMap(Uri uri) async {\n", catalog_start)
if catalog_start < 0 or json_start < 0:
    raise SystemExit('unexpected legacy Manhastro catalog helper shape')
new_catalog_item = """  Future<Map<String, dynamic>> _catalogItem(String mangaId) async {
    final cached = _catalogItemCache[mangaId];
    final now = _now();
    if (cached != null &&
        now.difference(cached.cachedAt) < _catalogCacheTtl) {
      return cached.item;
    }

    final uri = _apiBase.resolve('dados').replace(
      queryParameters: <String, String>{
        'page': '1',
        'per_page': '$_pageSize',
        'manga_id': mangaId,
      },
    );
    final payload = await _jsonMap(uri);
    final rawItems = payload['data'];
    if (rawItems is! List) {
      throw const FormatException('Manhastro catalog response has no data.');
    }
    final hasMore = _catalogHasMore(
      payload,
      requestedPage: 1,
      pageSize: _pageSize,
      itemCount: rawItems.length,
    );
    if (hasMore || rawItems.length != 1) {
      throw FormatException(
        'Manhastro manga $mangaId did not resolve to exactly one catalog item.',
      );
    }
    final item = _map(rawItems.single);
    final resolvedId = item == null ? null : _mangaId(item);
    if (item == null ||
        resolvedId != mangaId ||
        _displayTitle(item).isEmpty) {
      throw FormatException(
        'Manhastro manga $mangaId returned an invalid catalog identity.',
      );
    }
    final frozen = Map<String, dynamic>.unmodifiable(item);
    _catalogItemCache[mangaId] = _ManhastroCatalogItemCacheEntry(
      item: frozen,
      cachedAt: _now(),
    );
    return frozen;
  }

"""
text = text[:catalog_start] + new_catalog_item + text[json_start:]

marker = """final class _ManhastroSearchCacheEntry {
"""
helper = """bool _catalogHasMore(
  Map<String, dynamic> payload, {
  required int requestedPage,
  required int pageSize,
  required int itemCount,
}) {
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
      currentPage != requestedPage ||
      perPage == null ||
      perPage != pageSize ||
      total == null ||
      lastPage == null ||
      hasMore is! bool) {
    throw const FormatException(
      'Manhastro catalog response has invalid pagination metadata.',
    );
  }
  if (itemCount > perPage) {
    throw const FormatException(
      'Manhastro catalog response exceeds its page size.',
    );
  }
  final expectedLastPage = total == 0 ? 1 : (total + perPage - 1) ~/ perPage;
  final minimumTotal = (currentPage - 1) * perPage + itemCount;
  final expectedHasMore = currentPage < lastPage;
  if (currentPage > lastPage ||
      lastPage != expectedLastPage ||
      total < minimumTotal ||
      hasMore != expectedHasMore ||
      (hasMore && itemCount == 0)) {
    throw const FormatException(
      'Manhastro catalog response has contradictory pagination metadata.',
    );
  }
  return hasMore;
}

final class _ManhastroCatalogItemCacheEntry {
  const _ManhastroCatalogItemCacheEntry({
    required this.item,
    required this.cachedAt,
  });

  final Map<String, dynamic> item;
  final DateTime cachedAt;
}

""" + marker
if text.count(marker) != 1:
    raise SystemExit(f'unexpected Manhastro cache-class marker: {text.count(marker)}')
text = text.replace(marker, helper, 1)
path.write_text(text, encoding='utf-8')
PY

dart format \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart
dart format --output=none --set-exit-if-changed \
  lib/services/manga/providers/manhastro_manga_provider.dart \
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart
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
  test/services/manga/providers/manhastro_manga_provider_pagination_test.dart
git diff --cached --check
git commit -m 'fix(manga): resolve Manhastro details by id'
published_sha="$(git rev-parse HEAD)"

remote_head="$(git -c http.extraheader="AUTHORIZATION: basic $auth" ls-remote "$remote_url" "refs/heads/$target_branch" | awk '{print $1}')"
test "$remote_head" = "$expected_sha"
git -c http.extraheader="AUTHORIZATION: basic $auth" push -q origin "HEAD:refs/heads/$target_branch"
echo "[manhastro-details-by-id] published $published_sha"
popd >/dev/null

rm -rf private-source /tmp/manhastro-details-red.log
unset auth PRIVATE_REPOSITORIES_TOKEN
