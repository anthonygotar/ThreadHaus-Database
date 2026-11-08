# MongoDB index explain timings

| Query | Docs examined before | Docs examined after | Time before (ms) | Time after (ms) | Plan before | Plan after | Index used | Kept? |
|---|---|---|---|---|---|---|---|---|
| M1 Catalogue search | 1000 | 198 | 3 | 11 | COLLSCAN | FETCH (IXSCAN) | idx_variants_search | **Kept** — docs examined -80%; ms higher due to $unwind overhead |
| M3 Top rated | 1000 | 20 | 2 | 2 | SORT (full scan) | LIMIT (IXSCAN) | idx_rating_summary | **Kept** — docs examined -98%; same time but avoids full scan under load |
| M5 Text search | N/A (no text index = error) | 63 | N/A | 4 | N/A | TEXT_MATCH | idx_text_search | **Kept** — query impossible without it |

## Notes on idx_category_path

`idx_category_path` was created for M1 to filter by parent category. The planner chose `idx_variants_search` instead because it is more selective for this query (filters by size, colour and stock_qty simultaneously). `idx_category_path` is still useful for queries that filter only by category (e.g. count products per category) but was not needed for M1 alongside `idx_variants_search`. Kept because it helps other category-filter queries and is small.

## Summary

All four indexes were kept. Three are clearly useful (M1 docs -80%, M3 docs -98%, M5 was impossible without text index). `idx_category_path` was kept as it aids category-only queries even though the planner did not choose it for M1.
