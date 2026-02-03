/*
================================================================================
DASHBOARD 5: PRODUCT ENGAGEMENT & FUNNEL DASHBOARD
================================================================================
Purpose: "How are my products performing in attracting and converting buyers?"
Data Source: matomo_logs_ds, po_details, vendor_products

KPIs:
- Total Product Views
- Unique Viewers
- Vendor Profile Views
- Chat Initiations
- View-to-Chat Conversion Rate

Charts:
- Engagement Funnel: Product View → Vendor View → Chat → Order
- Top Viewed Products
- Views Trend Over Time
- Conversion Rate by Product
================================================================================
*/

/*----------------------------------------------------------------
5.1 MAIN KPIs: Product Engagement Metrics
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

-- Product Views for vendor's products
product_views AS (
    SELECT 
        m.product_id,
        m.user_id,
        m.idvisit,
        m.server_time
    FROM matomo_logs_ds m
    JOIN vendor_products vp ON m.product_id = vp.id
    JOIN params p ON vp.org_id = p.vendor_id
    WHERE m.event_type = 'product_view'
      AND m.server_time::DATE BETWEEN p.start_date AND p.end_date
),

-- Vendor Profile Views
vendor_views AS (
    SELECT 
        m.vendor_id,
        m.user_id,
        m.idvisit,
        m.server_time
    FROM matomo_logs_ds m
    JOIN params p ON m.vendor_id = p.vendor_id
    WHERE m.event_type = 'vendor_view'
      AND m.server_time::DATE BETWEEN p.start_date AND p.end_date
),

-- Chat Initiations
chat_events AS (
    SELECT 
        m.chat_id,
        m.user_id,
        m.vendor_id,
        m.server_time
    FROM matomo_logs_ds m
    JOIN params p ON m.vendor_id = p.vendor_id
    WHERE m.event_type = 'chat'
      AND m.server_time::DATE BETWEEN p.start_date AND p.end_date
),

-- Orders from PO
orders AS (
    SELECT DISTINCT pd.id, pd.buyer_org_id
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    (SELECT COUNT(*) FROM product_views) AS total_product_views,
    (SELECT COUNT(DISTINCT COALESCE(user_id, idvisit)) FROM product_views) AS unique_viewers,
    (SELECT COUNT(*) FROM vendor_views) AS vendor_profile_views,
    (SELECT COUNT(DISTINCT chat_id) FROM chat_events) AS chat_initiations,
    (SELECT COUNT(*) FROM orders) AS total_orders,
    ROUND(
        (SELECT COUNT(DISTINCT chat_id) FROM chat_events)::numeric * 100 / 
        NULLIF((SELECT COUNT(DISTINCT COALESCE(user_id, idvisit)) FROM product_views), 0),
        2
    ) AS view_to_chat_rate_pct,
    ROUND(
        (SELECT COUNT(*) FROM orders)::numeric * 100 / 
        NULLIF((SELECT COUNT(DISTINCT chat_id) FROM chat_events), 0),
        2
    ) AS chat_to_order_rate_pct;


/*----------------------------------------------------------------
5.2 CHART: Engagement Funnel Data
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

funnel_data AS (
    SELECT 
        'Product Views' AS stage,
        1 AS stage_order,
        COUNT(*) AS count
    FROM matomo_logs_ds m
    JOIN vendor_products vp ON m.product_id = vp.id
    JOIN params p ON vp.org_id = p.vendor_id
    WHERE m.event_type = 'product_view'
      AND m.server_time::DATE BETWEEN p.start_date AND p.end_date

    UNION ALL

    SELECT 
        'Vendor Views' AS stage,
        2 AS stage_order,
        COUNT(*)
    FROM matomo_logs_ds m
    JOIN params p ON m.vendor_id = p.vendor_id
    WHERE m.event_type IN ('vendor_view', 'vendor_product_view')
      AND m.server_time::DATE BETWEEN p.start_date AND p.end_date

    UNION ALL

    SELECT 
        'Chat Initiated' AS stage,
        3 AS stage_order,
        COUNT(DISTINCT chat_id)
    FROM matomo_logs_ds m
    JOIN params p ON m.vendor_id = p.vendor_id
    WHERE m.event_type = 'chat'
      AND m.server_time::DATE BETWEEN p.start_date AND p.end_date

    UNION ALL

    SELECT 
        'Orders Placed' AS stage,
        4 AS stage_order,
        COUNT(*)
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    stage,
    stage_order,
    count,
    ROUND(count::numeric * 100 / NULLIF(FIRST_VALUE(count) OVER (ORDER BY stage_order), 0), 2) AS conversion_pct
FROM funnel_data
ORDER BY stage_order;


/*----------------------------------------------------------------
5.3 CHART: Top Viewed Products
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    vp.id AS product_id,
    vp.product_name AS product_name,
    COUNT(*) AS view_count,
    COUNT(DISTINCT COALESCE(m.user_id, m.idvisit)) AS unique_viewers
FROM matomo_logs_ds m
JOIN vendor_products vp ON m.product_id = vp.id
JOIN params p ON vp.org_id = p.vendor_id
WHERE m.event_type = 'product_view'
  AND m.server_time::DATE BETWEEN p.start_date AND p.end_date
GROUP BY vp.id, vp.product_name
ORDER BY view_count DESC
LIMIT 10;


/*----------------------------------------------------------------
5.4 CHART: Product Views Trend (Daily/Weekly)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    DATE_TRUNC('week', m.server_time)::DATE AS week_start,
    COUNT(*) AS product_views,
    COUNT(DISTINCT COALESCE(m.user_id, m.idvisit)) AS unique_viewers,
    COUNT(DISTINCT m.product_id) AS products_viewed
FROM matomo_logs_ds m
JOIN vendor_products vp ON m.product_id = vp.id
JOIN params p ON vp.org_id = p.vendor_id
WHERE m.event_type = 'product_view'
  AND m.server_time::DATE BETWEEN p.start_date AND p.end_date
GROUP BY DATE_TRUNC('week', m.server_time)
ORDER BY week_start;


/*----------------------------------------------------------------
5.5 CHART: Conversion Rate by Product (Views to Chats)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

product_views AS (
    SELECT 
        m.product_id,
        COUNT(*) AS views,
        COUNT(DISTINCT COALESCE(m.user_id, m.idvisit)) AS unique_viewers
    FROM matomo_logs_ds m
    JOIN vendor_products vp ON m.product_id = vp.id
    JOIN params p ON vp.org_id = p.vendor_id
    WHERE m.event_type = 'product_view'
      AND m.server_time::DATE BETWEEN p.start_date AND p.end_date
    GROUP BY m.product_id
),

product_chats AS (
    SELECT 
        m.product_id,
        COUNT(DISTINCT m.chat_id) AS chats
    FROM matomo_logs_ds m
    JOIN vendor_products vp ON m.product_id = vp.id
    JOIN params p ON vp.org_id = p.vendor_id
    WHERE m.event_type = 'chat'
      AND m.product_id IS NOT NULL
      AND m.server_time::DATE BETWEEN p.start_date AND p.end_date
    GROUP BY m.product_id
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    vp.id AS product_id,
    vp.product_name AS product_name,
    COALESCE(pv.views, 0) AS views,
    COALESCE(pc.chats, 0) AS chats,
    ROUND(COALESCE(pc.chats, 0)::numeric * 100 / NULLIF(pv.views, 0), 2) AS conversion_rate_pct
FROM vendor_products vp
JOIN params p ON vp.org_id = p.vendor_id
LEFT JOIN product_views pv ON vp.id = pv.product_id
LEFT JOIN product_chats pc ON vp.id = pc.product_id
WHERE pv.views > 0
ORDER BY views DESC
LIMIT 15;
