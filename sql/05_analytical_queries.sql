/* Analytics Queries */

-- Monthly sales by product category
-- Business question: How much revenue does each product category generate every month?

-- QUERY 1: Monthly sales by product category

WITH monthly_category_sales AS (

    SELECT
        d.year_number,
        d.month_number,
        p.category,

        COUNT(DISTINCT f.order_id) AS total_orders,
        SUM(f.quantity) AS units_sold,
        SUM(f.gross_sales) AS gross_sales,
        SUM(f.discount_amount) AS total_discounts,
        SUM(f.net_sales) AS net_sales

    FROM gold.fact_sales f

    JOIN gold.dim_date d
        ON f.date_key = d.date_key

    JOIN gold.dim_product p
        ON f.product_id = p.product_id

    GROUP BY
        d.year_number,
        d.month_number,
        p.category
)

SELECT
    year_number,
    TO_CHAR(
        MAKE_DATE(year_number, month_number, 1),
        'Mon YYYY'
    ) AS sales_month,
    category,
    total_orders,
    units_sold,
    gross_sales,
    total_discounts,
    net_sales

FROM monthly_category_sales

ORDER BY
    year_number,
    month_number,
    net_sales DESC;




-- Top 3 products by sales in each month
-- Business question: Which three products generated the highest revenue in each month?

-- QUERY 2: Top 3 products in each month

WITH product_month_sales AS (

    SELECT
        d.year_number,
        d.month_number,
        p.product_id,
        p.product_name,
        p.category,

        SUM(f.net_sales) AS monthly_net_sales,
        SUM(f.quantity) AS units_sold

    FROM gold.fact_sales f

    JOIN gold.dim_date d
        ON f.date_key = d.date_key

    JOIN gold.dim_product p
        ON f.product_id = p.product_id

    GROUP BY
        d.year_number,
        d.month_number,
        p.product_id,
        p.product_name,
        p.category
),

ranked_products AS (

    SELECT
        *,

        ROW_NUMBER() OVER (
            PARTITION BY year_number, month_number
            ORDER BY monthly_net_sales DESC, product_id
        ) AS product_rank

    FROM product_month_sales
)

SELECT
    year_number,
    month_number,
    product_rank,
    product_id,
    product_name,
    category,
    monthly_net_sales,
    units_sold

FROM ranked_products

WHERE product_rank <= 3

ORDER BY
    year_number,
    month_number,
    product_rank;



-- Customer sales ranking and cumulative revenue
-- Business question: Who are our highest-value customers, 
-- -- and how much revenue have we accumulated as we move down the customer ranking?

-- QUERY 3: Customer ranking and cumulative revenue

WITH customer_sales AS (

    SELECT
        c.customer_id,
        c.customer_name,
        c.city,
        c.state,

        COUNT(DISTINCT f.order_id) AS completed_orders,

        SUM(f.net_sales) AS total_net_sales

    FROM gold.fact_sales f

    JOIN gold.dim_customer c
        ON f.customer_id = c.customer_id

    GROUP BY
        c.customer_id,
        c.customer_name,
        c.city,
        c.state
),

customer_metrics AS (

    SELECT
        *,

        DENSE_RANK() OVER (
            ORDER BY total_net_sales DESC
        ) AS sales_rank,

        SUM(total_net_sales) OVER (
            ORDER BY total_net_sales DESC, customer_id
            ROWS BETWEEN UNBOUNDED PRECEDING
            AND CURRENT ROW
        ) AS cumulative_sales

    FROM customer_sales
)

SELECT
    customer_id,
    customer_name,
    city,
    state,
    completed_orders,
    total_net_sales,
    sales_rank,
    cumulative_sales,

    ROUND(
        100.0 * total_net_sales /
        NULLIF(SUM(total_net_sales) OVER (), 0),
        2
    ) AS revenue_contribution_percentage

FROM customer_metrics

ORDER BY sales_rank, customer_id;