-- 07-nonrepeatable-s2.sql
-- Session 2: starts 1s after S1, raises variant 3 price by 500 and commits.
-- Shared by both 07a and 07b runs.

SELECT pg_sleep(1);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN' AS log;
BEGIN;

SELECT '[S2] ' || clock_timestamp()::text || ' Updating variant 3 price: +500' AS log;
UPDATE product_variant SET price = price + 500 WHERE variant_id = 3;

SELECT '[S2] ' || clock_timestamp()::text || ' COMMIT' AS log;
COMMIT;
SELECT '[S2] Done — price updated and committed.' AS log;
