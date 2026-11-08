-- 10b-writeskew-s2.sql
-- Write skew fix under SERIALIZABLE.
-- S2 also tries to mark rider 2 unavailable.
-- One session will fail with serialization error. The runner retries it.

SELECT pg_sleep(1);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN SERIALIZABLE' AS log;
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT '[S2] ' || clock_timestamp()::text || ' Count of available riders (should be 2)' AS log;
SELECT COUNT(*) AS available_riders FROM rider WHERE is_available = TRUE AND deleted_at IS NULL;

SELECT '[S2] ' || clock_timestamp()::text || ' Sleeping 2s' AS log;
SELECT pg_sleep(2);

SELECT '[S2] ' || clock_timestamp()::text || ' Count > 1, marking rider 2 unavailable' AS log;
UPDATE rider SET is_available = FALSE WHERE rider_id = 2;

SELECT '[S2] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S2] Done.' AS log;
