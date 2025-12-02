/*
KPIs: 
- Total Sales: Total value and quantity of orders placed. [Done]
- Growth Rate: Month-over-month or quarter-over-quarter sales growth. [Done] 
- Average Order Value: Average ₹ per transaction. [Done]
- Revenue by Product Line:Revenue contribution per product category.[Done] 
- Repeat Purchase Rate: % of returning buyers. [Done]
*/
/*----------------------------------------------------------------
1. TOTAL SALES | UNITS SOLD | AVG ORDER VALUE | REPEAT PURCHASE RATE
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        NULL::TEXT[] AS category_filter,
        NULL::TEXT[] AS channel_filter
),

product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),

-- Calculate order-level sales metrics
order_level AS (
    SELECT 
        pi.po_id,
        SUM(pi.total_amount) AS order_total,
        SUM(pi.qty) AS total_qty
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pi.created_date BETWEEN p.start_date AND p.end_date
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
    GROUP BY pi.po_id
),

-- Calculate sales aggregates
sales_metrics AS (
    SELECT 
        ROUND(SUM(order_total)::numeric, 2) AS total_sales,
        ROUND(SUM(total_qty)::numeric, 2) AS units_sold,
        ROUND(SUM(order_total)::numeric / NULLIF(COUNT(po_id), 0), 2) AS average_order_value
    FROM order_level
),

-- Get distinct orders per buyer for repeat purchase calculation
base_orders AS (
    SELECT DISTINCT
        pd.buyer_org_id AS buyer_id,
        pd.id AS po_id
    FROM po_details pd
    JOIN po_items pi ON pd.id = pi.po_id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND pd.buyer_org_id IS NOT NULL
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
),

-- Count orders per buyer
buyer_order_counts AS (
    SELECT 
        buyer_id,
        COUNT(DISTINCT po_id) AS order_count
    FROM base_orders
    GROUP BY buyer_id
),

-- Calculate repeat purchase stats
repeat_purchase_metrics AS (
    SELECT
        COUNT(DISTINCT buyer_id) AS total_buyers,
        COUNT(DISTINCT CASE WHEN order_count > 1 THEN buyer_id END) AS repeat_buyers,
        ROUND(
            (COUNT(DISTINCT CASE WHEN order_count > 1 THEN buyer_id END)::numeric 
             / NULLIF(COUNT(DISTINCT buyer_id), 0)) * 100, 
            2
        ) AS repeat_purchase_rate_pct
    FROM buyer_order_counts
)

-- Final output combining all metrics
SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    sm.total_sales,
    sm.units_sold,
    sm.average_order_value,
    rpm.total_buyers,
    rpm.repeat_buyers,
    rpm.repeat_purchase_rate_pct
FROM sales_metrics sm
CROSS JOIN repeat_purchase_metrics rpm;

/*-----------------------------------------
 2. MOM GROWTH RATE
-----------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        NULL::TEXT[] AS category_filter,
        NULL::TEXT[] AS channel_filter
),

month_series AS (
    SELECT generate_series(
        date_trunc('month', (SELECT start_date FROM params)),
        date_trunc('month', (SELECT end_date FROM params)),
        interval '1 month'
    ) AS month
),

product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),

monthly_sales AS (
    SELECT 
        date_trunc('month', pi.created_date) AS month,
        SUM(pi.total_amount) AS total_sales,
        SUM(pi.qty) AS total_units,
        COUNT(DISTINCT pi.po_id) AS order_count
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pi.created_date BETWEEN p.start_date AND p.end_date
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
    GROUP BY date_trunc('month', pi.created_date)
)

SELECT
    (SELECT vendor_id FROM params) AS vendor_id,
    TO_CHAR(ms.month, 'YYYY-MM') AS month,
    COALESCE(ROUND(msl.total_sales::numeric, 2), 0) AS total_sales,
    COALESCE(ROUND(msl.total_units::numeric, 2), 0) AS total_units,
    COALESCE(msl.order_count, 0) AS order_count,
    COALESCE(ROUND(LAG(msl.total_sales) OVER (ORDER BY ms.month)::numeric, 2), 0) AS prev_month_sales,
    CASE
        WHEN LAG(msl.total_sales) OVER (ORDER BY ms.month) IS NULL 
            OR LAG(msl.total_sales) OVER (ORDER BY ms.month) = 0 
        THEN NULL
        ELSE ROUND(
            (((COALESCE(msl.total_sales, 0) - LAG(msl.total_sales) OVER (ORDER BY ms.month))
              / NULLIF(LAG(msl.total_sales) OVER (ORDER BY ms.month), 0)) * 100)::numeric,
            2
        )
    END AS mom_growth_rate_pct
FROM month_series ms
LEFT JOIN monthly_sales msl ON ms.month = msl.month
ORDER BY ms.month;

/*-----------------------------------------
 3. QOQ Growth
-----------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        NULL::TEXT[] AS category_filter,
        NULL::TEXT[] AS channel_filter
),

quarter_series AS (
    SELECT generate_series(
        date_trunc('quarter', (SELECT start_date FROM params)),
        date_trunc('quarter', (SELECT end_date FROM params)),
        interval '3 month'
    ) AS quarter_start
),

product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),

quarterly_sales AS (
    SELECT 
        date_trunc('quarter', pi.created_date) AS quarter_start,
        SUM(pi.total_amount) AS total_sales,
        SUM(pi.qty) AS total_units,
        COUNT(DISTINCT pi.po_id) AS order_count
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pi.created_date BETWEEN p.start_date AND p.end_date
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
    GROUP BY date_trunc('quarter', pi.created_date)
)

SELECT
    (SELECT vendor_id FROM params) AS vendor_id,
    TO_CHAR(qs.quarter_start, '"Q"Q YYYY') AS quarter,
    qs.quarter_start,
    COALESCE(ROUND(qsl.total_sales::numeric, 2), 0) AS total_sales,
    COALESCE(ROUND(qsl.total_units::numeric, 2), 0) AS total_units,
    COALESCE(qsl.order_count, 0) AS order_count,
    COALESCE(ROUND(LAG(qsl.total_sales) OVER (ORDER BY qs.quarter_start)::numeric, 2), 0) AS prev_quarter_sales,
    CASE
        WHEN LAG(qsl.total_sales) OVER (ORDER BY qs.quarter_start) IS NULL 
            OR LAG(qsl.total_sales) OVER (ORDER BY qs.quarter_start) = 0 
        THEN NULL
        ELSE ROUND(
            (((COALESCE(qsl.total_sales, 0) - LAG(qsl.total_sales) OVER (ORDER BY qs.quarter_start))
              / NULLIF(LAG(qsl.total_sales) OVER (ORDER BY qs.quarter_start), 0)) * 100)::numeric,
            2
        )
    END AS qoq_growth_rate_pct
FROM quarter_series qs
LEFT JOIN quarterly_sales qsl ON qs.quarter_start = qsl.quarter_start
ORDER BY qs.quarter_start;

/*-----------------------------------------
 4. REVENUE PER PRODUCT LINE
-----------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        NULL::TEXT[] AS category_filter,
        NULL::TEXT[] AS channel_filter
),

product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),

-- Base sales data with filters
base_sales AS (
    SELECT 
        pi.product_id,
        pi.total_amount,
        pi.qty
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pi.created_date BETWEEN p.start_date AND p.end_date
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
),

-- Join with category information
sales_with_category AS (
    SELECT 
        COALESCE(pc.category_name, 'Unknown') AS category_name,
        b.total_amount,
        b.qty
    FROM base_sales b
    LEFT JOIN product_categories pc ON b.product_id = pc.product_id
),

-- Aggregate by category
category_sales AS (
    SELECT 
        category_name,
        ROUND(SUM(total_amount)::numeric, 2) AS total_revenue,
        ROUND(SUM(qty)::numeric, 2) AS total_units,
        COUNT(*) AS transaction_count
    FROM sales_with_category
    GROUP BY category_name
),

-- Calculate vendor total for percentage
vendor_total AS (
    SELECT SUM(total_revenue) AS vendor_total_revenue
    FROM category_sales
)

-- Final output with contribution percentage
SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    cs.category_name AS product_line,
    cs.total_revenue,
    cs.total_units,
    cs.transaction_count,
    ROUND((cs.total_revenue / NULLIF(vt.vendor_total_revenue, 0)) * 100, 2) AS revenue_contribution_pct
FROM category_sales cs
CROSS JOIN vendor_total vt
ORDER BY cs.total_revenue DESC;

/*
Charts: 
- Time-series Line Chart: Trends in daily/weekly/monthly sales. 
- Bar Chart: Top-Selling Products. 
- Pie Chart: Regional revenue distribution. 
- Additional: Scatterplot of Order Value vs. Quantity.
*/

