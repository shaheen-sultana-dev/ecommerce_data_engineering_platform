/*  Silver layer */

-- Step 1 — Creating the Silver schema and four tables

BEGIN;

-- 1. Create the Silver schema
CREATE SCHEMA IF NOT EXISTS silver;


-- 2. Create the four Silver tables

CREATE TABLE IF NOT EXISTS silver.customers (
    customer_id TEXT PRIMARY KEY,
    customer_name TEXT NOT NULL,
    email TEXT,
    city TEXT,
    state TEXT,
    created_at TIMESTAMP NOT NULL
);


CREATE TABLE IF NOT EXISTS silver.products (
    product_id TEXT PRIMARY KEY,
    product_name TEXT NOT NULL,
    category TEXT,
    unit_price NUMERIC(12,2) NOT NULL,
    updated_at TIMESTAMP NOT NULL
);


CREATE TABLE IF NOT EXISTS silver.orders (
    order_id TEXT PRIMARY KEY,
    customer_id TEXT NOT NULL,
    order_ts TIMESTAMP NOT NULL,
    order_status TEXT NOT NULL,
    payment_method TEXT,
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES silver.customers(customer_id)
);


CREATE TABLE IF NOT EXISTS silver.order_items (
    order_item_id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL,
    discount_amount NUMERIC(12,2) NOT NULL,
    CONSTRAINT fk_items_order
        FOREIGN KEY (order_id)
        REFERENCES silver.orders(order_id),
    CONSTRAINT fk_items_product
        FOREIGN KEY (product_id)
        REFERENCES silver.products(product_id)
);


-- 3. Clear previous Silver data for a clean reload

TRUNCATE TABLE
    silver.order_items,
    silver.orders,
    silver.products,
    silver.customers
CASCADE;


-- 4. Transform customers

INSERT INTO silver.customers
SELECT
    NULLIF(BTRIM(customer_id), ''),
    NULLIF(BTRIM(customer_name), ''),
    LOWER(NULLIF(BTRIM(email), '')),
    NULLIF(BTRIM(city), ''),
    NULLIF(BTRIM(state), ''),
    NULLIF(BTRIM(created_at), '')::TIMESTAMP
FROM staging.customers_raw;


-- 5. Transform products

INSERT INTO silver.products
SELECT
    NULLIF(BTRIM(product_id), ''),
    NULLIF(BTRIM(product_name), ''),
    NULLIF(BTRIM(category), ''),
    NULLIF(BTRIM(unit_price), '')::NUMERIC(12,2),
    NULLIF(BTRIM(updated_at), '')::TIMESTAMP
FROM staging.products_raw;


-- 6. Transform orders

INSERT INTO silver.orders
SELECT
    NULLIF(BTRIM(order_id), ''),
    NULLIF(BTRIM(customer_id), ''),
    NULLIF(BTRIM(order_ts), '')::TIMESTAMP,
    LOWER(NULLIF(BTRIM(order_status), '')),
    UPPER(NULLIF(BTRIM(payment_method), ''))
FROM staging.orders_raw;


-- 7. Transform order items

INSERT INTO silver.order_items
SELECT
    NULLIF(BTRIM(order_item_id), ''),
    NULLIF(BTRIM(order_id), ''),
    NULLIF(BTRIM(product_id), ''),
    NULLIF(BTRIM(quantity), '')::INTEGER,
    NULLIF(BTRIM(unit_price), '')::NUMERIC(12,2),
    NULLIF(BTRIM(discount_amount), '')::NUMERIC(12,2)
FROM staging.order_items_raw;


COMMIT;


--Verify Silver:

SELECT 'customers' AS dataset, COUNT(*) AS total
FROM silver.customers

UNION ALL

SELECT 'products', COUNT(*)
FROM silver.products

UNION ALL

SELECT 'orders', COUNT(*)
FROM silver.orders

UNION ALL

SELECT 'order_items', COUNT(*)
FROM silver.order_items;



-- running to verify that the missing email was preserved:

SELECT customer_id, customer_name, email
FROM silver.customers
WHERE email IS NULL;
 
/* creating the remaining silver tables */
-- 1. silver.supplier_inventory
-- 2. silver.external_api_products
-- 3. silver.order_events


-- Create the tables:

BEGIN;

-- Supplier inventory (csv data)
CREATE TABLE IF NOT EXISTS silver.supplier_inventory (
    supplier_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    supplier_name TEXT NOT NULL,
    available_quantity INTEGER NOT NULL
        CHECK (available_quantity >= 0),
    unit_cost NUMERIC(12,2) NOT NULL
        CHECK (unit_cost >= 0),
    last_updated DATE NOT NULL,

    PRIMARY KEY (supplier_id, product_id),

    FOREIGN KEY (product_id)
        REFERENCES silver.products(product_id)
);


