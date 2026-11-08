-- 10a-writeskew-s2.sql
-- Write skew scenario under REPEATABLE READ.
-- S2 also reads count=2, decides safe, sets rider 2 unavailable.
-- Both S1 and S2 commit — zero riders remain. Rule broken.

SELECT pg_sleep(1);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN REPEATABLE READ' AS log;
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT '[S2] ' || clock_timestamp()::text || ' Count of available riders (should be 2)' AS log;
SELECT COUNT(*) AS available_riders FROM rider WHERE is_available = TRUE AND deleted_at IS NULL;

SELECT '[S2] ' || clock_timestamp()::text || ' Sleeping 2s' AS log;
SELECT pg_sleep(2);

SELECT '[S2] ' || clock_timestamp()::text || ' Count > 1, so marking rider 2 unavailable' AS log;
UPDATE rider SET is_available = FALSE WHERE rider_id = 2;

SELECT '[S2] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S2] Done.' AS log;
