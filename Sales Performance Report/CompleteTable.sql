SELECT 
    r.id as rfq_id,
    r.rqf_title,
    r.visibility,
    r.company_id as buyer_id,
    rs.code as rfq_status,
	rs.seller_status,
    rp.product_id,
    rp.rfq_parent_product_id,
    rp.requested_qty,
	rp.SELLER_ID,
    rp.requested_price,
    rp.is_followed,
    rsp.code as product_status,
	rq.rfq_product_id as offered_product_id,
	rq."offeredQty",
	rq."unitPrice",
	rq.discount_percentage,
	rq.seller_id as quote_vendor_id,
	rsq.code as quote_status,
	vp.product_id as available_product_id,
	vp.org_id as vendor_id 
FROM public.bt_rfq r
LEFT JOIN bt_rfq_status rs
    ON r.rfq_status = rs.id
LEFT JOIN bt_rfq_products rp
    ON r.id = rp.rfq_id
LEFT JOIN bt_rfq_status rsp
    ON rp.status = rsp.id 
LEFT JOIN bt_rfq_quotes rq
	ON r.id=rq.rfq_id
LEFT JOIN bt_rfq_status rsq
    ON rq.status = rsq.id 
left join vendor_products vp
	on rp.product_id =vp.product_id
WHERE r.visibility = 'public'
  AND rs.seller_status IN ('Quote Won', 'PO Generated')
ORDER BY r.id ASC;

