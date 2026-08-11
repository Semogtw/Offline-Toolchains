#!/usr/bin/env python3
from pathlib import Path


def replace_once(text: str, old: str, new: str, description: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected {description} exactly once; found {count}")
    return text.replace(old, new)


tool = Path("tools/build_mal_availability_cache.dart")
text = tool.read_text(encoding="utf-8")
old = '''Future<List<JikanAnimeSearchCandidate>> searchCandidatesForAvailableTitle(
  String normalizedTitle, {
  required JikanAnimeSearcher searcher,
  required Map<String, List<JikanAnimeSearchCandidate>> searchCache,
}) async {
  final candidatesByMalId = <int, JikanAnimeSearchCandidate>{};
  for (final query in jikanSearchQueriesForAvailableTitle(normalizedTitle)) {
    final candidates = searchCache[query] ??= (await searcher(
      query,
    )).take(_maxCandidates).toList();
    for (final candidate in candidates) {
      candidatesByMalId.putIfAbsent(candidate.malId, () => candidate);
    }
  }
  return candidatesByMalId.values.take(_maxCandidates * 3).toList();
}
'''
new = '''Future<List<JikanAnimeSearchCandidate>> searchCandidatesForAvailableTitle(
  String normalizedTitle, {
  required JikanAnimeSearcher searcher,
  required Map<String, List<JikanAnimeSearchCandidate>> searchCache,
}) async {
  final candidatesByMalId = <int, JikanAnimeSearchCandidate>{};
  for (final query in jikanSearchQueriesForAvailableTitle(normalizedTitle)) {
    final candidates = searchCache[query] ??= (await searcher(
      query,
    )).take(_maxCandidates).toList();
    for (final candidate in candidates) {
      candidatesByMalId.putIfAbsent(candidate.malId, () => candidate);
    }

    final accumulated = candidatesByMalId.values
        .take(_maxCandidates * 3)
        .toList();
    final decision = matchAvailableTitleToJikanCandidate(
      availableTitle: normalizedTitle,
      candidates: accumulated,
    );
    final accepted = decision.accepted;
    if (accepted != null &&
        accepted.matchType == 'exact_normalized_title' &&
        accepted.confidence >= 0.98) {
      break;
    }
  }
  return candidatesByMalId.values.take(_maxCandidates * 3).toList();
}
'''
text = replace_once(text, old, new, "canonical Jikan search function")
tool.write_text(text, encoding="utf-8")

test = Path("test/tools/build_mal_availability_cache_test.dart")
text = test.read_text(encoding="utf-8")
marker = "  test('exact title accepts', () {\n"
inserted = '''  group('adaptive Jikan query plan', () {
    test('stops after an unequivocal exact normalized match', () async {
      final queries = <String>[];
      final candidates = await builder.searchCandidatesForAvailableTitle(
        'death note',
        searcher: (query) async {
          queries.add(query);
          return <builder.JikanAnimeSearchCandidate>[
            const builder.JikanAnimeSearchCandidate(
              malId: 1535,
              title: 'Death Note',
            ),
          ];
        },
        searchCache: <String, List<builder.JikanAnimeSearchCandidate>>{},
      );

      expect(queries, <String>['death note']);
      expect(candidates.single.malId, 1535);
    });

    test('keeps fallback queries for a non-exact first result', () async {
      final queries = <String>[];
      final candidates = await builder.searchCandidatesForAvailableTitle(
        'death note',
        searcher: (query) async {
          queries.add(query);
          if (query == 'deathnote') {
            return <builder.JikanAnimeSearchCandidate>[
              const builder.JikanAnimeSearchCandidate(
                malId: 1535,
                title: 'Death Note',
              ),
            ];
          }
          return <builder.JikanAnimeSearchCandidate>[
            const builder.JikanAnimeSearchCandidate(
              malId: 999,
              title: 'Death Note Extra',
            ),
          ];
        },
        searchCache: <String, List<builder.JikanAnimeSearchCandidate>>{},
      );

      expect(queries, <String>['death note', 'deathnote']);
      expect(candidates.map((item) => item.malId), contains(1535));
    });
  });

'''
text = replace_once(text, marker, inserted + marker, "exact title test marker")
test.write_text(text, encoding="utf-8")
