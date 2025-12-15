
SELECT
    pm.category,
    o.sku,
    SUM(o.order_value) AS total_order_value,
    SUM(o.quantity) AS total_quantity
FROM orders o
JOIN product_master pm
    ON o.sku = pm.sku
GROUP BY
    pm.category,
    o.sku
ORDER BY
    pm.category,
    total_order_value DESC;

