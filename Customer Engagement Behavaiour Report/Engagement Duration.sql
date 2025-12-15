
WITH session_time_by_product AS (
    SELECT
        pm.category,
        pi.sku,
        SUM(pi.session_duration_sec) AS total_session_time
    FROM product_interactions pi
    JOIN product_master pm
        ON pi.sku = pm.sku
    GROUP BY pm.category, pi.sku
)

SELECT
    category,
    SUM(total_session_time) * 1.0 / COUNT(DISTINCT sku) AS avg_session_time_per_product
FROM session_time_by_product
GROUP BY category
ORDER BY avg_session_time_per_product DESC;
