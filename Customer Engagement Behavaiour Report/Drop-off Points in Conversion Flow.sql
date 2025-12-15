

WITH buyer_steps AS (
    SELECT
        pi.buyer_id,
        pm.category,
        MAX(CASE WHEN pi.event_type = 'view' THEN 1 ELSE 0 END) AS viewed,
        MAX(CASE WHEN pi.event_type = 'add_to_quote' THEN 1 ELSE 0 END) AS quoted
    FROM product_interactions pi
    JOIN product_master pm
        ON pi.sku = pm.sku
    GROUP BY pi.buyer_id, pm.category
)

SELECT
    category,
    COUNT(*) FILTER (WHERE viewed = 1 AND quoted = 0) AS drop_after_view,
    COUNT(*) FILTER (WHERE quoted = 1) AS progressed_to_quote
FROM buyer_steps
GROUP BY category;