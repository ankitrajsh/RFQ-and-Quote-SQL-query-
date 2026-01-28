
-- Overall Inventory Value Summary
SELECT 
    COUNT(DISTINCT mp.id) as total_products,
    COUNT(DISTINCT CASE WHEN inv.quantity > 0 THEN mp.id END) as products_in_stock,
    SUM(COALESCE(inv.quantity, 0)) as total_units,
    ROUND(SUM(COALESCE(inv.quantity, 0) * COALESCE(inv.price_per_unit, 0))::numeric, 2) as total_inventory_value,
    ROUND(AVG(COALESCE(inv.price_per_unit, 0))::numeric, 2) as avg_unit_price,
    ROUND(AVG(COALESCE(inv.quantity, 0))::numeric, 2) as avg_quantity_per_product
FROM master_products mp
LEFT JOIN "inventoryManagement_inventorystock" inv ON mp.id = inv.product
WHERE mp.status = 'A';

-- Inventory Value by Warehouse
SELECT 
    w.id as warehouse_id,
    w.name as warehouse_name,
    COUNT(DISTINCT inv.product) as product_count,
    SUM(inv.quantity) as total_units,
    ROUND(SUM(inv.quantity * inv.price_per_unit)::numeric, 2) as inventory_value,
    ROUND(100.0 * SUM(inv.quantity * inv.price_per_unit) / 
          SUM(SUM(inv.quantity * inv.price_per_unit)) OVER (), 2) as percentage_of_total_value
FROM "inventoryManagement_inventorystock" inv
JOIN "inventoryManagement_warehouse" w ON inv.warehouse_id = w.id
JOIN master_products mp ON inv.product = mp.id
WHERE inv.quantity > 0
  AND mp.status = 'A'
GROUP BY w.id, w.name
ORDER BY inventory_value DESC;

-- Top 20 Products by Inventory Value
SELECT 
    mp.id as product_id,
    mp.product_name,
    mp.sku,
    mp.bluet_sku,
    SUM(inv.quantity) as total_stock_quantity,
    AVG(inv.price_per_unit) as avg_unit_price,
    ROUND(SUM(inv.quantity * inv.price_per_unit)::numeric, 2) as total_inventory_value,
    ROUND(100.0 * SUM(inv.quantity * inv.price_per_unit) / 
          SUM(SUM(inv.quantity * inv.price_per_unit)) OVER (), 2) as percentage_of_total_value,
    COUNT(DISTINCT inv.warehouse_id) as warehouses_count
FROM master_products mp
JOIN "inventoryManagement_inventorystock" inv ON mp.id = inv.product
WHERE inv.quantity > 0
  AND mp.status = 'A'
GROUP BY mp.id, mp.product_name, mp.sku, mp.bluet_sku
ORDER BY total_inventory_value DESC
LIMIT 20;

-- Inventory Value Trend (Last 12 Months)
SELECT 
    DATE_TRUNC('month', sl.posting_datetime) as month,
    ROUND(AVG(sl.balance_value)::numeric, 2) as avg_inventory_value,
    ROUND(SUM(CASE WHEN sl.transaction_type IN ('in', 'purchase') THEN sl.rate_value ELSE 0 END)::numeric, 2) as total_inflow_value,
    ROUND(SUM(CASE WHEN sl.transaction_type IN ('out', 'sale', 'consumption') THEN sl.rate_value ELSE 0 END)::numeric, 2) as total_outflow_value
FROM "inventoryManagement_stockledger" sl
WHERE sl.posting_datetime >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', sl.posting_datetime)
ORDER BY month DESC;
