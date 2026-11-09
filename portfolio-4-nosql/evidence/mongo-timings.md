# MongoDB index explain timings (updated after 10-run re-test)

10 runs with and without each index. Median of 10 recorded.

| Query | Docs examined without index | Docs examined with index | Median time without (ms) | Median time with (ms) | Plan without | Plan with | Index used | Kept? |
|---|---|---|---|---|---|---|---|---|
| M1 Catalogue search | 1000 | 198 | 7.0 | 8.0 | COLLSCAN | FETCH (IXSCAN) | idx_variants_search | **Kept** — docs examined -80%; time gain not measurable at 1000 docs (all in memory) |
| M3 Top rated | 1000 | 20 | 4.5 | 0.0 | SORT (COLLSCAN) | LIMIT (IXSCAN) | idx_rating_summary | **Kept** — docs examined -98%, median time -100% |
| M5 Text search | N/A (query impossible) | 63 | N/A | 4 | N/A | TEXT_MATCH | idx_text_search | **Kept** — required for $text query |

## Additional indexes (not tested with explain but kept)
| Index | Purpose | Kept? |
|---|---|---|
| idx_category_path | Category-only filter queries | Kept — small overhead, aids category browsing |

## Notes
- M1: The planner chose `idx_variants_search` over `idx_category_path` for this query. Both array fields cannot be in the same compound index (MongoDB parallel arrays restriction). Separate indexes exist for both use cases.
- M1 time did not improve at 1000 documents (all cached in memory). At larger scale the index would prevent a disk scan. Docs examined dropped 80% which meets the ≥50% threshold for keeping.
- M3 improved clearly: 0ms median with index vs 4.5ms without, and only 20 docs examined instead of 1000.
