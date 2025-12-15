
SELECT
    pi.sku AS source,
    pi.event_type AS target,
    COUNT(*) AS value
FROM product_interactions pi
GROUP BY pi.sku, pi.event_type;
