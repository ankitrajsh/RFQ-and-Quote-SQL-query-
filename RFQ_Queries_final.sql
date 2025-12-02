/*
KPIs: 
- RFQs Received: Count of incoming requests. 
- Quotes Submitted: Number of RFQs responded to. 
- Conversion Rate: % of quotes converted into orders. 
- Avg. Response Time: Time between RFQ receipt and quote. 
- Price Competitiveness: How closely the quoted price aligns with the winning quote.
*/

/*
RFQs Received/Quotes Submitted/Conversion Rate
*/

WITH params AS (
    SELECT 
        91 AS vendor_id,                         -- change vendor ID
        DATE '2025-01-01' AS start_date,         -- change start date
        DATE '2025-12-31' AS end_date
),

rfq_master AS (
    SELECT 
        al.id,
        al.updated_date,
        al.new_status,
        rs.code,
        rs.level,
        al.quote_id,
        al.rfq_id,
        al.rfq_product_id,
        al.updated_by,

        -- RFQ master
        r.visibility,
        r.publish_date AS rfq_publish_date,
        r.expiry_date AS rfq_expiry_date,
        r.customer_id AS buyer_id,
        r.company_id AS buyer_org_id,

        -- Product & Seller side
        rp.seller_id AS vendor_id,                        
        rp.product_id,
        rp.rfq_parent_product_id,
        rp.requested_qty,
        rp.requested_price,
        rp.product_type,
        rp.is_followed,

        -- Quote response
        rq.seller_id AS quoting_seller,
        rq.expiry_date AS quote_expiry_date,
        rq."offeredQty",
        rq."unitPrice",
        rq.mdate AS responded_date,
        rq.discount_percentage,
        rq.delivery_date,
        rq.shipping_charges,
        rq.logistics_charges,
        rq.insurance_charges,
        rq.gst
		

    FROM bt_rfq_activity_logs al
    JOIN bt_rfq r              
	ON al.rfq_id = r.id
    LEFT JOIN bt_rfq_status rs 
	ON al.new_status = rs.id
    LEFT JOIN bt_rfq_products rp 
           ON al.rfq_product_id = rp.id
          AND rp.seller_id IS NOT NULL
    LEFT JOIN bt_rfq_quotes rq
           ON al.quote_id = rq.id 
          AND al.rfq_id   = rq.rfq_id

    JOIN params p ON rp.seller_id = p.vendor_id
    WHERE r.publish_date BETWEEN p.start_date AND p.end_date
)

SELECT
    COUNT(DISTINCT rfq_id) AS rfq_received,
    COUNT(DISTINCT CASE WHEN NULLIF(quote_id,0)>0 THEN rfq_id END) AS quote_submitted,
    COUNT(DISTINCT CASE WHEN new_status IN (5,6) THEN rfq_id END) AS quotes_converted,
    ROUND(
        COUNT(DISTINCT CASE WHEN new_status IN (5,6) THEN rfq_id END)::DECIMAL * 100.0 /
        NULLIF(COUNT(DISTINCT rfq_id),0), 2
    ) AS conversion_rate_percent

FROM rfq_master
;

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
	
/* Avg. Response time*/
WITH params AS (
    SELECT 
        91 AS vendor_id,                         -- vendor_id to filter
        DATE '2025-01-01' AS start_date,         -- date window start
        DATE '2025-12-31' AS end_date            -- date window end
),

-- sent to supplier time (status 2)
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

-- vendor quote submission time (status 9)
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

-- Add seller_id and calculate response time per quote
response_times AS (
    SELECT 
        s.rfq_id,
        s.rfq_product_id,
        q.quote_id,
        rq.seller_id,
        s.sent_to_supplier_time,
        q.quote_sent_time,
        EXTRACT(EPOCH FROM (q.quote_sent_time - s.sent_to_supplier_time)) / 60
            AS response_mins
    FROM sent s
    JOIN quotes q 
        ON s.rfq_id = q.rfq_id
       AND s.rfq_product_id = q.rfq_product_id
    JOIN bt_rfq_quotes rq
        ON q.quote_id = rq.id
    JOIN params p 
        ON rq.seller_id = p.vendor_id
)

-- Final metric: average response time for this vendor
SELECT 
    seller_id,
    AVG(response_mins) AS avg_response_time_mins
FROM response_times
GROUP BY seller_id;
