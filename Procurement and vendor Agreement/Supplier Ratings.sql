

-- 3a. Supplier Ratings Summary
-- Using supplier_avg_rating from userApis_organization table
SELECT 
    org.company_name AS supplier_name,
    org.org_id AS supplier_id,
    ROUND(org.supplier_avg_rating::numeric, 2) AS avg_rating,
    COALESCE(org.supplier_rating_count, 0) AS total_ratings,
    org.updated_date AS last_updated
FROM "userApis_organization" org
JOIN po_details pd ON pd.seller_org_id = org.org_id
WHERE org.supplier_avg_rating IS NOT NULL
GROUP BY org.company_name, org.org_id, org.supplier_avg_rating, org.supplier_rating_count, org.updated_date
ORDER BY org.supplier_avg_rating DESC;

-- 3b. Supplier Rating Distribution
SELECT 
    CASE 
        WHEN org.supplier_avg_rating >= 4.5 THEN '4.5-5.0 (Excellent)'
        WHEN org.supplier_avg_rating >= 4.0 THEN '4.0-4.4 (Very Good)'
        WHEN org.supplier_avg_rating >= 3.0 THEN '3.0-3.9 (Good)'
        WHEN org.supplier_avg_rating >= 2.0 THEN '2.0-2.9 (Fair)'
        ELSE '0-1.9 (Poor)'
    END AS rating_range,
    COUNT(*) AS supplier_count
FROM "userApis_organization" org
JOIN po_details pd ON pd.seller_org_id = org.org_id
WHERE org.supplier_avg_rating IS NOT NULL
GROUP BY 
    CASE 
        WHEN org.supplier_avg_rating >= 4.5 THEN '4.5-5.0 (Excellent)'
        WHEN org.supplier_avg_rating >= 4.0 THEN '4.0-4.4 (Very Good)'
        WHEN org.supplier_avg_rating >= 3.0 THEN '3.0-3.9 (Good)'
        WHEN org.supplier_avg_rating >= 2.0 THEN '2.0-2.9 (Fair)'
        ELSE '0-1.9 (Poor)'
    END
ORDER BY rating_range DESC;

-- 3c. Vendor Rating Summary with Order Volume
SELECT 
    org.company_name AS vendor_name,
    ROUND(org.supplier_avg_rating::numeric, 2) AS avg_rating,
    COALESCE(org.supplier_rating_count, 0) AS total_ratings,
    COUNT(DISTINCT pd.id) AS total_orders,
    SUM(pi.total_amount) AS total_order_value,
    CASE 
        WHEN org.supplier_avg_rating >= 4 THEN 'Excellent'
        WHEN org.supplier_avg_rating >= 3 THEN 'Good'
        WHEN org.supplier_avg_rating >= 2 THEN 'Average'
        ELSE 'Poor'
    END AS rating_category
FROM "userApis_organization" org
JOIN po_details pd ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
WHERE org.supplier_avg_rating IS NOT NULL
GROUP BY org.company_name, org.org_id, org.supplier_avg_rating, org.supplier_rating_count
HAVING COUNT(DISTINCT pd.id) >= 3
ORDER BY org.supplier_avg_rating DESC;