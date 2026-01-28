
-- Stock Level by Warehouse
SELECT 
    w.id as warehouse_id,
    w.name as warehouse_name,
    mp.id as product_id,
    mp.product_name,
    mp.sku,
    inv.quantity as stock_quantity,
    inv.price_per_unit,
    inv.quantity * inv.price_per_unit as stock_value,
    inv.reorder_quantity,
    inv.auto_reorder,
    CASE 
        WHEN inv.quantity = 0 THEN 'Out of Stock'
        WHEN inv.quantity <= inv.reorder_quantity THEN 'Low Stock'
        ELSE 'Adequate'
    END as stock_status
FROM "inventoryManagement_inventorystock" inv
JOIN master_products mp ON inv.product = mp.id
JOIN "inventoryManagement_warehouse" w ON inv.warehouse_id = w.id
WHERE mp.status = 'A'
ORDER BY stock_value DESC;

