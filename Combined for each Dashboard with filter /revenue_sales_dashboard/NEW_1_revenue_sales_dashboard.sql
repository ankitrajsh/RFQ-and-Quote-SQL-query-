/*
================================================================================
DASHBOARD 1: REVENUE & SALES DASHBOARD
================================================================================
Purpose: "How is my business performing?"
Combines: Sales Performance + Vendor Financial Dashboard

KPIs:
- Total Revenue
- Units Sold  
- Average Order Value
- Net Earnings
- Repeat Purchase Rate %

Charts:
- Line Chart: Monthly Revenue Trend
- Bar Chart: Revenue by Product Category
- Bar Chart: Top 10 Selling Products
- Pie Chart: Revenue by Region
================================================================================
*/

/*----------------------------------------------------------------
1.1 MAIN KPIs: Revenue, Units, AOV, Net Earnings, Repeat Rate
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

-- Order-level sales metrics
order_level AS (
    SELECT 
        pi.po_id,
        SUM(pi.total_amount) AS order_total,
        SUM(pi.gross_amount) AS order_gross,
        SUM(pi.net_total) AS order_net,
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

-- Sales aggregates
sales_metrics AS (
    SELECT 
        ROUND(SUM(order_total)::numeric, 2) AS total_revenue,
        ROUND(SUM(order_gross)::numeric, 2) AS gross_revenue,
        ROUND(SUM(order_net)::numeric, 2) AS net_earnings,
        ROUND(SUM(total_qty)::numeric, 2) AS units_sold,
        ROUND(SUM(order_total)::numeric / NULLIF(COUNT(po_id), 0), 2) AS average_order_value
    FROM order_level
),

-- Repeat purchase calculation
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

buyer_order_counts AS (
    SELECT 
        buyer_id,
        COUNT(DISTINCT po_id) AS order_count
    FROM base_orders
    GROUP BY buyer_id
),

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

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    sm.total_revenue,
    sm.gross_revenue,
    sm.net_earnings,
    sm.units_sold,
    sm.average_order_value,
    rpm.total_buyers,
    rpm.repeat_buyers,
    rpm.repeat_purchase_rate_pct
FROM sales_metrics sm
CROSS JOIN repeat_purchase_metrics rpm;


/*----------------------------------------------------------------
1.2 CHART: Monthly Revenue Trend with MoM Growth
-----------------------------------------------------------------*/

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
        SUM(pi.total_amount) AS total_revenue,
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
    COALESCE(ROUND(msl.total_revenue::numeric, 2), 0) AS total_revenue,
    COALESCE(ROUND(msl.total_units::numeric, 2), 0) AS total_units,
    COALESCE(msl.order_count, 0) AS order_count,
    CASE
        WHEN LAG(msl.total_revenue) OVER (ORDER BY ms.month) IS NULL 
            OR LAG(msl.total_revenue) OVER (ORDER BY ms.month) = 0 
        THEN NULL
        ELSE ROUND(
            (((COALESCE(msl.total_revenue, 0) - LAG(msl.total_revenue) OVER (ORDER BY ms.month))
              / NULLIF(LAG(msl.total_revenue) OVER (ORDER BY ms.month), 0)) * 100)::numeric,
            2
        )
    END AS mom_growth_rate_pct
FROM month_series ms
LEFT JOIN monthly_sales msl ON ms.month = msl.month
ORDER BY ms.month;


/*----------------------------------------------------------------
1.3 CHART: Revenue by Product Category
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

category_sales AS (
    SELECT 
        COALESCE(pc.category_name, 'Unknown') AS category_name,
        ROUND(SUM(b.total_amount)::numeric, 2) AS total_revenue,
        ROUND(SUM(b.qty)::numeric, 2) AS total_units
    FROM base_sales b
    LEFT JOIN product_categories pc ON b.product_id = pc.product_id
    GROUP BY pc.category_name
),

vendor_total AS (
    SELECT SUM(total_revenue) AS vendor_total_revenue
    FROM category_sales
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    cs.category_name AS product_line,
    cs.total_revenue,
    cs.total_units,
    ROUND((cs.total_revenue / NULLIF(vt.vendor_total_revenue, 0)) * 100, 2) AS revenue_contribution_pct
FROM category_sales cs
CROSS JOIN vendor_total vt
ORDER BY cs.total_revenue DESC;


/*----------------------------------------------------------------
1.4 CHART: Top 10 Selling Products
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        10 AS top_n_products,
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

product_sales AS (
    SELECT 
        pi.product_id,
        SUM(pi.total_amount) AS total_revenue,
        SUM(pi.qty) AS total_units,
        COUNT(DISTINCT pi.po_id) AS order_count
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    WHERE pi.created_date BETWEEN p.start_date AND p.end_date
      AND (p.category_filter IS NULL OR pc.category_name = ANY(p.category_filter))
      AND (p.channel_filter IS NULL OR pd.source = ANY(p.channel_filter))
    GROUP BY pi.product_id
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    vp.product_name,
    COALESCE(pc.category_name, 'Unknown') AS category,
    ROUND(ps.total_revenue::numeric, 2) AS total_revenue,
    ROUND(ps.total_units::numeric, 2) AS total_units,
    ps.order_count
FROM product_sales ps
JOIN vendor_products vp ON ps.product_id = vp.id
LEFT JOIN product_categories pc ON ps.product_id = pc.product_id
ORDER BY ps.total_revenue DESC
LIMIT (SELECT top_n_products FROM params);


/*----------------------------------------------------------------
1.5 CHART: Revenue by Region (Pie Chart)
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

regional_sales AS (
    SELECT 
        COALESCE(ua.city, 'Unknown') AS region,
        SUM(pi.total_amount) AS total_revenue,
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

total_revenue AS (
    SELECT SUM(total_revenue) AS vendor_total_revenue
    FROM regional_sales
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    rs.region,
    ROUND(rs.total_revenue::numeric, 2) AS total_revenue,
    rs.order_count,
    ROUND((rs.total_revenue / NULLIF(tr.vendor_total_revenue, 0) * 100)::numeric, 2) AS revenue_contribution_pct
FROM regional_sales rs
CROSS JOIN total_revenue tr
ORDER BY rs.total_revenue DESC;
