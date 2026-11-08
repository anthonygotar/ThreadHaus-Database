-- 09-dirty-s2.sql
-- Session 2: sets READ UNCOMMITTED and reads variant 3 price while S1's
-- update is in-flight (not yet committed or rolled back).
--
-- In most databases READ UNCOMMITTED would allow seeing S1's dirty write (99999).
-- PostgreSQL does NOT implement dirty reads: it treats READ UNCOMMITTED
-- as READ COMMITTED. So S2 still sees the last COMMITTED price (6500.00),
-- not S1's uncommitted 99999.
--
-- This demonstrates that PostgreSQL's weakest isolation level still
-- prevents dirty reads.

SELECT pg_sleep(1);

SELECT '[S2] ' || clock_timestamp()::text || ' BEGIN READ UNCOMMITTED' AS log;
BEGIN ISOLATION LEVEL READ UNCOMMITTED;

SELECT '[S2] ' || clock_timestamp()::text || ' Reading variant 3 price (S1 has updated but not committed)' AS log;
SELECT '[S2] NOTE: PostgreSQL treats READ UNCOMMITTED as READ COMMITTED.' AS log;
SELECT '[S2] We expect to see 6500.00, NOT 99999.00 (no dirty read in PostgreSQL).' AS log;
SELECT variant_id, sku, price FROM product_variant WHERE variant_id = 3;

COMMIT;
SELECT '[S2] Done.' AS log;
