-- 10a-writeskew-s1.sql
-- Write skew scenario under REPEATABLE READ.
-- Rule: at least one rider must remain available.
-- Setup: exactly two riders available (rider 1 and rider 2).
-- S1 checks count (sees 2), decides it is safe, sets rider 1 unavailable.
-- S2 does the same for rider 2 — both commit, leaving zero riders available.
-- The rule is violated. This is write skew.

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN REPEATABLE READ' AS log;
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT '[S1] ' || clock_timestamp()::text || ' Count of available riders (should be 2)' AS log;
SELECT COUNT(*) AS available_riders FROM rider WHERE is_available = TRUE AND deleted_at IS NULL;

SELECT '[S1] ' || clock_timestamp()::text || ' Sleeping 2s (S2 will also read count and mark its rider)' AS log;
SELECT pg_sleep(2);

SELECT '[S1] ' || clock_timestamp()::text || ' Count > 1, so marking rider 1 unavailable' AS log;
UPDATE rider SET is_available = FALSE WHERE rider_id = 1;

SELECT '[S1] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S1] Done.' AS log;
