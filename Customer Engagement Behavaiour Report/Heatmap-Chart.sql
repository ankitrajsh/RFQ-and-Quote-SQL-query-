
SELECT
    pi.sku,
    pi.event_type,
    COUNT(*) AS interaction_count
FROM product_interactions pi
GROUP BY pi.sku, pi.event_type;

