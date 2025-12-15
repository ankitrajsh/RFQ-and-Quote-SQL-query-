
SELECT
    pm.category,
    COUNT(*) AS wishlist_count
FROM product_interactions pi
JOIN product_master pm
    ON pi.sku = pm.sku
WHERE pi.event_type = 'wishlist'
GROUP BY pm.category
ORDER BY wishlist_count DESC;

