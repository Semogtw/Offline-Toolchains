# Manga catalog inventory

- Generated: `2026-08-25T04:16:29.610275Z`
- Enabled providers: **16**
- Exhaustively paginated providers: **13**
- Unique source occurrences: **11088**
- Conservative title-deduplicated works: **9571**

> Deduplication is intentionally conservative: exact normalized titles are merged only across providers; a normalized-title collision inside one provider is never auto-merged.

| Provider | Status | Pages | Raw | Unique | Duplicates | Stop reason |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `ptbr.arthurscan` | failed | 0 | 0 | 0 | 0 | `provider_failure` |
| `ptbr.astratoons` | exhausted | 18 | 177 | 176 | 1 | `next_page_token_null` |
| `ptbr.hqnow` | exhausted | 1 | 2856 | 2856 | 0 | `next_page_token_null` |
| `ptbr.hipertoon` | exhausted | 106 | 2538 | 2538 | 0 | `next_page_token_null` |
| `ptbr.capitoons` | exhausted | 3 | 24 | 24 | 0 | `next_page_token_null` |
| `ptbr.kamisamaexplorer` | exhausted | 4 | 34 | 34 | 0 | `next_page_token_null` |
| `ptbr.kivaratoons` | exhausted | 132 | 3156 | 3156 | 0 | `next_page_token_null` |
| `ptbr.leituramanga` | exhausted | 59 | 1398 | 1398 | 0 | `next_page_token_null` |
| `ptbr.ler999` | exhausted | 1 | 7 | 7 | 0 | `next_page_token_null` |
| `ptbr.littletyrant` | exhausted | 29 | 290 | 290 | 0 | `next_page_token_null` |
| `ptbr.maidscan` | exhausted | 6 | 154 | 154 | 0 | `next_page_token_null` |
| `ptbr.mangadash` | exhausted | 15 | 343 | 343 | 0 | `next_page_token_null` |
| `ptbr.mangaflix` | exhausted | 1 | 100 | 100 | 0 | `next_page_token_null` |
| `ptbr.mangalivreblog` | not_enumerable | 1 | 0 | 0 | 0 | `empty_query_returned_no_catalog` |
| `ptbr.mangalivreorg` | failed | 0 | 0 | 0 | 0 | `provider_failure` |
| `ptbr.ninjascan` | exhausted | 1 | 12 | 12 | 0 | `next_page_token_null` |

## Interpretation

The source-occurrence count is exact for providers marked `exhausted`. Providers marked `partial`, `failed` or `not_enumerable` are explicitly excluded from any claim that this is the absolute upstream universe.
