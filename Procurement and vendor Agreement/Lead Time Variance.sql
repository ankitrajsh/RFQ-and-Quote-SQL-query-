

-- 2a. Lead Time Variance Overview
SELECT 
    org.company_name AS vendor_name,
    AVG(EXTRACT(EPOCH FROM (asn.created_date - pd.created_date)) / 86400) AS avg_actual_lead_time_days,
    AVG(EXTRACT(EPOCH FROM (asn.expected_delivery_date - pd.created_date)) / 86400) AS avg_expected_lead_time_days,
    AVG(EXTRACT(EPOCH FROM (asn.created_date - asn.expected_delivery_date)) / 86400) AS avg_lead_time_variance_days,
    COUNT(*) AS total_deliveries
FROM po_details pd
JOIN po_asn asn ON asn.tax_invoice_id IN (
    SELECT ti.id FROM po_tax_invoice ti WHERE ti.po_id = pd.id
)
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
WHERE pd.created_date >= CURRENT_DATE - INTERVAL '180 days'
GROUP BY org.company_name, org.org_id
ORDER BY avg_lead_time_variance_days DESC;

-- 2b. Lead Time Variance Trend (Monthly)
SELECT 
    DATE_TRUNC('month', pd.created_date) AS month,
    AVG(EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400) AS avg_actual_lead_time_days,
    STDDEV(EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400) AS stddev_lead_time,
    COUNT(*) AS po_count
FROM po_details pd
JOIN po_tax_invoice ti ON ti.po_id = pd.id
WHERE pd.created_date >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', pd.created_date)
ORDER BY month;

-- 2c. Lead Time by Vendor and Product Category (for detailed analysis)
-- 2c. Lead Time by Vendor and Product Category (for detailed analysis)
SELECT 
    org.company_name AS vendor_name,
    COALESCE(pi."productName", 'Unknown') AS product_category,
    AVG(EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400) AS avg_lead_time_days,
    MIN(EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400) AS min_lead_time_days,
    MAX(EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400) AS max_lead_time_days,
    COUNT(*) AS order_count
FROM po_details pd
JOIN po_items pi ON pi.po_id = pd.id
JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
WHERE pd.created_date >= CURRENT_DATE - INTERVAL '6 months'
GROUP BY org.company_name, org.org_id, pi."productName"
ORDER BY avg_lead_time_days DESC;

