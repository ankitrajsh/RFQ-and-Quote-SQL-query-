/*
================================================================================
DASHBOARD 4: CUSTOMER & MARKET INSIGHTS DASHBOARD
================================================================================
Purpose: "Where are my opportunities?"
Combines: Customer Engagement + Territory Intelligence (simplified)

KPIs:
- Profile Views
- Product Views
- Unique Visitors
- Chats Initiated
- Active Buyers
- Market Penetration %

Charts:
- Bar Chart: Top Products by Views
- Table: Accounts by Region
================================================================================
*/

/*----------------------------------------------------------------
4.1 MAIN KPIs: Engagement Metrics
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2024-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
),

-- Profile views
profile_engagement AS (
    SELECT 
        COUNT(idvisit) AS vendor_profile_views,
        SUM(time_spent_ref_action) AS engagement_duration_ms,
        COUNT(DISTINCT idvisit) AS profile_visitors
    FROM public.matomo_logs_ds ml
    JOIN params p 
        ON ml.server_time::date BETWEEN p.start_date AND p.end_date
        AND ml.vendor_id = p.vendor_id
    WHERE event_type = 'vendor_view'
),

-- Product views
vendor_products_list AS (
    SELECT product_id
    FROM vendor_products vp
    JOIN params p ON vp.org_id = p.vendor_id
),

product_views_data AS (
    SELECT 
        idvisit,
        user_id,
        time_spent_ref_action
    FROM public.matomo_logs_ds ml
    JOIN vendor_products_list vp ON ml.product_id = vp.product_id
    JOIN params p ON ml.server_time::date BETWEEN p.start_date AND p.end_date
    WHERE ml.event_type = 'product_view'
    
    UNION ALL
    
    SELECT 
        idvisit,
        user_id,
        time_spent_ref_action
    FROM public.matomo_logs_ds ml
    JOIN params p ON ml.vendor_id = p.vendor_id
    WHERE ml.event_type = 'vendor_product_view'
      AND ml.server_time::date BETWEEN p.start_date AND p.end_date
),

product_engagement AS (
    SELECT 
        COUNT(idvisit) AS product_views,
        COUNT(DISTINCT idvisit) AS unique_viewers,
        SUM(time_spent_ref_action) AS product_engagement_ms
    FROM product_views_data
),

-- Chats initiated
chat_data AS (
    SELECT COUNT(DISTINCT stream_id) AS chats_initiated
    FROM params p
    JOIN public.dealroom_stream_members dr
        ON p.vendor_id = dr.vendor_id
        AND dr.created_at::date BETWEEN p.start_date AND p.end_date
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    pe.vendor_profile_views,
    pe.profile_visitors,
    prd.product_views,
    prd.unique_viewers,
    cd.chats_initiated,
    -- Engagement in seconds
    ROUND(pe.engagement_duration_ms / 1000.0, 2) AS profile_engagement_seconds,
    ROUND(prd.product_engagement_ms / 1000.0, 2) AS product_engagement_seconds
FROM profile_engagement pe
CROSS JOIN product_engagement prd
CROSS JOIN chat_data cd;


/*----------------------------------------------------------------
4.2 KPIs: Market Penetration
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS zone_filter,
        NULL::TEXT AS industry_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

-- Active buyers in period
active_buyers AS (
    SELECT DISTINCT pd.buyer_org_id
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
),

-- Total potential accounts
potential_accounts AS (
    SELECT COUNT(DISTINCT org.org_id) AS total_accounts
    FROM "userApis_organization" org
    CROSS JOIN params p
    WHERE org.is_active = TRUE
      AND (p.zone_filter IS NULL OR org.state = p.zone_filter OR org.city_name = p.zone_filter)
      AND (p.industry_filter IS NULL OR org.industries ILIKE '%' || p.industry_filter || '%')
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    COUNT(DISTINCT ab.buyer_org_id) AS active_buyers,
    pa.total_accounts AS potential_accounts,
    ROUND(
        (COUNT(DISTINCT ab.buyer_org_id) * 100.0 / NULLIF(pa.total_accounts, 0))::NUMERIC, 2
    ) AS penetration_pct
FROM active_buyers ab
CROSS JOIN potential_accounts pa
GROUP BY pa.total_accounts;


/*----------------------------------------------------------------
4.3 CHART: Top Products by Views
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2024-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
),

vendor_products_list AS (
    SELECT product_id, product_name
    FROM vendor_products vp
    JOIN params p ON vp.org_id = p.vendor_id
),

product_views_data AS (
    SELECT 
        ml.product_id,
        vp.product_name,
        idvisit
    FROM public.matomo_logs_ds ml
    JOIN vendor_products_list vp ON ml.product_id = vp.product_id
    JOIN params p ON ml.server_time::date BETWEEN p.start_date AND p.end_date
    WHERE ml.event_type = 'product_view'
    
    UNION ALL
    
    SELECT 
        ml.product_id,
        vp.product_name,
        idvisit
    FROM public.matomo_logs_ds ml
    JOIN params p ON ml.vendor_id = p.vendor_id
    JOIN vendor_products_list vp ON ml.product_id = vp.product_id
    WHERE ml.event_type = 'vendor_product_view'
      AND ml.server_time::date BETWEEN p.start_date AND p.end_date
)

SELECT 
    product_id,
    product_name,
    COUNT(idvisit) AS views
FROM product_views_data
GROUP BY product_id, product_name
ORDER BY views DESC
LIMIT 10;


/*----------------------------------------------------------------
4.4 TABLE: Accounts by Region
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

-- Buyers per region
regional_buyers AS (
    SELECT 
        COALESCE(ua.region, ua.city, 'Unknown') AS region,
        COUNT(DISTINCT pd.buyer_org_id) AS active_buyers,
        ROUND(SUM(pi.total_amount)::NUMERIC, 2) AS total_sales,
        COUNT(DISTINCT pd.id) AS total_orders
    FROM po_details pd
    JOIN po_items pi ON pi.po_id = pd.id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
    GROUP BY COALESCE(ua.region, ua.city, 'Unknown')
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    region,
    active_buyers,
    total_sales,
    total_orders,
    ROUND(total_sales / NULLIF(total_orders, 0), 2) AS avg_order_value
FROM regional_buyers
ORDER BY total_sales DESC;


/*----------------------------------------------------------------
4.5 SUMMARY: Engagement Funnel (Views → Chats → Orders)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2024-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
),

-- Profile views
profile_views AS (
    SELECT COUNT(DISTINCT idvisit) AS profile_visitors
    FROM public.matomo_logs_ds ml
    JOIN params p 
        ON ml.server_time::date BETWEEN p.start_date AND p.end_date
        AND ml.vendor_id = p.vendor_id
    WHERE event_type = 'vendor_view'
),

-- Chats
chats AS (
    SELECT COUNT(DISTINCT stream_id) AS chats_initiated
    FROM params p
    JOIN public.dealroom_stream_members dr
        ON p.vendor_id = dr.vendor_id
        AND dr.created_at::date BETWEEN p.start_date AND p.end_date
),

-- Orders
orders AS (
    SELECT COUNT(DISTINCT buyer_org_id) AS buyers_ordered
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
)

SELECT
    'Profile Visitors' AS stage,
    1 AS stage_order,
    pv.profile_visitors AS count
FROM profile_views pv

UNION ALL

SELECT
    'Chats Initiated' AS stage,
    2 AS stage_order,
    c.chats_initiated AS count
FROM chats c

UNION ALL

SELECT
    'Buyers Ordered' AS stage,
    3 AS stage_order,
    o.buyers_ordered AS count
FROM orders o

ORDER BY stage_order;
