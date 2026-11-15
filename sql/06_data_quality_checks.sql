/* Data Quality Checks */

-- Check A — Missing mandatory values:

SELECT 'customers' AS dataset,
       COUNT(*) AS invalid_records
FROM silver.customers
WHERE customer_id IS NULL
   OR customer_name IS NULL
   OR created_at IS NULL

UNION ALL

SELECT 'products',
       COUNT(*)
FROM silver.products
WHERE product_id IS NULL
   OR product_name IS NULL
   OR unit_price IS NULL
   OR unit_price < 0

UNION ALL

SELECT 'orders',
       COUNT(*)
FROM silver.orders
WHERE order_id IS NULL
   OR customer_id IS NULL
   OR order_ts IS NULL
   OR order_status IS NULL

UNION ALL

SELECT 'order_items',
       COUNT(*)
FROM silver.order_items
WHERE order_item_id IS NULL
   OR order_id IS NULL
   OR product_id IS NULL
   OR quantity IS NULL
   OR quantity <= 0
   OR unit_price < 0
   OR discount_amount < 0;

-- Expected: zero invalid records in each dataset.
-- Notice that we have deliberately not flagged missing customer emails as invalid,
-- -- because email is optional in our current data model.
-----------------------------------------------------------------------------------------------------------------------------------------

-- Check B — Duplicate streaming events:

SELECT
    event_id,
    COUNT(*) AS occurrences
FROM staging.order_events_raw
GROUP BY event_id
HAVING COUNT(*) > 1;

-- Expected: zero rows.
-- Our source currently has five unique events.
-- The Silver transformation nevertheless protects against repeated delivery of the same event ID.

-----------------------------------------------------------------------------------------------------------------------------------------------
-- Check C — Verify revenue between Silver and Gold:

WITH silver_revenue AS (

    SELECT
        SUM(oi.quantity * oi.unit_price) AS gross_sales,
        SUM(oi.discount_amount) AS discounts,
        SUM(
            oi.quantity * oi.unit_price
            - oi.discount_amount
        ) AS net_sales

    FROM silver.order_items oi

    JOIN silver.orders o
        ON oi.order_id = o.order_id

    WHERE LOWER(o.order_status) = 'completed'
),

gold_revenue AS (

    SELECT
        SUM(gross_sales) AS gross_sales,
        SUM(discount_amount) AS discounts,
        SUM(net_sales) AS net_sales

    FROM gold.fact_sales
)

SELECT
    s.gross_sales AS silver_gross,
    g.gross_sales AS gold_gross,

    s.discounts AS silver_discounts,
    g.discounts AS gold_discounts,

    s.net_sales AS silver_net,
    g.net_sales AS gold_net

FROM silver_revenue s
CROSS JOIN gold_revenue g;


-- Expected: both silver and gold sides should match:
-- - Gross: ₹61,200
-- - Discounts: ₹350
-- - Net: ₹60,850