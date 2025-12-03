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
