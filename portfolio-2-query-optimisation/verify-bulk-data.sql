-- ThreadHaus bulk data verification
-- Run against threadhaus_perf after bulk-data.sql has loaded.

-- a. Row counts for all 14 tables
SELECT 'customer'        AS table_name, COUNT(*) AS row_count FROM customer
UNION ALL SELECT 'address',             COUNT(*) FROM address
UNION ALL SELECT 'staff',               COUNT(*) FROM staff
UNION ALL SELECT 'rider',               COUNT(*) FROM rider
UNION ALL SELECT 'category',            COUNT(*) FROM category
UNION ALL SELECT 'product',             COUNT(*) FROM product
UNION ALL SELECT 'product_variant',     COUNT(*) FROM product_variant
UNION ALL SELECT 'orders',              COUNT(*) FROM orders
UNION ALL SELECT 'order_item',          COUNT(*) FROM order_item
UNION ALL SELECT 'payment',             COUNT(*) FROM payment
UNION ALL SELECT 'delivery',            COUNT(*) FROM delivery
UNION ALL SELECT 'return_request',      COUNT(*) FROM return_request
UNION ALL SELECT 'complaint',           COUNT(*) FROM complaint
UNION ALL SELECT 'review',              COUNT(*) FROM review
ORDER BY table_name;

-- b. Orders whose total_amount does not equal the sum of their items (must be 0)
SELECT COUNT(*) AS total_mismatch_count
FROM orders o
JOIN (
    SELECT order_id, SUM(quantity * unit_price) AS item_total
    FROM order_item
    GROUP BY order_id
) oi ON oi.order_id = o.order_id
WHERE o.total_amount <> oi.item_total;

-- c. Orders placed in the last 30 days
SELECT COUNT(*) AS orders_last_30_days
FROM orders
WHERE order_date >= now() - interval '30 days';

-- d. Status distribution of orders
SELECT status, COUNT(*) AS count,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM orders
GROUP BY status
ORDER BY count DESC;

-- e. Orders that have more than one payment
SELECT COUNT(*) AS orders_with_multiple_payments
FROM (
    SELECT order_id
    FROM payment
    GROUP BY order_id
    HAVING COUNT(*) > 1
) sub;
