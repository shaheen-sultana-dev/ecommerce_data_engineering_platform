/* 1. Data Quality */

-- checking row counts in each table
select 'customers' as table_name, count(*) as total_rows
from source.customers

union all

select 'products', count(*)
from source.products

union all

select 'orders', count(*)
from source.orders

union all

select 'order_items', count(*)
from source.order_items;


--checking duplicate primary IDs
select 'customers' as table_name, customer_id as record_id, count(*) as occurrences
from source.customers
group by customer_id
having count(*)>1

union all

select 'products', product_id, count(*)
from source.products
group by product_id
having count(*)>1

union all

select 'orders', order_id, count(*)
from source.orders
group by order_id
having count(*)>1

union all

select 'order_items', order_item_id, count(*)
from source.order_items
group by order_item_id
having count(*)>1;

-- checking missing values
select 
    'customers' as table_name,
	count(*) filter (where customer_id is null) as missing_id,
	count(*) filter (where customer_name is null or trim(customer_name)='') as missing_name,
	count(*) filter (where email is null or trim(email)='') as missing_email   -- 1 missing email found (of C003 customer) but wont reject customer for missing an email
from source.customers

union all

select 
    'products',
	count(*) filter (where product_id is null),
	count(*) filter (where product_name is null or trim(product_name)=''),
	count(*) filter (where category is null or trim(category)='')
from source.products

union all

select 
    'orders',
	count(*) filter (where order_id is null),
	count(*) filter (where customer_id is null),
	count(*) filter (where order_ts is null)
from source.orders

union all

select 
    'order_items',
	count(*) filter (where order_item_id is null),
	count(*) filter (where order_id is null),
	count(*) filter (where product_id is null)
from source.order_items;


/* checking invalid numeric values*/
-- 1. invalid product prices
select * 
from source.products
where unit_price<0;

-- 2. invalid order item quantities or prices
select *
from source.order_items
where quantity<=0
    or unit_price<0
	or discount_amount<0
	or discount_amount>(quantity * unit_price);

/* check broken relationships */
-- 1. orders without a matching customer
select o.*
from source.orders o
left join source.customers c
    on o.customer_id = c.customer_id
where c.customer_id is null;	

-- 2. order items without a matching order
select oi.*
from source.order_items oi
left join source.orders o
    on oi.order_id=o.order_id
where o.order_id is null;	

-- 3. order items without a matching product 
select oi.*
from source.order_items oi
left join source.products p
    on oi.product_id=p.product_id
where p.product_id is null;	




/* 2. Preparing PostgreSQL staging tables */
create schema if not exists staging;

-- supplier CSV data
create table if not exists staging.supplier_inventory_raw (
    supplier_id TEXT,
	product_id TEXT,
	supplier_name TEXT,
	available_quantity TEXT,
	unit_cost TEXT,
	last_updated TEXT,
	ingested_at TIMESTAMP default CURRENT_TIMESTAMP
);

-- api products data
create table if not exists staging.api_products_raw (
    raw_payload JSONB not null,
	source_url TEXT,
	ingested_at TIMESTAMP default CURRENT_TIMESTAMP
);

-- stream order events data
create table if not exists staging.order_events_raw (
    event_id TEXT,
	event_type TEXT,
	order_id TEXT,
	available_quantity TEXT,
	customer_id TEXT,
	amount TEXT,
	event_timestamp TEXT,
	source_file TEXT,
	ingested_at TIMESTAMP default CURRENT_TIMESTAMP
);


-- postgresql database data
create table if not exists staging.customers_raw (
    customer_id TEXT,
	customer_name TEXT,
	order_id TEXT,
	email TEXT,
	city TEXT,
	state TEXT,
	created_at TEXT,
	ingested_at TIMESTAMP default CURRENT_TIMESTAMP
);


create table if not exists staging.products_raw (
    product_id TEXT,
	product_name TEXT,
	category TEXT,
	unit_price TEXT,
	updated_at TEXT,
	ingested_at TIMESTAMP default CURRENT_TIMESTAMP
);

create table if not exists staging.orders_raw (
    order_id TEXT,
	customer_id TEXT,
	order_ts TEXT,
	order_status TEXT,
	payment_method TEXT,
	ingested_at TIMESTAMP default CURRENT_TIMESTAMP
);

create table if not exists staging.order_items_raw (
    order_item_id TEXT,
	order_id TEXT,
	product_id TEXT,
	quantity TEXT,
	unit_price TEXT,
	discount_amount TEXT,
	ingested_at TIMESTAMP default CURRENT_TIMESTAMP
);



-- verifying the staging data after running code in load_staging.py on vscode
SELECT 'customers' AS dataset, COUNT(*) AS total
FROM staging.customers_raw

UNION ALL

SELECT 'products', COUNT(*)
FROM staging.products_raw

UNION ALL

SELECT 'orders', COUNT(*)
FROM staging.orders_raw

UNION ALL

SELECT 'order_items', COUNT(*)
FROM staging.order_items_raw

UNION ALL

SELECT 'supplier_inventory', COUNT(*)
FROM staging.supplier_inventory_raw

UNION ALL

SELECT 'api_products', COUNT(*)
FROM staging.api_products_raw

UNION ALL

SELECT 'order_events', COUNT(*)
FROM staging.order_events_raw;