
---Funnel Chart:

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
    JOIN bt_rfq r              ON al.rfq_id     = r.id
    LEFT JOIN bt_rfq_status rs ON al.new_status = rs.id
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



----- Heatmap: RFQs by Region/Product.
WITH params AS (
    SELECT 
        91 AS vendor_id,                         -- change vendor ID
        DATE '2025-01-01' AS start_date,         -- change start date
        DATE '2025-12-31' AS end_date
)
SELECT rp.product_id,ua.city,count(distinct rq.rfq_id)
FROM bt_rfq_quotes rq 
join
bt_rfq_products rp
on rq.rfq_product_id = rp.id
left join bt_rfq_address ra
on rq.rfq_id=ra.rfq_id
left join user_address ua
on  ra.address_id =ua.id
left join bt_rfq r
on rq.rfq_id=r.id
JOIN params p ON rp.seller_id = p.vendor_id
    WHERE r.publish_date BETWEEN p.start_date AND p.end_date
group by 1,2
;



---Box Plot:Price Variance across RFQs.
WITH params AS (
    SELECT 
        91 AS vendor_id,                         -- change vendor ID
        DATE '2025-01-01' AS start_date,         -- change start date
        DATE '2025-12-31' AS end_date
)
SELECT 
r.id AS rfq_id,
q.id AS quote_id,
rp.requested_price,
q."unitPrice",
((q."unitPrice" - rp.requested_price) / rp.requested_price) * 100 AS price_variance
FROM bt_rfq r
left join  bt_rfq_products rp
on rp.rfq_id = r.id
left join bt_rfq_quotes q
on q.rfq_product_id = rp.id

JOIN params p ON rp.seller_id = p.vendor_id
WHERE r.publish_date BETWEEN p.start_date AND p.end_date

and q."unitPrice" IS NOT NULL
AND rp.requested_price > 0;



---Additional: Response Time Histogram.
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
    JOIN bt_rfq_quotes rq 
	ON rq.id = al.quote_id
    JOIN params p 
	ON rq.seller_id = p.vendor_id
    WHERE al.new_status = 9
      AND al.updated_date BETWEEN p.start_date AND p.end_date
    GROUP BY al.rfq_id
)

SELECT
    p.rfq_id,
    p.publish_date,
    f.first_response_time,
    EXTRACT(EPOCH FROM (f.first_response_time - p.publish_date)) / 60
        AS response_time_mins
FROM publish_times p
JOIN first_vendor_response f
    ON p.rfq_id = f.rfq_id
WHERE f.first_response_time IS NOT NULL;

