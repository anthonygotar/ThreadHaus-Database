-- ThreadHaus baseline queries
-- Course: MIT 8103 Advanced Database Systems, MIVA Open University
-- Portfolio 2: Query Optimisation
--
-- Run against threadhaus_perf (bulk data loaded).
-- Parameter values are chosen from real data in the database.
-- Each query has a comment with the business question and the parameter values used.

-- =============================================================================
-- Q1: Catalogue search
-- Business question: Show all in-stock variants of products in a chosen parent
-- category and its children, for a chosen size and colour, ordered by price.
-- Parameters: parent_category_id = 1 (Men), size = 'M', colour = 'Black'
-- =============================================================================
SELECT
    p.name          AS product_name,
    p.brand,
    pv.sku,
    pv.size,
    pv.colour,
    pv.price,
    pv.stock_qty
FROM product_variant pv
JOIN product  p  ON p.product_id  = pv.product_id
JOIN category c  ON c.category_id = p.category_id
WHERE pv.deleted_at IS NULL
  AND p.deleted_at  IS NULL
  AND pv.stock_qty  > 0
  AND pv.size       = 'M'
  AND pv.colour     = 'Black'
  AND (
        c.category_id        = 1   -- is the parent itself
     OR c.parent_category_id = 1   -- is a direct child
  )
ORDER BY pv.price;

-- =============================================================================
-- Q2: Order history
-- Business question: Show all orders for one customer with item count and
-- items total, newest first.
-- Parameters: customer_id = 4790  (has 10 orders in the dataset)
-- =============================================================================
SELECT
    o.order_id,
    o.order_date,
    o.status,
    o.total_amount,
    COUNT(oi.order_item_id)              AS item_count,
    SUM(oi.quantity * oi.unit_price)     AS items_total
FROM orders o
JOIN order_item oi ON oi.order_id = o.order_id
WHERE o.customer_id = 4790
GROUP BY o.order_id, o.order_date, o.status, o.total_amount
ORDER BY o.order_date DESC;

-- =============================================================================
-- Q3: Best sellers
-- Business question: The 10 product variants with the highest total quantity
-- sold in the last 30 days, excluding cancelled orders, with product name,
-- size and colour.
-- Parameters: last 30 days from now(), status != 'cancelled'
-- =============================================================================
SELECT
    pv.variant_id,
    p.name      AS product_name,
    pv.size,
    pv.colour,
    SUM(oi.quantity) AS total_qty_sold
FROM order_item oi
JOIN orders         o  ON o.order_id   = oi.order_id
JOIN product_variant pv ON pv.variant_id = oi.variant_id
JOIN product        p  ON p.product_id  = pv.product_id
WHERE o.order_date >= now() - interval '30 days'
  AND o.status     != 'cancelled'
GROUP BY pv.variant_id, p.name, pv.size, pv.colour
ORDER BY total_qty_sold DESC
LIMIT 10;

-- =============================================================================
-- Q4: Monthly sales report
-- Business question: Total amount of successful payments grouped by month.
-- Parameters: status = 'successful'
-- =============================================================================
SELECT
    date_trunc('month', paid_at)    AS month,
    COUNT(*)                        AS payment_count,
    SUM(amount)                     AS total_revenue
FROM payment
WHERE status = 'successful'
GROUP BY date_trunc('month', paid_at)
ORDER BY month DESC;

-- =============================================================================
-- Q5: Orders awaiting a rider
-- Business question: Orders with status 'paid' or 'processing' that have no
-- delivery row yet, oldest first.
-- Parameters: status IN ('paid','processing'), no delivery row
-- =============================================================================
SELECT
    o.order_id,
    o.customer_id,
    o.order_date,
    o.status,
    o.total_amount
FROM orders o
WHERE o.status IN ('paid', 'processing')
  AND NOT EXISTS (
        SELECT 1 FROM delivery d WHERE d.order_id = o.order_id
  )
ORDER BY o.order_date
LIMIT 20;

-- =============================================================================
-- Q6: Product ratings
-- Business question: Average rating and review count per product, only for
-- products with at least 5 reviews, top 20 by average rating.
-- Parameters: min 5 reviews
-- =============================================================================
SELECT
    p.product_id,
    p.name          AS product_name,
    p.brand,
    ROUND(AVG(r.rating), 2) AS avg_rating,
    COUNT(r.review_id)      AS review_count
FROM review r
JOIN product p ON p.product_id = r.product_id
GROUP BY p.product_id, p.name, p.brand
HAVING COUNT(r.review_id) >= 5
ORDER BY avg_rating DESC, review_count DESC
LIMIT 20;
