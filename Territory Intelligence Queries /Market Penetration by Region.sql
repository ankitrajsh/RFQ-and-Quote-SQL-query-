-- 2a. Market Penetration by Region
WITH total_accounts AS (
    SELECT 
        COALESCE(org.state, org.country, 'Unknown') AS zone,
        COUNT(DISTINCT org.org_id) AS total_organizations
    FROM "userApis_organization" org
    WHERE org.is_active = TRUE
    GROUP BY COALESCE(org.state, org.country, 'Unknown')
),
active_buyers AS (
    SELECT 
        COALESCE(buyer_org.state, buyer_org.country, 'Unknown') AS zone,
        COUNT(DISTINCT pd.buyer_org_id) AS active_buyer_count,
        SUM(pi.total_amount) AS total_purchase_value
    FROM po_details pd
    JOIN po_items pi ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" buyer_org ON pd.buyer_org_id = buyer_org.org_id
    WHERE pd.created_date >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY COALESCE(buyer_org.state, buyer_org.country, 'Unknown')
)
SELECT 
    ta.zone,
    ta.total_organizations AS potential_accounts,
    COALESCE(ab.active_buyer_count, 0) AS active_buyers,
    ROUND((COALESCE(ab.active_buyer_count, 0) * 100.0 / 
           NULLIF(ta.total_organizations, 0))::numeric, 2) AS penetration_percentage,
    ROUND(COALESCE(ab.total_purchase_value, 0)::numeric, 2) AS total_revenue,
    CASE 
        WHEN (COALESCE(ab.active_buyer_count, 0) * 100.0 / NULLIF(ta.total_organizations, 0)) >= 50 THEN 'HIGH'
        WHEN (COALESCE(ab.active_buyer_count, 0) * 100.0 / NULLIF(ta.total_organizations, 0)) >= 25 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS penetration_level
FROM total_accounts ta
LEFT JOIN active_buyers ab ON ta.zone = ab.zone
ORDER BY penetration_percentage DESC;



