-- ThreadHaus schema
-- Course: MIT 8103 Advanced Database Systems, MIVA Open University
-- Case study: ThreadHaus, a simulated online clothing store
-- Database: PostgreSQL 16+
--
-- Re-runnable: DROP TABLE statements at the top clear everything before recreating.
-- I drop in reverse dependency order to avoid FK conflicts.

DROP TABLE IF EXISTS review            CASCADE;
DROP TABLE IF EXISTS complaint         CASCADE;
DROP TABLE IF EXISTS return_request    CASCADE;
DROP TABLE IF EXISTS delivery          CASCADE;
DROP TABLE IF EXISTS payment           CASCADE;
DROP TABLE IF EXISTS order_item        CASCADE;
DROP TABLE IF EXISTS orders            CASCADE;
DROP TABLE IF EXISTS product_variant   CASCADE;
DROP TABLE IF EXISTS product           CASCADE;
DROP TABLE IF EXISTS category          CASCADE;
DROP TABLE IF EXISTS address           CASCADE;
DROP TABLE IF EXISTS staff             CASCADE;
DROP TABLE IF EXISTS rider             CASCADE;
DROP TABLE IF EXISTS customer          CASCADE;

-- -----------------------------------------------------------------------------
-- customer
-- Soft delete via deleted_at so we keep order history after an account closes.
-- -----------------------------------------------------------------------------
CREATE TABLE customer (
    customer_id   BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     TEXT          NOT NULL,
    email         TEXT          NOT NULL,
    phone         TEXT          NOT NULL,
    password_hash TEXT          NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ,                          -- soft delete
    UNIQUE (email),
    UNIQUE (phone)
);

-- -----------------------------------------------------------------------------
-- address
-- Belongs to a customer. Cascades on delete so orphan addresses are removed
-- if a customer row is hard-deleted (soft delete keeps them in place).
-- -----------------------------------------------------------------------------
CREATE TABLE address (
    address_id  BIGINT   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT   NOT NULL REFERENCES customer (customer_id) ON DELETE CASCADE,
    street      TEXT     NOT NULL,
    city        TEXT     NOT NULL,
    state       TEXT     NOT NULL,
    is_default  BOOLEAN  NOT NULL DEFAULT false
);

-- -----------------------------------------------------------------------------
-- staff
-- Roles are fixed: admin, manager, support. Soft delete keeps audit trail.
-- -----------------------------------------------------------------------------
CREATE TABLE staff (
    staff_id      BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     TEXT         NOT NULL,
    email         TEXT         NOT NULL,
    password_hash TEXT         NOT NULL,
    role          TEXT         NOT NULL CHECK (role IN ('admin', 'manager', 'support')),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ,                          -- soft delete
    UNIQUE (email)
);

-- -----------------------------------------------------------------------------
-- rider
-- is_available flips when the rider is assigned to an active delivery.
-- Soft delete keeps delivery history intact.
-- -----------------------------------------------------------------------------
CREATE TABLE rider (
    rider_id     BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name    TEXT         NOT NULL,
    phone        TEXT         NOT NULL,
    is_available BOOLEAN      NOT NULL DEFAULT true,
    deleted_at   TIMESTAMPTZ,                          -- soft delete
    UNIQUE (phone)
);

-- -----------------------------------------------------------------------------
-- category
-- Self-referencing for sub-categories (parent_category_id is nullable for
-- top-level categories). Restrict delete so we don't orphan child categories.
-- -----------------------------------------------------------------------------
CREATE TABLE category (
    category_id        BIGINT   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_category_id BIGINT   REFERENCES category (category_id) ON DELETE RESTRICT,
    name               TEXT     NOT NULL,
    UNIQUE (name)
);

-- -----------------------------------------------------------------------------
-- product
-- base_price is the default/reference price; actual selling price lives on
-- product_variant. Soft delete keeps order history readable.
-- -----------------------------------------------------------------------------
CREATE TABLE product (
    product_id  BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id BIGINT        NOT NULL REFERENCES category (category_id) ON DELETE RESTRICT,
    name        TEXT          NOT NULL,
    description TEXT,
    brand       TEXT,
    base_price  NUMERIC(12,2) NOT NULL CHECK (base_price >= 0),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ                            -- soft delete
);

-- -----------------------------------------------------------------------------
-- product_variant
-- Each row is one SKU (size + colour combination). price >= 0 allows free items.
-- UNIQUE (product_id, size, colour) prevents duplicate variants.
-- Soft delete keeps sold variants visible in old order_item rows.
-- -----------------------------------------------------------------------------
CREATE TABLE product_variant (
    variant_id  BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id  BIGINT        NOT NULL REFERENCES product (product_id) ON DELETE RESTRICT,
    sku         TEXT          NOT NULL,
    size        TEXT          NOT NULL,
    colour      TEXT          NOT NULL,
    price       NUMERIC(12,2) NOT NULL CHECK (price >= 0),
    stock_qty   INTEGER       NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    deleted_at  TIMESTAMPTZ,                          -- soft delete
    UNIQUE (sku),
    UNIQUE (product_id, size, colour)
);

