/*
================================================================================
DASHBOARD 2: RFQ & QUOTE PERFORMANCE DASHBOARD
================================================================================
Purpose: "How do I win more deals?"
Combines: RFQ & Quote Conversion + Pricing Intelligence

This is the MOST CRITICAL dashboard for B2B vendors - Quote conversion 
directly impacts revenue.

KPIs:
- RFQs Received
- Quotes Submitted
- Quote Conversion Rate %
- Avg Response Time (mins)
- Price Competitiveness %

Charts:
- Funnel Chart: RFQ → Quote → Won
- Histogram: Response Time Distribution
- Heatmap: RFQs by Region × Product
- Box Plot: Price Variance across RFQs
================================================================================
*/

/*----------------------------------------------------------------
2.1 MAIN KPIs: RFQs, Quotes, Conversion Rate, Response Time
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2025-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
),

rfq_master AS (
    SELECT 
        al.id,
        al.updated_date,
        al.new_status,
        al.quote_id,
        al.rfq_id,
        al.rfq_product_id,
        r.publish_date AS rfq_publish_date,
        rp.seller_id AS vendor_id,
        rq.mdate AS responded_date

    FROM bt_rfq_activity_logs al
    JOIN bt_rfq r ON al.rfq_id = r.id
    LEFT JOIN bt_rfq_status rs ON al.new_status = rs.id
    LEFT JOIN bt_rfq_products rp 
           ON al.rfq_product_id = rp.id
          AND rp.seller_id IS NOT NULL
    LEFT JOIN bt_rfq_quotes rq
           ON al.quote_id = rq.id 
          AND al.rfq_id = rq.rfq_id

    JOIN params p ON rp.seller_id = p.vendor_id
    WHERE r.publish_date BETWEEN p.start_date AND p.end_date
),

-- RFQ & Conversion metrics
rfq_metrics AS (
    SELECT
        COUNT(DISTINCT rfq_id) AS rfq_received,
        COUNT(DISTINCT CASE WHEN NULLIF(quote_id, 0) > 0 THEN rfq_id END) AS quote_submitted,
        COUNT(DISTINCT CASE WHEN new_status IN (5, 6) THEN rfq_id END) AS quotes_converted,
        ROUND(
            COUNT(DISTINCT CASE WHEN new_status IN (5, 6) THEN rfq_id END)::DECIMAL * 100.0 /
            NULLIF(COUNT(DISTINCT rfq_id), 0), 2
        ) AS conversion_rate_pct
    FROM rfq_master
),

-- Response time calculation
sent AS (
    SELECT 
        al.rfq_id,
        al.rfq_product_id,
        MIN(CASE WHEN al.new_status = 2 THEN al.updated_date END) AS sent_to_supplier_time
    FROM bt_rfq_activity_logs al
    JOIN params p ON 1=1
    WHERE al.updated_date BETWEEN p.start_date AND p.end_date
    GROUP BY al.rfq_id, al.rfq_product_id
),

quotes AS (
    SELECT 
        al.rfq_id,
        al.rfq_product_id,
        al.quote_id,
        MIN(CASE WHEN al.new_status = 9 THEN al.updated_date END) AS quote_sent_time
    FROM bt_rfq_activity_logs al
    JOIN params p ON 1=1
    WHERE al.quote_id IS NOT NULL
      AND al.updated_date BETWEEN p.start_date AND p.end_date
    GROUP BY al.rfq_id, al.rfq_product_id, al.quote_id
),

response_times AS (
    SELECT 
        rq.seller_id,
        EXTRACT(EPOCH FROM (q.quote_sent_time - s.sent_to_supplier_time)) / 60 AS response_mins
    FROM sent s
    JOIN quotes q 
        ON s.rfq_id = q.rfq_id
       AND s.rfq_product_id = q.rfq_product_id
    JOIN bt_rfq_quotes rq ON q.quote_id = rq.id
    JOIN params p ON rq.seller_id = p.vendor_id
),

avg_response AS (
    SELECT 
        ROUND(AVG(response_mins)::numeric, 2) AS avg_response_time_mins
    FROM response_times
),

-- Price competitiveness
winning_quotes AS (
    SELECT
        rq.rfq_id,
        MAX(rq."unitPrice") AS win_price
    FROM bt_rfq_activity_logs al
    JOIN bt_rfq_quotes rq ON al.quote_id = rq.id
    WHERE al.new_status IN (5, 6)
    GROUP BY rq.rfq_id
),

vendor_quotes AS (
    SELECT
        rq.id AS quote_id,
        rq.rfq_id,
        rq."unitPrice" AS vendor_price,
        rq.seller_id
    FROM bt_rfq_quotes rq
    JOIN params p ON rq.seller_id = p.vendor_id
),

competitiveness AS (
    SELECT
        CASE 
            WHEN w.win_price IS NULL THEN NULL
            ELSE ROUND(((v.vendor_price - w.win_price) * 100.0 / NULLIF(w.win_price, 0))::numeric, 2)
        END AS price_competitiveness
    FROM vendor_quotes v
    LEFT JOIN winning_quotes w ON w.rfq_id = v.rfq_id
    JOIN bt_rfq r ON v.rfq_id = r.id
    JOIN params p ON r.publish_date BETWEEN p.start_date AND p.end_date
    WHERE r.rfq_status IN (5, 6)
),

avg_competitiveness AS (
    SELECT ROUND(AVG(price_competitiveness)::numeric, 2) AS avg_price_competitiveness
    FROM competitiveness
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    rm.rfq_received,
    rm.quote_submitted,
    rm.quotes_converted,
    rm.conversion_rate_pct,
    ar.avg_response_time_mins,
    ac.avg_price_competitiveness
FROM rfq_metrics rm
CROSS JOIN avg_response ar
CROSS JOIN avg_competitiveness ac;


/*----------------------------------------------------------------
2.2 CHART: Funnel - RFQ → Quote → Won
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2025-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
),

rfq_master AS (
    SELECT 
        al.new_status,
        al.quote_id,
        al.rfq_id,
        rp.seller_id AS vendor_id

    FROM bt_rfq_activity_logs al
    JOIN bt_rfq r ON al.rfq_id = r.id
    LEFT JOIN bt_rfq_products rp 
           ON al.rfq_product_id = rp.id
          AND rp.seller_id IS NOT NULL
    LEFT JOIN bt_rfq_quotes rq
           ON al.quote_id = rq.id 
          AND al.rfq_id = rq.rfq_id

    JOIN params p ON rp.seller_id = p.vendor_id
    WHERE r.publish_date BETWEEN p.start_date AND p.end_date
)

SELECT
    'RFQs Received' AS stage,
    1 AS stage_order,
    COUNT(DISTINCT rfq_id) AS count
FROM rfq_master

UNION ALL

SELECT
    'Quotes Submitted' AS stage,
    2 AS stage_order,
    COUNT(DISTINCT CASE WHEN NULLIF(quote_id, 0) > 0 THEN rfq_id END) AS count
FROM rfq_master

UNION ALL

SELECT
    'Orders Won' AS stage,
    3 AS stage_order,
    COUNT(DISTINCT CASE WHEN new_status IN (5, 6) THEN rfq_id END) AS count
FROM rfq_master

ORDER BY stage_order;


/*----------------------------------------------------------------
2.3 CHART: Heatmap - RFQs by Region × Product
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2025-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
)

SELECT 
    rp.product_id,
    vp.product_name,
    COALESCE(ua.city, 'Unknown') AS city,
    COUNT(DISTINCT rq.rfq_id) AS rfq_count
FROM bt_rfq_quotes rq 
JOIN bt_rfq_products rp ON rq.rfq_product_id = rp.id
LEFT JOIN vendor_products vp ON rp.product_id = vp.id
LEFT JOIN bt_rfq_address ra ON rq.rfq_id = ra.rfq_id
LEFT JOIN user_address ua ON ra.address_id = ua.id
LEFT JOIN bt_rfq r ON rq.rfq_id = r.id
JOIN params p ON rp.seller_id = p.vendor_id
WHERE r.publish_date BETWEEN p.start_date AND p.end_date
GROUP BY rp.product_id, vp.product_name, ua.city
ORDER BY rfq_count DESC;


/*----------------------------------------------------------------
2.4 CHART: Response Time Distribution (Histogram)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2025-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
),

publish_times AS (
    SELECT 
        r.id AS rfq_id,
        r.publish_date
    FROM bt_rfq r
),

first_vendor_response AS (
    SELECT
        al.rfq_id,
        MIN(al.updated_date) AS first_response_time
    FROM bt_rfq_activity_logs al
    JOIN bt_rfq_quotes rq ON rq.id = al.quote_id
    JOIN params p ON rq.seller_id = p.vendor_id
    WHERE al.new_status = 9
      AND al.updated_date BETWEEN p.start_date AND p.end_date
    GROUP BY al.rfq_id
),

response_data AS (
    SELECT
        p.rfq_id,
        EXTRACT(EPOCH FROM (f.first_response_time - p.publish_date)) / 60 AS response_time_mins
    FROM publish_times p
    JOIN first_vendor_response f ON p.rfq_id = f.rfq_id
    WHERE f.first_response_time IS NOT NULL
)

-- Bucketed for histogram
SELECT
    response_bucket,
    COUNT(*) AS rfq_count
FROM (
    SELECT
        CASE 
            WHEN response_time_mins <= 30 THEN '0-30 mins'
            WHEN response_time_mins <= 60 THEN '30-60 mins'
            WHEN response_time_mins <= 120 THEN '1-2 hours'
            WHEN response_time_mins <= 240 THEN '2-4 hours'
            WHEN response_time_mins <= 480 THEN '4-8 hours'
            WHEN response_time_mins <= 1440 THEN '8-24 hours'
            ELSE '> 24 hours'
        END AS response_bucket,
        CASE 
            WHEN response_time_mins <= 30 THEN 1
            WHEN response_time_mins <= 60 THEN 2
            WHEN response_time_mins <= 120 THEN 3
            WHEN response_time_mins <= 240 THEN 4
            WHEN response_time_mins <= 480 THEN 5
            WHEN response_time_mins <= 1440 THEN 6
            ELSE 7
        END AS bucket_order
    FROM response_data
) bucketed
GROUP BY response_bucket, bucket_order
ORDER BY bucket_order;


/*----------------------------------------------------------------
2.5 CHART: Price Variance Box Plot Data
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2025-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
)

SELECT 
    r.id AS rfq_id,
    q.id AS quote_id,
    rp.requested_price,
    q."unitPrice" AS quoted_price,
    ROUND(((q."unitPrice" - rp.requested_price) / NULLIF(rp.requested_price, 0)::numeric * 100)::numeric, 2) AS price_variance_pct
FROM bt_rfq r
LEFT JOIN bt_rfq_products rp ON rp.rfq_id = r.id
LEFT JOIN bt_rfq_quotes q ON q.rfq_product_id = rp.id
JOIN params p ON rp.seller_id = p.vendor_id
WHERE r.publish_date BETWEEN p.start_date AND p.end_date
  AND q."unitPrice" IS NOT NULL
  AND rp.requested_price > 0
ORDER BY price_variance_pct;


/*----------------------------------------------------------------
2.6 SUMMARY STATS: Price Variance for Box Plot
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2025-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
),

price_data AS (
    SELECT 
        ROUND(((q."unitPrice" - rp.requested_price) / NULLIF(rp.requested_price, 0)::numeric * 100)::numeric, 2) AS price_variance_pct
    FROM bt_rfq r
    LEFT JOIN bt_rfq_products rp ON rp.rfq_id = r.id
    LEFT JOIN bt_rfq_quotes q ON q.rfq_product_id = rp.id
    JOIN params p ON rp.seller_id = p.vendor_id
    WHERE r.publish_date BETWEEN p.start_date AND p.end_date
      AND q."unitPrice" IS NOT NULL
      AND rp.requested_price > 0
)

SELECT
    MIN(price_variance_pct) AS min_variance,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY price_variance_pct) AS q1,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY price_variance_pct) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY price_variance_pct) AS q3,
    MAX(price_variance_pct) AS max_variance,
    AVG(price_variance_pct) AS avg_variance
FROM price_data;
