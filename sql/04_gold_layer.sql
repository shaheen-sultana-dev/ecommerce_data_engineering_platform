/* Gold Layer */

-- Creating the Gold tables:

CREATE SCHEMA IF NOT EXISTS gold;


-- 1. Date dimension
CREATE TABLE IF NOT EXISTS gold.dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE UNIQUE NOT NULL,
    day_number INTEGER,
    month_number INTEGER,
    month_name TEXT,
    quarter_number INTEGER,
    year_number INTEGER
);


-- 2. Customer dimension
CREATE TABLE IF NOT EXISTS gold.dim_customer (
    customer_id TEXT PRIMARY KEY,
    customer_name TEXT,
    email TEXT,
    city TEXT,
    state TEXT
);


-- 3. Product dimension
CREATE TABLE IF NOT EXISTS gold.dim_product (
    product_id TEXT PRIMARY KEY,
    product_name TEXT,
    category TEXT,
    unit_price NUMERIC(12,2)
);


-- 4. Payment method dimension
CREATE TABLE IF NOT EXISTS gold.dim_payment_method (
    payment_method_key SERIAL PRIMARY KEY,
    payment_method TEXT UNIQUE NOT NULL
);


-- 5. Sales fact table
CREATE TABLE IF NOT EXISTS gold.fact_sales (
    order_item_id TEXT PRIMARY KEY,
    order_id TEXT NOT NULL,

    date_key INTEGER NOT NULL,
    customer_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    payment_method_key INTEGER NOT NULL,

    quantity INTEGER NOT NULL,
    unit_price NUMERIC(12,2) NOT NULL,
    discount_amount NUMERIC(12,2) NOT NULL,

    gross_sales NUMERIC(14,2) NOT NULL,
    net_sales NUMERIC(14,2) NOT NULL,

    FOREIGN KEY (date_key)
        REFERENCES gold.dim_date(date_key),

    FOREIGN KEY (customer_id)
        REFERENCES gold.dim_customer(customer_id),

    FOREIGN KEY (product_id)
        REFERENCES gold.dim_product(product_id),

    FOREIGN KEY (payment_method_key)
        REFERENCES gold.dim_payment_method(payment_method_key)
);




-- Populate the dimensions and fact table (moving the data from Silver into Gold.):

BEGIN;

-- Clearing previous Gold records in dependency order
DELETE FROM gold.fact_sales;
DELETE FROM gold.dim_payment_method;
DELETE FROM gold.dim_product;
DELETE FROM gold.dim_customer;
DELETE FROM gold.dim_date;


-- 1. Populate date dimension

INSERT INTO gold.dim_date (
    date_key,
    full_date,
    day_number,
    month_number,
    month_name,
    quarter_number,
    year_number
)
SELECT DISTINCT
    TO_CHAR(order_ts::DATE, 'YYYYMMDD')::INTEGER,
    order_ts::DATE,
    EXTRACT(DAY FROM order_ts)::INTEGER,
    EXTRACT(MONTH FROM order_ts)::INTEGER,
    TO_CHAR(order_ts, 'Month'),
    EXTRACT(QUARTER FROM order_ts)::INTEGER,
    EXTRACT(YEAR FROM order_ts)::INTEGER
FROM silver.orders;


-- 2. Populate customer dimension

INSERT INTO gold.dim_customer
SELECT
    customer_id,
    customer_name,
    email,
    city,
    state
FROM silver.customers;


-- 3. Populate product dimension

INSERT INTO gold.dim_product
SELECT
    product_id,
    product_name,
    category,
    unit_price
FROM silver.products;


-- 4. Populate payment method dimension

INSERT INTO gold.dim_payment_method (payment_method)
SELECT DISTINCT payment_method
FROM silver.orders
WHERE LOWER(order_status) = 'completed'
  AND payment_method IS NOT NULL;


-- 5. Populate sales fact table

INSERT INTO gold.fact_sales (
    order_item_id,
    order_id,
    date_key,
    customer_id,
    product_id,
    payment_method_key,
    quantity,
    unit_price,
    discount_amount,
    gross_sales,
    net_sales
)
SELECT
    oi.order_item_id,
    o.order_id,

    TO_CHAR(o.order_ts::DATE, 'YYYYMMDD')::INTEGER,

    o.customer_id,
    oi.product_id,
    pm.payment_method_key,

    oi.quantity,
    oi.unit_price,
    oi.discount_amount,

    (oi.quantity * oi.unit_price),

    (oi.quantity * oi.unit_price - oi.discount_amount)

FROM silver.order_items oi

JOIN silver.orders o
    ON oi.order_id = o.order_id

JOIN gold.dim_payment_method pm
    ON o.payment_method = pm.payment_method

WHERE LOWER(o.order_status) = 'completed';


COMMIT;




-- verifying six fact rows
select 
    count(*) as total_order_items,
    count(*) filter (
        where lower(o.order_status)='completed'
	) as completed_order_items,
	count(*) filter (
        where lower(o.order_status)<>'completed'
	) as non_completed_order_items
from silver.order_items oi	
join silver.orders o
    on oi.order_id=o.order_id;

-- checking fact table	
select
    order_id,
    count(*) as order_items,
    sum(gross_sales) as gross_sales,
    sum(discount_amount) as discounts,
    sum(net_sales) as net_sales
from gold.fact_sales
group by order_id
order by order_id;




-- Verifying Gold

SELECT 'dim_date' AS table_name, COUNT(*) AS total
FROM gold.dim_date

UNION ALL

SELECT 'dim_customer', COUNT(*)
FROM gold.dim_customer

UNION ALL

SELECT 'dim_product', COUNT(*)
FROM gold.dim_product

UNION ALL

SELECT 'dim_payment_method', COUNT(*)
FROM gold.dim_payment_method

UNION ALL

SELECT 'fact_sales', COUNT(*)
FROM gold.fact_sales;




-- inspecting the fact table:

SELECT *
FROM gold.fact_sales
ORDER BY order_id, order_item_id;

-- And checking the revenue:

SELECT
    SUM(gross_sales) AS total_gross_sales,
    SUM(discount_amount) AS total_discounts,
    SUM(net_sales) AS total_net_sales
FROM gold.fact_sales;