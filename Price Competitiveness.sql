WITH winning_quotes_raw AS (
    SELECT
        rq.rfq_id,
        rq.id AS quote_id,
        rq."unitPrice" AS unit_price,
        rq."offeredQty" AS offered_qty
    FROM bt_rfq_activity_logs al
    JOIN bt_rfq_quotes rq
      ON al.quote_id = rq.id
    WHERE al.new_status IN (5,6)
),

winning_quote_per_rfq AS (
    SELECT DISTINCT ON (rfq_id)
        rfq_id,
        quote_id,
        unit_price AS min_win_price,
        offered_qty  AS min_win_quantity
    FROM winning_quotes_raw
    ORDER BY rfq_id, unit_price ASC, 
	quote_id ASC
)

SELECT 
    r.id,
    al.updated_date,
    al.new_status,
    rs.code,
    rs.level,
    al.quote_id,
    al.rfq_id,
    al.rfq_product_id,
    al.updated_by,
    r.visibility,
    r.publish_date AS rfq_publish_date,
    r.expiry_date AS rfq_expiry_date,
    r.customer_id AS buyer_id,
    r.company_id AS buyer_org_id,
    rp.seller_id AS product_seller_id,
    rp.product_id AS rfq_product_id,
    rp.rfq_parent_product_id,
    rp.requested_qty,
    rp.requested_price,
    rp.product_type,
    rp.is_followed,
    rq.seller_id AS quote_seller_id,
    rq.expiry_date AS quote_expiry_date,
    rq."offeredQty",
    rq."unitPrice",
    rq.mdate AS responded_date,
    rq.discount_percentage,
    rq.delivery_date,
    rq.shipping_charges,
    rq.logistics_charges,
    rq.insurance_charges,
    rq.gst,

    CASE 
        WHEN al.new_status IN (5, 6) THEN 1
        ELSE 0
    END AS win_loss_flag,

    CASE 
        WHEN w.min_win_quantity IS NOT NULL THEN w.min_win_quantity
        WHEN al.new_status IN (5,6) THEN rq."offeredQty"   
        ELSE NULL
    END AS win_quantity,

    CASE 
        WHEN w.min_win_price IS NOT NULL THEN w.min_win_price
        WHEN al.new_status IN (5,6) THEN rq."unitPrice"    
        ELSE NULL
    END AS win_price,

    CASE 
        WHEN w.min_win_price IS NULL THEN NULL
        ELSE (w.min_win_price - rq."unitPrice")
    END AS price_difference,

    CASE 
        WHEN w.min_win_price IS NULL OR w.min_win_price = 0 THEN NULL
        ELSE ROUND( ((w.min_win_price - rq."unitPrice") * 100.0 / w.min_win_price)::numeric, 2 )
    END AS price_competitiveness_percentage

FROM bt_rfq r
LEFT JOIN bt_rfq_activity_logs al
    ON r.id = al.rfq_id 
LEFT JOIN bt_rfq_status rs
    ON al.new_status = rs.id
LEFT JOIN bt_rfq_products rp
    ON al.rfq_product_id = rp.id
LEFT JOIN bt_rfq_quotes rq
    ON al.quote_id = rq.id
    AND al.rfq_id = rq.rfq_id
LEFT JOIN winning_quote_per_rfq w
    ON w.rfq_id = r.id;
