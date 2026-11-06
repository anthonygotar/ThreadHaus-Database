-- drop-indexes.sql
-- Drops all manually created indexes from the indexing experiment (step 8).
-- Run this to restore threadhaus_perf to the baseline state (PK/UNIQUE only).

DROP INDEX IF EXISTS idx_orders_customer_date;
DROP INDEX IF EXISTS idx_orders_order_date;
DROP INDEX IF EXISTS idx_orders_awaiting;
DROP INDEX IF EXISTS idx_variant_instock;
