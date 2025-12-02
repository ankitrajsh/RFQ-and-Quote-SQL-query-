SELECT 
    COUNT(DISTINCT r.id) AS unique_rfq_count
FROM public.bt_rfq r
LEFT JOIN bt_rfq_status rs
    ON r.rfq_status = rs.id
LEFT JOIN bt_rfq_products rp
    ON r.id = rp.rfq_id
LEFT JOIN bt_rfq_status rsp
    ON rp.status = rsp.id 
LEFT JOIN bt_rfq_quotes rq
    ON r.id = rq.rfq_id
LEFT JOIN bt_rfq_status rsq
    ON rq.status = rsq.id 
LEFT JOIN vendor_products vp
    ON rp.product_id = vp.product_id
WHERE r.visibility = 'private'
and rs.seller_status ='Quote Won';
