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
