-- 09-dirty-s1.sql
-- Session 1: updates variant 3 price but does NOT commit yet.
-- Sleeps 3s (giving S2 time to read), then ROLLBACKs.
-- The update is never committed — it is a dirty write.

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S1] ' || clock_timestamp()::text || ' Updating variant 3 price to 99999 (NOT committing yet)' AS log;
UPDATE product_variant SET price = 99999.00 WHERE variant_id = 3;

SELECT '[S1] ' || clock_timestamp()::text || ' Sleeping 3s — S2 will try to read the dirty value during this sleep' AS log;
SELECT pg_sleep(3);

SELECT '[S1] ' || clock_timestamp()::text || ' Rolling back — this update is discarded' AS log;
ROLLBACK;
SELECT '[S1] Done — update rolled back.' AS log;
