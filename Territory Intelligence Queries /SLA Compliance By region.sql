




-- 4a. SLA Compliance by Region
SELECT 
    COALESCE(ua.region, ua.city, 'Unassigned') AS zone,
    COUNT(*) AS total_deliveries,
    COUNT(CASE WHEN ti.created_date <= asn.expected_delivery_date THEN 1 END) AS on_time_deliveries,
    COUNT(CASE WHEN ti.created_date > asn.expected_delivery_date THEN 1 END) AS late_deliveries,
    ROUND((COUNT(CASE WHEN ti.created_date <= asn.expected_delivery_date THEN 1 END) * 100.0 / 
           NULLIF(COUNT(*), 0))::numeric, 2) AS sla_compliance_pct,
    ROUND(AVG(EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400)::numeric, 1) AS avg_delivery_days
FROM po_details pd
JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN po_asn asn ON asn.tax_invoice_id = ti.id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
WHERE pd.created_date >= CURRENT_DATE - INTERVAL '12 months'
AND asn.expected_delivery_date IS NOT NULL
GROUP BY ua.region, ua.city
ORDER BY sla_compliance_pct DESC;