-- -----------------------------------------------------------------------------
-- orders
-- Uses quoted name because "order" is a reserved word in SQL.
-- total_amount is denormalised for quick reporting; kept in sync by app logic.
-- One address per order (the address at time of placing, not current default).
-- -----------------------------------------------------------------------------
CREATE TABLE orders (
    order_id     BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  BIGINT        NOT NULL REFERENCES customer (customer_id) ON DELETE RESTRICT,
    address_id   BIGINT        NOT NULL REFERENCES address  (address_id)  ON DELETE RESTRICT,
    order_date   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    status       TEXT          NOT NULL DEFAULT 'pending'
                               CHECK (status IN ('pending','paid','processing',
                                                 'shipped','delivered','cancelled','returned')),
    total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0)
);

-- -----------------------------------------------------------------------------
-- order_item
-- unit_price records what the customer actually paid at order time, so price
-- changes on product_variant do not rewrite history.
-- Cascades on delete: if an order is deleted, its items go with it.
-- UNIQUE (order_id, variant_id) prevents the same variant appearing twice on
-- the same order (app should merge quantities instead).
-- -----------------------------------------------------------------------------
CREATE TABLE order_item (
    order_item_id BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      BIGINT        NOT NULL REFERENCES orders          (order_id)  ON DELETE CASCADE,
    variant_id    BIGINT        NOT NULL REFERENCES product_variant (variant_id) ON DELETE RESTRICT,
    quantity      INTEGER       NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (order_id, variant_id)
);

-- -----------------------------------------------------------------------------
-- payment
-- An order can have many payments (e.g. failed attempt followed by success).
-- amount must be positive. reference is a gateway transaction ID; must be unique.
-- -----------------------------------------------------------------------------
CREATE TABLE payment (
    payment_id BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id   BIGINT        NOT NULL REFERENCES orders (order_id) ON DELETE RESTRICT,
    method     TEXT          NOT NULL CHECK (method IN ('card','bank_transfer','ussd','cash_on_delivery')),
    amount     NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    status     TEXT          NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending','successful','failed','refunded')),
    reference  TEXT,
    paid_at    TIMESTAMPTZ,
    UNIQUE (reference)
);

-- -----------------------------------------------------------------------------
-- delivery
-- One delivery per order (enforced by UNIQUE on order_id).
-- rider_id is nullable until a rider is assigned.
-- -----------------------------------------------------------------------------
CREATE TABLE delivery (
    delivery_id      BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id         BIGINT       NOT NULL REFERENCES orders (order_id) ON DELETE RESTRICT,
    rider_id         BIGINT       REFERENCES rider (rider_id) ON DELETE RESTRICT,  -- nullable
    status           TEXT         NOT NULL DEFAULT 'pending'
                                  CHECK (status IN ('pending','assigned','picked_up',
                                                    'in_transit','delivered','failed')),
    assigned_at      TIMESTAMPTZ,
    delivered_at     TIMESTAMPTZ,
    current_location TEXT,
    UNIQUE (order_id)
);

-- -----------------------------------------------------------------------------
-- return_request
-- Uses quoted name because "return" is a reserved word.
-- staff_id is nullable until support staff picks it up.
-- refund_amount is what will be / was refunded; must be >= 0.
-- -----------------------------------------------------------------------------
CREATE TABLE return_request (
    return_id     BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_item_id BIGINT        NOT NULL REFERENCES order_item (order_item_id) ON DELETE RESTRICT,
    staff_id      BIGINT        REFERENCES staff (staff_id) ON DELETE RESTRICT,   -- nullable
    reason        TEXT          NOT NULL,
    status        TEXT          NOT NULL DEFAULT 'requested'
                                CHECK (status IN ('requested','approved','rejected','received','refunded')),
    refund_amount NUMERIC(12,2) CHECK (refund_amount >= 0),
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- complaint
-- staff_id is nullable until assigned to a support agent.
-- -----------------------------------------------------------------------------
CREATE TABLE complaint (
    complaint_id BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id  BIGINT       NOT NULL REFERENCES customer (customer_id) ON DELETE RESTRICT,
    staff_id     BIGINT       REFERENCES staff (staff_id) ON DELETE RESTRICT,     -- nullable
    subject      TEXT         NOT NULL,
    description  TEXT         NOT NULL,
    status       TEXT         NOT NULL DEFAULT 'open'
                              CHECK (status IN ('open','in_progress','resolved','closed')),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- review
-- One review per customer per product (UNIQUE enforces this).
-- rating is 1–5 stars.
-- -----------------------------------------------------------------------------
CREATE TABLE review (
    review_id   BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT       NOT NULL REFERENCES customer (customer_id) ON DELETE RESTRICT,
    product_id  BIGINT       NOT NULL REFERENCES product  (product_id)  ON DELETE RESTRICT,
    rating      SMALLINT     NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment     TEXT,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    UNIQUE (customer_id, product_id)
);
