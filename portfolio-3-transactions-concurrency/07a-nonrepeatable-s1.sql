-- 07a-nonrepeatable-s1.sql
-- Session 1 under READ COMMITTED.
-- Reads variant 3 price twice with a 2s gap.
-- Under READ COMMITTED each statement gets a fresh snapshot, so the second read
-- sees S2's committed update — this is a non-repeatable read.

SELECT '[S1] ' || clock_timestamp()::text || ' BEGIN READ COMMITTED' AS log;
BEGIN ISOLATION LEVEL READ COMMITTED;

SELECT '[S1] ' || clock_timestamp()::text || ' First read of variant 3 price' AS log;
SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;

SELECT '[S1] ' || clock_timestamp()::text || ' Sleeping 2s (S2 updates price during sleep)' AS log;
SELECT pg_sleep(2);

SELECT '[S1] ' || clock_timestamp()::text || ' Second read — READ COMMITTED sees S2 committed value' AS log;
SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;

COMMIT;
SELECT '[S1] Done.' AS log;
