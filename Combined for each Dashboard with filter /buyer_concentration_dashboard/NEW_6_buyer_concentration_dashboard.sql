/*
================================================================================
DASHBOARD 6: BUYER CONCENTRATION & RISK DASHBOARD
================================================================================
Purpose: "How dependent am I on a few buyers? What's my risk exposure?"
Data Source: po_details, po_items, userApis_organization

KPIs:
- Total Active Buyers
- Top 1 Buyer Revenue %
- Top 5 Buyers Revenue %
- Buyer Dependency Index (HHI)
- Dormant Buyers (No PO in last 90 days)

Charts:
- Buyer Revenue Pareto (Top 10)
- Buyer Revenue Share (Donut)
- Active vs New vs Dormant Buyers Trend
- Buyer Order Frequency Distribution
================================================================================
*/

/*----------------------------------------------------------------
6.1 MAIN KPIs: Buyer Concentration Metrics
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        90 AS dormant_days  -- Days without order to be considered dormant
),

buyer_revenue AS (
    SELECT 
        pd.buyer_org_id,
        SUM(pi.total_amount) AS revenue,
        COUNT(DISTINCT pd.id) AS order_count,
        MAX(pd.created_date) AS last_order_date
    FROM po_details pd
    JOIN po_items pi ON pd.id = pi.po_id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
      AND pd.buyer_org_id IS NOT NULL
    GROUP BY pd.buyer_org_id
),

total_revenue AS (
    SELECT SUM(revenue) AS total FROM buyer_revenue
),

ranked_buyers AS (
    SELECT 
        buyer_org_id,
        revenue,
        order_count,
        last_order_date,
        ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rank,
        revenue / NULLIF((SELECT total FROM total_revenue), 0) * 100 AS revenue_pct
    FROM buyer_revenue
),

-- Herfindahl-Hirschman Index for concentration
hhi AS (
    SELECT 
        SUM(POWER(revenue_pct, 2)) AS hhi_index
    FROM ranked_buyers
),

-- Dormant buyers (had orders before period but none in period)
historical_buyers AS (
    SELECT DISTINCT pd.buyer_org_id
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date::DATE < p.start_date
      AND pd.buyer_org_id IS NOT NULL
),

dormant_buyers AS (
    SELECT COUNT(*) AS dormant_count
    FROM historical_buyers hb
    WHERE hb.buyer_org_id NOT IN (SELECT buyer_org_id FROM buyer_revenue)
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    (SELECT COUNT(*) FROM buyer_revenue) AS active_buyers,
    ROUND((SELECT revenue_pct FROM ranked_buyers WHERE rank = 1)::numeric, 2) AS top1_buyer_revenue_pct,
    ROUND((SELECT SUM(revenue_pct) FROM ranked_buyers WHERE rank <= 5)::numeric, 2) AS top5_buyers_revenue_pct,
    ROUND((SELECT hhi_index FROM hhi)::numeric, 2) AS buyer_dependency_index,
    (SELECT dormant_count FROM dormant_buyers) AS dormant_buyers,
    ROUND((SELECT total FROM total_revenue)::numeric, 2) AS total_revenue;


/*----------------------------------------------------------------
6.2 CHART: Buyer Revenue Pareto (Top 10 Buyers)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

buyer_revenue AS (
    SELECT 
        pd.buyer_org_id,
        org.company_name AS buyer_name,
        SUM(pi.total_amount) AS revenue,
        COUNT(DISTINCT pd.id) AS order_count
    FROM po_details pd
    JOIN po_items pi ON pd.id = pi.po_id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN "userApis_organization" org ON pd.buyer_org_id = org.org_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
      AND pd.buyer_org_id IS NOT NULL
    GROUP BY pd.buyer_org_id, org.company_name
),

total_revenue AS (
    SELECT SUM(revenue) AS total FROM buyer_revenue
),

ranked AS (
    SELECT 
        buyer_org_id,
        COALESCE(buyer_name, 'Buyer ' || buyer_org_id) AS buyer_name,
        revenue,
        order_count,
        ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rank,
        ROUND((revenue * 100 / NULLIF((SELECT total FROM total_revenue), 0))::numeric, 2) AS revenue_pct,
        ROUND((SUM(revenue) OVER (ORDER BY revenue DESC) * 100 / NULLIF((SELECT total FROM total_revenue), 0))::numeric, 2) AS cumulative_pct
    FROM buyer_revenue
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    buyer_org_id,
    buyer_name,
    ROUND(revenue::numeric, 2) AS revenue,
    order_count,
    revenue_pct,
    cumulative_pct
FROM ranked
WHERE rank <= 10
ORDER BY rank;


/*----------------------------------------------------------------
6.3 CHART: Buyer Revenue Share Distribution (For Donut)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

buyer_revenue AS (
    SELECT 
        pd.buyer_org_id,
        org.company_name AS buyer_name,
        SUM(pi.total_amount) AS revenue
    FROM po_details pd
    JOIN po_items pi ON pd.id = pi.po_id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN "userApis_organization" org ON pd.buyer_org_id = org.org_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
      AND pd.buyer_org_id IS NOT NULL
    GROUP BY pd.buyer_org_id, org.company_name
),

total_revenue AS (
    SELECT SUM(revenue) AS total FROM buyer_revenue
),

ranked AS (
    SELECT 
        buyer_org_id,
        COALESCE(buyer_name, 'Buyer ' || buyer_org_id) AS buyer_name,
        revenue,
        ROW_NUMBER() OVER (ORDER BY revenue DESC) AS rank
    FROM buyer_revenue
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    CASE 
        WHEN rank <= 5 THEN buyer_name
        ELSE 'Others'
    END AS segment,
    ROUND(SUM(revenue)::numeric, 2) AS revenue,
    ROUND((SUM(revenue) * 100 / NULLIF((SELECT total FROM total_revenue), 0))::numeric, 2) AS revenue_pct
FROM ranked
GROUP BY CASE WHEN rank <= 5 THEN buyer_name ELSE 'Others' END
ORDER BY SUM(revenue) DESC;


/*----------------------------------------------------------------
6.4 CHART: Buyer Activity Trend (Monthly New/Active/Dormant)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

monthly_buyers AS (
    SELECT 
        DATE_TRUNC('month', pd.created_date)::DATE AS month,
        pd.buyer_org_id,
        MIN(pd.created_date) OVER (PARTITION BY pd.buyer_org_id) AS first_order_date
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
      AND pd.buyer_org_id IS NOT NULL
),

monthly_stats AS (
    SELECT 
        month,
        COUNT(DISTINCT buyer_org_id) AS active_buyers,
        COUNT(DISTINCT CASE 
            WHEN DATE_TRUNC('month', first_order_date) = month 
            THEN buyer_org_id 
        END) AS new_buyers
    FROM monthly_buyers
    GROUP BY month
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    TO_CHAR(month, 'YYYY-MM') AS month,
    active_buyers,
    new_buyers,
    active_buyers - new_buyers AS returning_buyers
FROM monthly_stats
ORDER BY month;


/*----------------------------------------------------------------
6.5 CHART: Buyer Order Frequency Distribution
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

buyer_orders AS (
    SELECT 
        pd.buyer_org_id,
        COUNT(DISTINCT pd.id) AS order_count
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
      AND pd.buyer_org_id IS NOT NULL
    GROUP BY pd.buyer_org_id
),

frequency_buckets AS (
    SELECT 
        CASE 
            WHEN order_count = 1 THEN '1 order'
            WHEN order_count BETWEEN 2 AND 5 THEN '2-5 orders'
            WHEN order_count BETWEEN 6 AND 10 THEN '6-10 orders'
            WHEN order_count BETWEEN 11 AND 20 THEN '11-20 orders'
            ELSE '20+ orders'
        END AS frequency_bucket,
        CASE 
            WHEN order_count = 1 THEN 1
            WHEN order_count BETWEEN 2 AND 5 THEN 2
            WHEN order_count BETWEEN 6 AND 10 THEN 3
            WHEN order_count BETWEEN 11 AND 20 THEN 4
            ELSE 5
        END AS bucket_order,
        COUNT(*) AS buyer_count
    FROM buyer_orders
    GROUP BY 1, 2
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    frequency_bucket,
    bucket_order,
    buyer_count
FROM frequency_buckets
ORDER BY bucket_order;