/*-----------------------------------------
 1. Daily/Weekly/Monthly Sales 
-----------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        'day'::TEXT AS time_resolution,      -- 'day', 'week', or 'month'
        NULL::TEXT[] AS category_filter,
        NULL::TEXT[] AS channel_filter
),

product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),

-- Aggregate sales by time period
sales_time AS (
    SELECT 
        date_trunc((SELECT time_resolution FROM params), pi.created_date) AS date_period,
        SUM(pi.total_amount) AS total_sales,
        SUM(pi.qty) AS total_units,
        COUNT(DISTINCT pi.po_id) AS order_count
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pi.created_date BETWEEN p.start_date AND p.end_date
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
    GROUP BY date_trunc((SELECT time_resolution FROM params), pi.created_date)
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    CASE 
        WHEN (SELECT time_resolution FROM params) = 'day' 
            THEN TO_CHAR(date_period, 'YYYY-MM-DD')
        WHEN (SELECT time_resolution FROM params) = 'week' 
            THEN TO_CHAR(date_period, 'YYYY-MM-DD') || ' (Week ' || TO_CHAR(date_period, 'IW') || ')'
        WHEN (SELECT time_resolution FROM params) = 'month' 
            THEN TO_CHAR(date_period, 'YYYY-MM')
    END AS period_label,
    date_period,
    ROUND(total_sales::numeric, 2) AS total_sales,
    ROUND(total_units::numeric, 2) AS total_units,
    order_count,
    ROUND((total_sales / NULLIF(order_count, 0))::numeric, 2) AS avg_order_value
FROM sales_time
ORDER BY date_period;

/*-----------------------------------------
 2. TOP SELLING PRODUCTS
-----------------------------------------*/


WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        20 AS top_n_products,                -- Number of top products to return
        NULL::TEXT[] AS category_filter,
        NULL::TEXT[] AS channel_filter
),

product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),

-- Aggregate sales by product
product_sales AS (
    SELECT 
        pi.product_id,
        SUM(pi.total_amount) AS total_revenue,
        SUM(pi.qty) AS total_units,
        COUNT(DISTINCT pi.po_id) AS order_count,
        COUNT(*) AS line_item_count
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pi.created_date BETWEEN p.start_date AND p.end_date
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
    GROUP BY pi.product_id
)

-- Join with product details and rank by revenue
SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    vp.product_name,
    COALESCE(pc.category_name, 'Unknown') AS category,
    ROUND(ps.total_revenue::numeric, 2) AS total_revenue,
    ROUND(ps.total_units::numeric, 2) AS total_units,
    ps.order_count,
    ps.line_item_count,
    ROUND((ps.total_revenue / NULLIF(ps.total_units, 0))::numeric, 2) AS avg_price_per_unit
FROM product_sales ps
JOIN vendor_products vp ON ps.product_id = vp.id
LEFT JOIN product_categories pc ON ps.product_id = pc.product_id
ORDER BY ps.total_revenue DESC
LIMIT (SELECT top_n_products FROM params);

/*-----------------------------------------
 3. REGION WISE REVENUE DISTRIBUTION
-----------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        NULL::TEXT[] AS category_filter,
        NULL::TEXT[] AS channel_filter
),

product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),

-- Aggregate sales by region (city from user_address)
regional_sales AS (
    SELECT 
        COALESCE(ua.city, 'Unknown') AS region,
        SUM(pi.total_amount) AS total_revenue,
        SUM(pi.qty) AS total_units,
        COUNT(DISTINCT pi.po_id) AS order_count
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pi.created_date BETWEEN p.start_date AND p.end_date
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
    GROUP BY ua.city
),

-- Calculate total for percentage
total_revenue AS (
    SELECT SUM(total_revenue) AS vendor_total_revenue
    FROM regional_sales
)

-- Final output with percentage contribution
SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    rs.region,
    ROUND(rs.total_revenue::numeric, 2) AS total_revenue,
    ROUND(rs.total_units::numeric, 2) AS total_units,
    rs.order_count,
    ROUND((rs.total_revenue / NULLIF(tr.vendor_total_revenue, 0) * 100)::numeric, 2) AS revenue_contribution_pct
FROM regional_sales rs
CROSS JOIN total_revenue tr
ORDER BY rs.total_revenue DESC;

/*-----------------------------------------
 4. SCATTERPLOT ORDER VALUE VS QUANTITY
-----------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        NULL::TEXT[] AS category_filter,
        NULL::TEXT[] AS channel_filter
),

product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),

-- Aggregate by order (po_id) for scatter plot
order_data AS (
    SELECT 
        pi.po_id,
        pd.created_date,
        COALESCE(pd.source, 'Unknown') AS sales_channel,
        SUM(pi.total_amount) AS order_value,
        SUM(pi.qty) AS total_quantity
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pi.created_date BETWEEN p.start_date AND p.end_date
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
    GROUP BY pi.po_id, pd.created_date, pd.source
)

-- Final scatter plot data
SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    od.po_id,
    ROUND(od.order_value::numeric, 2) AS order_value,
    ROUND(od.total_quantity::numeric, 2) AS quantity,
    od.sales_channel,
    TO_CHAR(od.created_date, 'YYYY-MM-DD') AS order_date,
    ROUND((od.order_value / NULLIF(od.total_quantity, 0))::numeric, 2) AS avg_price_per_unit
FROM order_data od
ORDER BY od.order_value DESC;
