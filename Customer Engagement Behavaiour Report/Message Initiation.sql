SELECT
    pm.category,
    COUNT(*) AS message_count
FROM product_interactions pi
JOIN product_master pm
    ON pi.sku = pm.sku
WHERE pi.event_type = 'message_init'
GROUP BY pm.category
ORDER BY message_count DESC;