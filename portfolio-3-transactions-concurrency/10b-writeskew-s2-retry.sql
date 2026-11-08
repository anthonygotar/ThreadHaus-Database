-- 10b-writeskew-s2-retry.sql
-- Retry after the serialization failure.
-- S2 re-runs its transaction. It now sees count=1 (only 1 rider available)
-- and does not change anything — the rule is preserved.

SELECT '[S2-RETRY] ' || clock_timestamp()::text || ' Retrying transaction after serialization failure' AS log;
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT '[S2-RETRY] ' || clock_timestamp()::text || ' Count of available riders' AS log;
SELECT COUNT(*) AS available_riders FROM rider WHERE is_available = TRUE AND deleted_at IS NULL;

-- Count is 1 — must not go below 1, so do nothing
SELECT '[S2-RETRY] ' || clock_timestamp()::text || ' Count is 1. Cannot mark another rider unavailable. Rolling back.' AS log;
ROLLBACK;
SELECT '[S2-RETRY] Done — rule preserved.' AS log;
