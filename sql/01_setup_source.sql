-- E-Commerce Data Engineering Platform Prototype
-- Step 1: create logical schemas and a small PostgreSQL operational source.

CREATE SCHEMA IF NOT EXISTS source;
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

-- Operational source tables (representing the e-commerce application's RDBMS).
CREATE TABLE IF NOT EXISTS source.customers (
    customer_id   VARCHAR(20) PRIMARY KEY,
    customer_name VARCHAR(100) NOT NULL,
    email         VARCHAR(150),
    city          VARCHAR(80),
    state         VARCHAR(80),
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS source.products (
    product_id   VARCHAR(20) PRIMARY KEY,
    product_name VARCHAR(120) NOT NULL,
    category     VARCHAR(80) NOT NULL,
    unit_price   NUMERIC(12,2) NOT NULL,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS source.orders (
    order_id      VARCHAR(30) PRIMARY KEY,
    customer_id   VARCHAR(20) NOT NULL REFERENCES source.customers(customer_id),
    order_ts      TIMESTAMP NOT NULL,
    order_status  VARCHAR(30) NOT NULL,
    payment_method VARCHAR(30)
);

-- Grain: one row per product line within an order.
CREATE TABLE IF NOT EXISTS source.order_items (
    order_item_id  VARCHAR(30) PRIMARY KEY,
    order_id       VARCHAR(30) NOT NULL REFERENCES source.orders(order_id),
    product_id     VARCHAR(20) NOT NULL REFERENCES source.products(product_id),
    quantity       INTEGER NOT NULL,
    unit_price     NUMERIC(12,2) NOT NULL,
    discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0
);

-- Small, fictional sample data. ON CONFLICT makes this script safe to rerun.
INSERT INTO source.customers
    (customer_id, customer_name, email, city, state)
VALUES
    ('C001', 'Asha Rao',   'asha@example.com',   'Bengaluru', 'Karnataka'),
    ('C002', 'Rahul Shah', 'rahul@example.com',  'Mumbai',    'Maharashtra'),
    ('C003', 'Meera Khan', NULL,                 'Hyderabad', 'Telangana'),
    ('C004', 'Dev Patel',  'dev@example.com',    'Pune',      'Maharashtra'),
    ('C005', 'Sara Ali',   'sara@example.com',   'Raichur',   'Karnataka')
ON CONFLICT (customer_id) DO NOTHING;

INSERT INTO source.products
    (product_id, product_name, category, unit_price)
VALUES
    ('P001', 'Laptop',       'Electronics', 50000.00),
    ('P002', 'Wireless Mouse','Accessories',   500.00),
    ('P003', 'Keyboard',     'Accessories',  1200.00),
    ('P004', 'Headphones',   'Electronics',  2500.00),
    ('P005', 'Office Chair', 'Furniture',    7500.00)
ON CONFLICT (product_id) DO NOTHING;

INSERT INTO source.orders
    (order_id, customer_id, order_ts, order_status, payment_method)
VALUES
    ('O1001', 'C001', '2026-11-10 09:15:00', 'completed', 'UPI'),
    ('O1002', 'C002', '2026-11-10 11:30:00', 'completed', 'Card'),
    ('O1003', 'C003', '2026-11-11 14:05:00', 'completed', 'UPI'),
    ('O1004', 'C001', '2026-11-12 16:20:00', 'cancelled', 'Card'),
    ('O1005', 'C004', '2026-11-12 18:45:00', 'completed', 'NetBanking'),
    ('O1006', 'C005', '2026-11-13 10:10:00', 'completed', 'UPI')
ON CONFLICT (order_id) DO NOTHING;

INSERT INTO source.order_items
    (order_item_id, order_id, product_id, quantity, unit_price, discount_amount)
VALUES
    ('OI001', 'O1001', 'P001', 1, 50000.00, 0.00),
    ('OI002', 'O1001', 'P002', 2,   500.00, 50.00),
    ('OI003', 'O1002', 'P004', 1,  2500.00, 0.00),
    ('OI004', 'O1003', 'P003', 1,  1200.00, 100.00),
    ('OI005', 'O1004', 'P005', 1,  7500.00, 0.00),
    ('OI006', 'O1005', 'P002', 3,   500.00, 0.00),
    ('OI007', 'O1006', 'P004', 2,  2500.00, 200.00)
ON CONFLICT (order_item_id) DO NOTHING;

-- Quick checks: these should return 5 customers, 5 products, 6 orders, 7 order lines.
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM source.customers
UNION ALL
SELECT 'products', COUNT(*) FROM source.products
UNION ALL
SELECT 'orders', COUNT(*) FROM source.orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM source.order_items;

-- Preview the operational order data through joins.
SELECT
    o.order_id,
    o.order_ts,
    c.customer_name,
    p.product_name,
    oi.quantity,
    oi.unit_price,
    oi.discount_amount,
    (oi.quantity * oi.unit_price - oi.discount_amount) AS line_net_sales,
    o.order_status
FROM source.orders AS o
JOIN source.customers AS c ON c.customer_id = o.customer_id
JOIN source.order_items AS oi ON oi.order_id = o.order_id
JOIN source.products AS p ON p.product_id = oi.product_id
ORDER BY o.order_ts, o.order_id, oi.order_item_id;
