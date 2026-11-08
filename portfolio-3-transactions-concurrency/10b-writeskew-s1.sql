-- 10b-writeskew-s1.sql
-- Write skew fix under SERIALIZABLE.
-- PostgreSQL detects the read/write dependency between S1 and S2
-- and aborts one of them with "could not serialize access due to
-- read/write dependencies among transactions".

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN SERIALIZABLE' AS log;
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT '[S1] ' || clock_timestamp()::text || ' Count of available riders (should be 2)' AS log;
SELECT COUNT(*) AS available_riders FROM rider WHERE is_available = TRUE AND deleted_at IS NULL;

SELECT '[S1] ' || clock_timestamp()::text || ' Sleeping 2s' AS log;
SELECT pg_sleep(2);

SELECT '[S1] ' || clock_timestamp()::text || ' Count > 1, marking rider 1 unavailable' AS log;
UPDATE rider SET is_available = FALSE WHERE rider_id = 1;

SELECT '[S1] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S1] Done.' AS log;
