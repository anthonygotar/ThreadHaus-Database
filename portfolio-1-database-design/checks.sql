-- ThreadHaus checks
-- Run after schema.sql and sample-data.sql.
-- Three queries: row counts, order totals vs item sums, orders with customer/payment/delivery.

-- -----------------------------------------------------------------------------
-- a. Row counts for all 14 tables
-- -----------------------------------------------------------------------------
SELECT 'customer'        AS table_name, COUNT(*) AS row_count FROM customer
UNION ALL
SELECT 'address',                        COUNT(*) FROM address
UNION ALL
SELECT 'staff',                          COUNT(*) FROM staff
UNION ALL
SELECT 'rider',                          COUNT(*) FROM rider
UNION ALL
SELECT 'category',                       COUNT(*) FROM category
UNION ALL
SELECT 'product',                        COUNT(*) FROM product
UNION ALL
SELECT 'product_variant',                COUNT(*) FROM product_variant
UNION ALL
SELECT 'orders',                         COUNT(*) FROM orders
UNION ALL
SELECT 'order_item',                     COUNT(*) FROM order_item
UNION ALL
SELECT 'payment',                        COUNT(*) FROM payment
UNION ALL
SELECT 'delivery',                       COUNT(*) FROM delivery
UNION ALL
SELECT 'return_request',                 COUNT(*) FROM return_request
UNION ALL
SELECT 'complaint',                      COUNT(*) FROM complaint
UNION ALL
SELECT 'review',                         COUNT(*) FROM review
ORDER BY table_name;

-- -----------------------------------------------------------------------------
-- b. For each order, compare stored total_amount against sum of item lines.
--    These should match. A mismatch means the app wrote a wrong total.
-- -----------------------------------------------------------------------------
SELECT
    o.order_id,
    o.total_amount                          AS stored_total,
    SUM(oi.quantity * oi.unit_price)        AS calculated_total,
    o.total_amount - SUM(oi.quantity * oi.unit_price) AS difference
FROM orders o
JOIN order_item oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.total_amount
ORDER BY o.order_id;

-- -----------------------------------------------------------------------------
-- c. Orders joined to customer name, latest payment status, delivery status
-- -----------------------------------------------------------------------------
SELECT
    o.order_id,
    c.full_name                             AS customer,
    o.status                                AS order_status,
    o.total_amount,
    p.status                                AS payment_status,
    p.method                                AS payment_method,
    d.status                                AS delivery_status
FROM orders o
JOIN customer  c ON c.customer_id = o.customer_id
LEFT JOIN LATERAL (
    -- latest payment row per order
    SELECT status, method
    FROM payment
    WHERE order_id = o.order_id
    ORDER BY paid_at DESC NULLS LAST, payment_id DESC
    LIMIT 1
) p ON true
LEFT JOIN delivery d ON d.order_id = o.order_id
ORDER BY o.order_id;
