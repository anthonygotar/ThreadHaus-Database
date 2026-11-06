-- ThreadHaus bulk test data
-- Course: MIT 8103 Advanced Database Systems, MIVA Open University
-- Portfolio 2: Query Optimisation
--
-- Run against a database that already has schema.sql loaded.
-- All data is generated in SQL using generate_series, random(), md5().
-- setseed() at the top makes the data repeatable.
-- End of file runs ANALYZE so the planner has fresh statistics.

SELECT setseed(0.42);

-- -----------------------------------------------------------------------------
-- staff (10 rows)
-- -----------------------------------------------------------------------------
INSERT INTO staff (full_name, email, password_hash, role)
SELECT
    'Staff ' || n,
    'staff' || n || '@threadhaus.example.com',
    md5('staffpass' || n),
    (ARRAY['admin','manager','support'])[1 + mod(n-1, 3)]
FROM generate_series(1, 10) AS n;

-- -----------------------------------------------------------------------------
-- rider (50 rows)
-- -----------------------------------------------------------------------------
INSERT INTO rider (full_name, phone, is_available)
SELECT
    'Rider ' || n,
    '080' || lpad(n::text, 8, '0'),
    (random() > 0.3)
FROM generate_series(1, 50) AS n;

-- -----------------------------------------------------------------------------
-- customer (10,000 rows)
-- -----------------------------------------------------------------------------
INSERT INTO customer (full_name, email, phone, password_hash)
SELECT
    'Customer ' || n,
    'customer' || n || '@example.com',
    '070' || lpad(n::text, 8, '0'),
    md5('custpass' || n)
FROM generate_series(1, 10000) AS n;

-- -----------------------------------------------------------------------------
-- address (~15,000 rows, ~1.5 per customer)
-- Every customer gets one default address; half also get a second.
-- -----------------------------------------------------------------------------
-- First address for every customer
INSERT INTO address (customer_id, street, city, state, is_default)
SELECT
    n,
    n || ' Main Street',
    (ARRAY['Lagos','Abuja','Kano','Ibadan','Port Harcourt','Enugu','Kaduna','Benin City'])[1 + mod(n-1, 8)],
    (ARRAY['Lagos','FCT','Kano','Oyo','Rivers','Enugu','Kaduna','Edo'])[1 + mod(n-1, 8)],
    true
FROM generate_series(1, 10000) AS n;

-- Second address for customers 1 to 5000
INSERT INTO address (customer_id, street, city, state, is_default)
SELECT
    n,
    n || ' Second Avenue',
    (ARRAY['Lagos','Abuja','Kano','Ibadan','Port Harcourt'])[1 + mod(n, 5)],
    (ARRAY['Lagos','FCT','Kano','Oyo','Rivers'])[1 + mod(n, 5)],
    false
FROM generate_series(1, 5000) AS n;

-- -----------------------------------------------------------------------------
-- category (12 rows: 4 parents, 8 children)
-- -----------------------------------------------------------------------------
INSERT INTO category (parent_category_id, name) VALUES
    (NULL, 'Men'),
    (NULL, 'Women'),
    (NULL, 'Kids'),
    (NULL, 'Accessories');

INSERT INTO category (parent_category_id, name) VALUES
    (1, 'Men Tops'),
    (1, 'Men Bottoms'),
    (1, 'Men Traditional'),
    (2, 'Women Tops'),
    (2, 'Women Bottoms'),
    (2, 'Women Traditional'),
    (3, 'Kids Clothing'),
    (4, 'Bags and Belts');

-- -----------------------------------------------------------------------------
-- product (1,000 rows)
-- category_ids 5 to 12 are the leaf categories (inserted second, so IDs 5-12)
-- -----------------------------------------------------------------------------
INSERT INTO product (category_id, name, description, brand, base_price)
SELECT
    5 + mod(n-1, 8),
    (ARRAY['Ankara Shirt','Joggers','Agbada Set','Blouse','Skirt','Kaftan',
           'Shorts','Polo Shirt','Trousers','Native Senator','Gown','Jacket',
           'Hoodie','Jeans','T-Shirt','Wrapper Set'])[1 + mod(n-1, 16)] || ' ' || n,
    'Description for product ' || n,
    (ARRAY['ThreadHaus','Lagos Stitch','Naija Threads','AsoOke Plus','KachiWear'])[1 + mod(n-1, 5)],
    -- base_price between 3000 and 80000 naira
    ROUND((3000 + random() * 77000)::numeric, 2)
FROM generate_series(1, 1000) AS n;

