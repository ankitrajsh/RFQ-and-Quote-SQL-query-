
-- Summary Statistics
WITH last_movement AS (
    SELECT 
        inventory_id_id,
        MAX(posting_datetime) as last_transaction_date
    FROM "inventoryManagement_stockledger"
    WHERE transaction_type IN ('OUT')
    GROUP BY inventory_id_id
),
stock_analysis AS (
    SELECT 
        inv.id as inventory_id,
        mp.id as product_id,
        mp.product_name,
        mp.sku,
        inv.quantity as current_stock,
        inv.quantity * inv.price_per_unit as stock_value,
        lm.last_transaction_date,
        CURRENT_DATE - DATE(lm.last_transaction_date) as days_since_last_movement,
        w.name as warehouse_name
    FROM "inventoryManagement_inventorystock" inv
    JOIN master_products mp ON inv.product = mp.id
    LEFT JOIN last_movement lm ON inv.id = lm.inventory_id_id
    LEFT JOIN "inventoryManagement_warehouse" w ON inv.warehouse_id = w.id
    WHERE mp.status = 'A'
      AND inv.quantity > 0
)
SELECT 
    COUNT(CASE WHEN days_since_last_movement > 90 OR last_transaction_date IS NULL THEN 1 END) as dead_stock_items,
    COUNT(*) as total_stocked_items,
    ROUND(100.0 * COUNT(CASE WHEN days_since_last_movement > 90 OR last_transaction_date IS NULL THEN 1 END) / 
          NULLIF(COUNT(*), 0), 2) as dead_stock_percentage,
    ROUND(SUM(CASE WHEN days_since_last_movement > 90 OR last_transaction_date IS NULL THEN stock_value ELSE 0 END)::numeric, 2) as dead_stock_value,
    ROUND(SUM(stock_value)::numeric, 2) as total_inventory_value,
    ROUND(100.0 * SUM(CASE WHEN days_since_last_movement > 90 OR last_transaction_date IS NULL THEN stock_value ELSE 0 END) /
          NULLIF(SUM(stock_value), 0), 2) as dead_stock_value_percentage
FROM stock_analysis;









-- Detailed Dead Stock List
WITH last_movement AS (
    SELECT 
        inventory_id_id,
        MAX(posting_datetime) as last_transaction_date
    FROM "inventoryManagement_stockledger"
    WHERE transaction_type IN ('OUT')
    GROUP BY inventory_id_id
)
SELECT 
    mp.id as product_id,
    mp.product_name,
    mp.sku,
    mp.bluet_sku,
    inv.quantity as current_stock,
    ROUND((inv.quantity * inv.price_per_unit)::numeric, 2) as stock_value,
    lm.last_transaction_date,
    CURRENT_DATE - DATE(lm.last_transaction_date) as days_since_last_movement,
    w.name as warehouse_name,
    CASE 
        WHEN lm.last_transaction_date IS NULL THEN 'Never Moved'
        WHEN CURRENT_DATE - DATE(lm.last_transaction_date) > 365 THEN 'Critical - 1+ year'
        WHEN CURRENT_DATE - DATE(lm.last_transaction_date) > 180 THEN 'Very High Risk - 180+ days'
        WHEN CURRENT_DATE - DATE(lm.last_transaction_date) > 90 THEN 'Dead Stock - 90+ days'
        ELSE 'Active'
    END as stock_status
FROM "inventoryManagement_inventorystock" inv
JOIN master_products mp ON inv.product = mp.id
LEFT JOIN last_movement lm ON inv.id = lm.inventory_id_id
LEFT JOIN "inventoryManagement_warehouse" w ON inv.warehouse_id = w.id
WHERE mp.status = 'A'
  AND inv.quantity > 0
  AND (CURRENT_DATE - DATE(lm.last_transaction_date) > 90 OR lm.last_transaction_date IS NULL)
ORDER BY days_since_last_movement DESC NULLS FIRST, stock_value DESC;




-- Dead Stock by Warehouse
WITH last_movement AS (
    SELECT 
        inventory_id_id,
        MAX(posting_datetime) as last_transaction_date
    FROM "inventoryManagement_stockledger"
    WHERE transaction_type IN ('OUT')
    GROUP BY inventory_id_id
)
SELECT 
    w.name as warehouse_name,
    COUNT(CASE WHEN CURRENT_DATE - DATE(lm.last_transaction_date) > 90 OR lm.last_transaction_date IS NULL THEN 1 END) as dead_stock_items,
    COUNT(*) as total_items,
    ROUND(100.0 * COUNT(CASE WHEN CURRENT_DATE - DATE(lm.last_transaction_date) > 90 OR lm.last_transaction_date IS NULL THEN 1 END) / 
          NULLIF(COUNT(*), 0), 2) as dead_stock_percentage,
    ROUND(SUM(CASE WHEN CURRENT_DATE - DATE(lm.last_transaction_date) > 90 OR lm.last_transaction_date IS NULL 
                   THEN inv.quantity * inv.price_per_unit ELSE 0 END)::numeric, 2) as dead_stock_value
FROM "inventoryManagement_inventorystock" inv
JOIN master_products mp ON inv.product = mp.id
LEFT JOIN last_movement lm ON inv.id = lm.inventory_id_id
JOIN "inventoryManagement_warehouse" w ON inv.warehouse_id = w.id
WHERE mp.status = 'A'
  AND inv.quantity > 0
GROUP BY w.name
ORDER BY dead_stock_percentage DESC;