-- Products received from the external API
CREATE TABLE IF NOT EXISTS silver.external_api_products (
    external_product_id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    category TEXT,
    brand TEXT,
    sku TEXT,
    price NUMERIC(12,2),
    discount_percentage NUMERIC(5,2),
    rating NUMERIC(3,2),
    stock INTEGER,
    availability_status TEXT,
    source_url TEXT
);


-- Streaming order events
CREATE TABLE IF NOT EXISTS silver.order_events (
    event_id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    order_id TEXT NOT NULL,
    customer_id TEXT NOT NULL,
    amount NUMERIC(14,2) NOT NULL
        CHECK (amount >= 0),
    event_timestamp TIMESTAMP NOT NULL,
    source_file TEXT,

    FOREIGN KEY (order_id)
        REFERENCES silver.orders(order_id),

    FOREIGN KEY (customer_id)
        REFERENCES silver.customers(customer_id)
);

COMMIT;



-- Transform the three datasets

BEGIN;

-- Clear previous records for repeatable loading
TRUNCATE TABLE
    silver.order_events,
    silver.external_api_products,
    silver.supplier_inventory;


-- 1. Supplier inventory transformation

INSERT INTO silver.supplier_inventory
SELECT
    NULLIF(BTRIM(supplier_id), ''),
    NULLIF(BTRIM(product_id), ''),
    NULLIF(BTRIM(supplier_name), ''),
    NULLIF(BTRIM(available_quantity), '')::INTEGER,
    NULLIF(BTRIM(unit_cost), '')::NUMERIC(12,2),
    NULLIF(BTRIM(last_updated), '')::DATE
FROM staging.supplier_inventory_raw;


-- 2. Extract individual products from the API JSON

INSERT INTO silver.external_api_products (
    external_product_id,
    title,
    category,
    brand,
    sku,
    price,
    discount_percentage,
    rating,
    stock,
    availability_status,
    source_url
)
SELECT
    (p.item ->> 'id')::INTEGER,
    NULLIF(BTRIM(p.item ->> 'title'), ''),
    NULLIF(BTRIM(p.item ->> 'category'), ''),
    NULLIF(BTRIM(p.item ->> 'brand'), ''),
    NULLIF(BTRIM(p.item ->> 'sku'), ''),
    (p.item ->> 'price')::NUMERIC(12,2),
    (p.item ->> 'discountPercentage')::NUMERIC(5,2),
    (p.item ->> 'rating')::NUMERIC(3,2),
    (p.item ->> 'stock')::INTEGER,
    NULLIF(BTRIM(p.item ->> 'availabilityStatus'), ''),
    a.source_url
FROM staging.api_products_raw AS a
CROSS JOIN LATERAL
    jsonb_array_elements(a.raw_payload -> 'products') AS p(item);


-- 3. Deduplicate and transform streaming events

WITH ranked_events AS (
    SELECT
        NULLIF(BTRIM(event_id), '') AS event_id,
        NULLIF(BTRIM(event_type), '') AS event_type,
        NULLIF(BTRIM(order_id), '') AS order_id,
        NULLIF(BTRIM(customer_id), '') AS customer_id,
        NULLIF(BTRIM(amount), '')::NUMERIC(14,2) AS amount,
        NULLIF(BTRIM(event_timestamp), '')::TIMESTAMP
            AS event_timestamp,
        source_file,

        ROW_NUMBER() OVER (
            PARTITION BY NULLIF(BTRIM(event_id), '')
            ORDER BY ingested_at DESC, source_file DESC
        ) AS row_num

    FROM staging.order_events_raw
)

INSERT INTO silver.order_events (
    event_id,
    event_type,
    order_id,
    customer_id,
    amount,
    event_timestamp,
    source_file
)
SELECT
    event_id,
    event_type,
    order_id,
    customer_id,
    amount,
    event_timestamp,
    source_file
FROM ranked_events
WHERE row_num = 1;

COMMIT;


-- Verify the results

SELECT 'supplier_inventory' AS dataset, COUNT(*) AS total
FROM silver.supplier_inventory

UNION ALL

SELECT 'external_api_products', COUNT(*)
FROM silver.external_api_products

UNION ALL

SELECT 'order_events', COUNT(*)
FROM silver.order_events;



-- inspect the actual records:

SELECT * FROM silver.supplier_inventory;

SELECT * FROM silver.external_api_products;

SELECT * FROM silver.order_events;
