/*
Price Competitiveness
*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2025-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
),

-- 1. All winning quotes (max price per RFQ)
winning_quotes AS (
    SELECT
        rq.rfq_id,
        max(rq."unitPrice") AS win_price
    FROM bt_rfq_activity_logs al
    JOIN bt_rfq_quotes rq
      ON al.quote_id = rq.id
    WHERE al.new_status IN (5,6)
    GROUP BY rq.rfq_id
),

-- 2. All quotes submitted by the vendor
vendor_quotes AS (
    SELECT
        rq.id AS quote_id,
        rq.rfq_id,
        rq."unitPrice" AS vendor_price,
        rq.seller_id
    FROM bt_rfq_quotes rq
    JOIN params p ON rq.seller_id = p.vendor_id
),

-- 3. Combine vendor quotes with winning prices, guarding division by zero with NULLIF
competitiveness AS (
    SELECT
        v.rfq_id,
        v.vendor_price,
        w.win_price,
        CASE 
            WHEN w.win_price IS NULL THEN NULL
            ELSE ROUND( ((v.vendor_price - w.win_price) * 100.0 / NULLIF(w.win_price, 0))::numeric, 2 )
        END AS price_competitiveness
    FROM vendor_quotes v
    LEFT JOIN winning_quotes w
        ON w.rfq_id = v.rfq_id
),

-- 4. RFQs published in date range
rfqs_in_period AS (
    SELECT distinct(id)
    FROM bt_rfq r
    JOIN params p
      ON r.publish_date BETWEEN p.start_date AND p.end_date
	WHERE r.rfq_status in (5,6)
	
)

SELECT 
    AVG(price_competitiveness) AS avg_price_competitiveness
FROM competitiveness c
JOIN rfqs_in_period r
    ON r.id = c.rfq_id;
