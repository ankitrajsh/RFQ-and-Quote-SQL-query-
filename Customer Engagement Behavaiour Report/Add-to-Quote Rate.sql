
SELECT
    pm.category,
    SUM(CASE WHEN pi.event_type = 'add_to_quote' THEN 1 ELSE 0 END) * 1.0
    / NULLIF(SUM(CASE WHEN pi.event_type = 'view' THEN 1 ELSE 0 END), 0)
    AS add_to_quote_rate
FROM product_interactions pi
JOIN product_master pm
    ON pi.sku = pm.sku
GROUP BY pm.category
ORDER BY add_to_quote_rate DESC;