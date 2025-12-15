
WITH views_by_product AS (
    SELECT
        pm.category,
        pi.sku,
        COUNT(*) AS total_views
    FROM product_interactions pi
    JOIN product_master pm
        ON pi.sku = pm.sku
    WHERE pi.event_type = 'view'
    GROUP BY pm.category, pi.sku
)

SELECT
    category,
    SUM(total_views) * 1.0 / COUNT(DISTINCT sku) AS avg_views_per_product
FROM views_by_product
GROUP BY category
ORDER BY avg_views_per_product DESC;