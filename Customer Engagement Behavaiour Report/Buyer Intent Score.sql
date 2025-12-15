
WITH buyer_intent AS (
    SELECT
        pi.buyer_id,
        pm.category,
        SUM(
            CASE pi.event_type
                WHEN 'view' THEN 1
                WHEN 'wishlist' THEN 2
                WHEN 'add_to_quote' THEN 3
                WHEN 'message' THEN 4
                ELSE 0
            END
        ) AS intent_score
    FROM product_interactions pi
    JOIN product_master pm
        ON pi.sku = pm.sku
    GROUP BY pi.buyer_id, pm.category
)

SELECT
    category,
    AVG(intent_score) AS avg_intent_score
FROM buyer_intent
GROUP BY category
ORDER BY avg_intent_score DESC;

