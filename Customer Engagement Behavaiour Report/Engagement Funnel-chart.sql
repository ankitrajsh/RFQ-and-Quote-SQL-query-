
WITH engagement_steps AS (
    SELECT
        pm.category,
        SUM(CASE WHEN pi.event_type = 'view' THEN 1 ELSE 0 END) AS views,
        SUM(CASE WHEN pi.event_type = 'add_to_quote' THEN 1 ELSE 0 END) AS quotes
    FROM product_interactions pi
    JOIN product_master pm
        ON pi.sku = pm.sku
    GROUP BY pm.category
),

orders_by_category AS (
    SELECT
        pm.category,
        COUNT(DISTINCT o.order_id) AS orders
    FROM orders o
    JOIN product_master pm
        ON o.sku = pm.sku
    GROUP BY pm.category
)

SELECT
    e.category,
    e.views,
    e.quotes,
    COALESCE(o.orders, 0) AS orders
FROM engagement_steps e
LEFT JOIN orders_by_category o
    ON e.category = o.category;