-- -----------------------------------------------------------------------------
-- product_variant (~5,000 rows)
-- 5 variants per product, each with a unique (product_id, size, colour).
-- SKU: TH-<product_id>-<size_code>-<colour_code>
-- -----------------------------------------------------------------------------
INSERT INTO product_variant (product_id, sku, size, colour, price, stock_qty)
SELECT
    p.product_id,
    'TH-' || p.product_id || '-' || s.size_code || '-' || c.colour_code,
    s.size_label,
    c.colour_label,
    ROUND((p.base_price * (0.9 + random() * 0.4))::numeric, 2),
    floor(random() * 201)::int
FROM product p
CROSS JOIN (
    VALUES ('S','S'),('M','M'),('L','L'),('XL','XL'),('XXL','XXL')
) AS s(size_code, size_label)
CROSS JOIN (
    VALUES ('BLK','Black'),('BLU','Blue'),('RED','Red'),('WHT','White'),('GRN','Green')
) AS c(colour_code, colour_label)
-- pick exactly one colour per (product, size) using a deterministic filter
WHERE mod(p.product_id * 7 + (CASE s.size_code WHEN 'S' THEN 1 WHEN 'M' THEN 2 WHEN 'L' THEN 3 WHEN 'XL' THEN 4 ELSE 5 END), 5)
      = (CASE c.colour_code WHEN 'BLK' THEN 0 WHEN 'BLU' THEN 1 WHEN 'RED' THEN 2 WHEN 'WHT' THEN 3 ELSE 4 END);

-- -----------------------------------------------------------------------------
-- orders (100,000 rows)
-- Spread evenly across the last 365 days.
-- Status mix: ~54% delivered, ~15% shipped, ~12% processing, ~8% pending,
--             ~7% cancelled, ~2% paid, ~2% returned
-- We use a hash of n to get a pseudo-random value r in [0,1) per row.
-- -----------------------------------------------------------------------------
INSERT INTO orders (customer_id, address_id, order_date, status, total_amount)
SELECT
    1 + mod(n - 1, 10000),
    1 + mod(n - 1, 10000),
    now() - (random() * interval '365 days'),
    CASE
        WHEN r < 0.54 THEN 'delivered'
        WHEN r < 0.69 THEN 'shipped'
        WHEN r < 0.81 THEN 'processing'
        WHEN r < 0.89 THEN 'pending'
        WHEN r < 0.96 THEN 'cancelled'
        WHEN r < 0.98 THEN 'paid'
        ELSE 'returned'
    END,
    0.00
FROM generate_series(1, 100000) AS n,
     -- draw r from a stable hash of n so it varies per row
     LATERAL (SELECT (hashint4(n::int) & 2147483647)::float8 / 2147483647 AS r) AS rnd;

-- -----------------------------------------------------------------------------
-- order_item (~250,000 rows)
-- For each order, pick 1 to 4 distinct variants deterministically.
-- We generate (order_id, slot) pairs then map slot to a variant_id.
-- -----------------------------------------------------------------------------
INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
SELECT DISTINCT ON (os.order_id, pv.variant_id)
    os.order_id,
    pv.variant_id,
    1 + floor(random() * 3)::int,
    pv.price
FROM (
    -- generate up to 4 slots per order, capped by desired item count
    SELECT o.order_id, s.slot
    FROM orders o
    CROSS JOIN generate_series(1, 4) AS s(slot)
    WHERE s.slot <= 1 + mod(o.order_id * 3, 4)
) os
JOIN (SELECT variant_id, price, row_number() OVER () AS rn FROM product_variant) pv
  ON pv.rn = 1 + mod(os.order_id * (os.slot + 1) * 1009,
                     (SELECT count(*) FROM product_variant))
ORDER BY os.order_id, pv.variant_id;

-- -----------------------------------------------------------------------------
-- Fix orders.total_amount = sum of quantity * unit_price per order
-- -----------------------------------------------------------------------------
UPDATE orders o
SET total_amount = sub.total
FROM (
    SELECT order_id, SUM(quantity * unit_price) AS total
    FROM order_item
    GROUP BY order_id
) sub
WHERE o.order_id = sub.order_id;

-- -----------------------------------------------------------------------------
-- payment
-- Every order with status not 'pending' or 'cancelled' gets one successful payment.
-- About 5% of orders also get a prior failed card attempt.
-- -----------------------------------------------------------------------------

-- Successful payments
INSERT INTO payment (order_id, method, amount, status, reference, paid_at)
SELECT
    o.order_id,
    (ARRAY['card','bank_transfer','ussd','cash_on_delivery'])[1 + mod(o.order_id, 4)],
    o.total_amount,
    'successful',
    'PAY-' || lpad(o.order_id::text, 10, '0') || '-OK',
    o.order_date + interval '10 minutes'
