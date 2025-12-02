SELECT 
    rfq_received_count,
    quote_submitted_count,
    (quote_submitted_count::decimal / NULLIF(rfq_received_count, 0)) * 100 AS conversion_rate_percentage
FROM (
    SELECT 
        -- RFQ Received (no filters)
        (SELECT COUNT(DISTINCT r.id)
         FROM public.bt_rfq r
         LEFT JOIN bt_rfq_status rs ON r.rfq_status = rs.id
         LEFT JOIN bt_rfq_products rp ON r.id = rp.rfq_id
         LEFT JOIN bt_rfq_status rsp ON rp.status = rsp.id
         LEFT JOIN bt_rfq_quotes rq ON r.id = rq.rfq_id
         LEFT JOIN bt_rfq_status rsq ON rq.status = rsq.id
         LEFT JOIN vendor_products vp ON rp.product_id = vp.product_id
        ) AS rfq_received_count,

        -- Quote Submitted (your filtered logic)
        (SELECT COUNT(DISTINCT r.id)
         FROM public.bt_rfq r
         LEFT JOIN bt_rfq_status rs ON r.rfq_status = rs.id
         LEFT JOIN bt_rfq_products rp ON r.id = rp.rfq_id
         LEFT JOIN bt_rfq_status rsp ON rp.status = rsp.id
         LEFT JOIN bt_rfq_quotes rq ON r.id = rq.rfq_id
         LEFT JOIN bt_rfq_status rsq ON rq.status = rsq.id
         LEFT JOIN vendor_products vp ON rp.product_id = vp.product_id
         WHERE r.visibility = 'private'
           AND rs.seller_status IN ('Quote Won', 'PO Generated')
        ) AS quote_submitted_count
) t;
