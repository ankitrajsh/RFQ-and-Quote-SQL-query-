
WITH buyer_frequency AS (
    SELECT
        pi.buyer_id,
        pm.category,
        COUNT(*) AS interaction_count
    FROM product_interactions pi
    JOIN product_master pm
        ON pi.sku = pm.sku
    GROUP BY pi.buyer_id, pm.category
)

SELECT
    category,
    CASE
        WHEN interaction_count >= 20 THEN 'High'
        WHEN interaction_count >= 10 THEN 'Medium'
        ELSE 'Low'
    END AS engagement_segment,
    COUNT(*) AS buyers
FROM buyer_frequency
GROUP BY category, engagement_segment
ORDER BY category, buyers DESC;