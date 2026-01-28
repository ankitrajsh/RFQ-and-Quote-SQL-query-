SELECT 
    mp.id as product_id,
    mp.product_name,
    mp.sku,
    mp.bluet_sku,
    mp.status,
    SUM(COALESCE(inv.quantity, 0)) as total_stock_quantity,
    AVG(COALESCE(inv.price_per_unit, 0)) as avg_unit_price,
    SUM(COALESCE(inv.quantity, 0) * COALESCE(inv.price_per_unit, 0)) as total_stock_value,
    CASE 
        WHEN SUM(COALESCE(inv.quantity, 0)) = 0 THEN 'Out of Stock'
        WHEN SUM(COALESCE(inv.quantity, 0)) <= inv.reorder_quantity THEN 'Reorder Required'
        ELSE 'In Stock'
    END as stock_status
FROM master_products mp
LEFT JOIN "inventoryManagement_inventorystock" inv 
    ON mp.id = inv.product
WHERE mp.status = 'A'
GROUP BY mp.id, mp.product_name, mp.sku, mp.bluet_sku, mp.status, inv.reorder_quantity
ORDER BY total_stock_value DESC NULLS LAST;