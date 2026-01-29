
-- 1a. Overall PO Fulfillment %
SELECT 
    COUNT(CASE WHEN pd.status IN (5, 6, 7, 8) THEN 1 END) * 100.0 / 
    NULLIF(COUNT(*), 0) AS po_fulfillment_percentage,
    COUNT(*) AS total_pos,
    COUNT(CASE WHEN pd.status IN (5, 6, 7, 8) THEN 1 END) AS fulfilled_pos
FROM po_details pd
WHERE pd.created_date >= CURRENT_DATE - INTERVAL '30 days';

-- 1b. PO Fulfillment % by Vendor (with filters)
SELECT 
    org.company_name AS vendor_name,
    org.org_id AS vendor_id,
    COUNT(*) AS total_pos,
    COUNT(CASE WHEN pd.status IN (5, 6, 7, 8) THEN 1 END) AS fulfilled_pos,
    COUNT(CASE WHEN pd.status IN (5, 6, 7, 8) THEN 1 END) * 100.0 / 
    NULLIF(COUNT(*), 0) AS fulfillment_percentage
FROM po_details pd
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
-- FILTER: Add WHERE clauses for vendor, material, region
-- WHERE org.org_id = :vendor_id  -- Vendor Filter
-- AND org.region = :region       -- Region Filter
WHERE pd.created_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY org.company_name, org.org_id
ORDER BY fulfillment_percentage DESC;

-- 1c. PO Fulfillment % by Product/Material
SELECT 
    COALESCE(pi."productName", 'Unknown Product') AS material_name,
    pi.product_id,
    COUNT(DISTINCT pd.id) AS total_pos,
    COUNT(DISTINCT CASE WHEN pd.status IN (5, 6, 7, 8) THEN pd.id END) AS fulfilled_pos,
    COUNT(DISTINCT CASE WHEN pd.status IN (5, 6, 7, 8) THEN pd.id END) * 100.0 / 
    NULLIF(COUNT(DISTINCT pd.id), 0) AS fulfillment_percentage
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
WHERE pd.created_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY pi."productName", pi.product_id
ORDER BY fulfillment_percentage DESC
LIMIT 50;