FROM orders o
WHERE o.status NOT IN ('pending', 'cancelled');

-- Failed prior attempts on ~5% of paid orders
INSERT INTO payment (order_id, method, amount, status, reference, paid_at)
SELECT
    o.order_id,
    'card',
    o.total_amount,
    'failed',
    'PAY-' || lpad(o.order_id::text, 10, '0') || '-FAIL',
    o.order_date + interval '5 minutes'
FROM orders o
WHERE o.status NOT IN ('pending', 'cancelled')
  AND mod(o.order_id, 20) = 0;   -- every 20th paid order = 5%

-- -----------------------------------------------------------------------------
-- delivery
-- One delivery per order that is shipped or delivered.
-- rider_id: 1 to 50
-- -----------------------------------------------------------------------------
INSERT INTO delivery (order_id, rider_id, status, assigned_at, delivered_at, current_location)
SELECT
    o.order_id,
    1 + mod(o.order_id, 50),
    CASE o.status
        WHEN 'delivered' THEN 'delivered'
        WHEN 'shipped'   THEN 'in_transit'
    END,
    o.order_date + interval '1 hour',
    CASE o.status
        WHEN 'delivered' THEN o.order_date + interval '2 days'
        ELSE NULL
    END,
    CASE o.status
        WHEN 'shipped' THEN 'In transit - ' || (ARRAY['Lagos','Abuja','Kano','Ibadan','Port Harcourt'])[1 + mod(o.order_id, 5)]
        ELSE NULL
    END
FROM orders o
WHERE o.status IN ('shipped', 'delivered');

-- -----------------------------------------------------------------------------
-- return_request (~3,000 rows)
-- Pick order_items from delivered orders at random, about 1.2% of items.
-- -----------------------------------------------------------------------------
INSERT INTO return_request (order_item_id, staff_id, reason, status, refund_amount)
SELECT
    oi.order_item_id,
    1 + mod(oi.order_item_id, 10),  -- staff_id 1 to 10
    (ARRAY[
        'Wrong size delivered',
        'Item damaged on arrival',
        'Not as described',
        'Changed my mind',
        'Received wrong colour'
    ])[1 + mod(oi.order_item_id, 5)],
    (ARRAY['requested','approved','rejected','received','refunded'])[1 + mod(oi.order_item_id, 5)],
    ROUND((oi.unit_price * oi.quantity)::numeric, 2)
FROM order_item oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.status = 'delivered'
  AND mod(oi.order_item_id, 83) = 0;   -- ~1.2% of delivered items

-- -----------------------------------------------------------------------------
-- complaint (~2,000 rows)
-- -----------------------------------------------------------------------------
INSERT INTO complaint (customer_id, staff_id, subject, description, status)
SELECT
    1 + mod(n - 1, 10000),
    CASE WHEN random() > 0.3 THEN 1 + mod(n, 10) ELSE NULL END,
    (ARRAY[
        'Delivery delay',
        'Wrong item received',
        'Payment not confirmed',
        'Poor packaging',
        'Rider was rude',
        'Item out of stock after order',
        'Refund not processed'
    ])[1 + mod(n, 7)],
    'Complaint detail for issue ' || n,
    (ARRAY['open','in_progress','resolved','closed'])[1 + mod(n, 4)]
FROM generate_series(1, 2000) AS n;

-- -----------------------------------------------------------------------------
-- review (~20,000 rows, unique (customer_id, product_id))
-- Ratings skewed toward 4 and 5.
-- We generate pairs and deduplicate with DISTINCT ON.
-- -----------------------------------------------------------------------------
INSERT INTO review (customer_id, product_id, rating, comment)
SELECT DISTINCT ON (customer_id, product_id)
    customer_id,
    product_id,
    rating,
    'Review comment ' || customer_id || '-' || product_id
FROM (
    SELECT
        1 + mod(n * 97, 10000)  AS customer_id,
        1 + mod(n * 31, 1000)   AS product_id,
        -- skew: 1=4%, 2=8%, 3=13%, 4=30%, 5=45%
        CASE
            WHEN random() < 0.04 THEN 1
            WHEN random() < 0.12 THEN 2
            WHEN random() < 0.25 THEN 3
            WHEN random() < 0.55 THEN 4
            ELSE 5
        END AS rating
    FROM generate_series(1, 30000) AS n
) sub
ORDER BY customer_id, product_id;

-- -----------------------------------------------------------------------------
-- Refresh planner statistics
-- -----------------------------------------------------------------------------
ANALYZE;
