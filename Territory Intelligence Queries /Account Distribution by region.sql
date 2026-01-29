



-- 3a. Account Distribution by Region
SELECT 
    COALESCE(org.country, 'Unknown') AS country,
    COALESCE(org.state, 'Unknown') AS state,
    COALESCE(org.city_name, 'Unknown') AS city,
    COUNT(DISTINCT org.org_id) AS total_accounts,
    COUNT(DISTINCT CASE WHEN buyer_activity.org_id IS NOT NULL THEN org.org_id END) AS active_accounts,
    ROUND((COUNT(DISTINCT CASE WHEN buyer_activity.org_id IS NOT NULL THEN org.org_id END) * 100.0 / 
           NULLIF(COUNT(DISTINCT org.org_id), 0))::numeric, 2) AS active_percentage
FROM "userApis_organization" org
LEFT JOIN (
    SELECT DISTINCT buyer_org_id AS org_id 
    FROM po_details 
    WHERE created_date >= CURRENT_DATE - INTERVAL '12 months'
) buyer_activity ON org.org_id = buyer_activity.org_id
WHERE org.is_active = TRUE
GROUP BY org.country, org.state, org.city_name
ORDER BY total_accounts DESC;