
WITH stock_movements AS (
    SELECT 
        inventory_id_id as inventory_id,
        AVG(CASE 
            WHEN transaction_type IN ('OUT') 
            THEN ABS(quantity) 
            ELSE 0 
        END) as avg_daily_outflow
    FROM "inventoryManagement_stockledger"
    WHERE posting_datetime >= CURRENT_DATE - INTERVAL '365 days'
      AND transaction_type IN ('OUT')
    GROUP BY inventory_id_id
)
SELECT 
    mp.id as product_id,
    mp.product_name,
    mp.sku,
    inv.quantity as current_stock,
    COALESCE(sm.avg_daily_outflow, 0) as avg_daily_sales,
    CASE 
        WHEN sm.avg_daily_outflow > 0 
        THEN ROUND((inv.quantity / sm.avg_daily_outflow)::numeric, 1)
        ELSE NULL 
    END as days_of_inventory,
    w.name as warehouse_name,
    CASE
        WHEN inv.quantity / NULLIF(sm.avg_daily_outflow, 0) < 7 THEN 'Critical - Less than 1 week'
        WHEN inv.quantity / NULLIF(sm.avg_daily_outflow, 0) < 30 THEN 'Low - Less than 1 month'
        WHEN inv.quantity / NULLIF(sm.avg_daily_outflow, 0) > 90 THEN 'Excess - More than 3 months'
        ELSE 'Optimal'
    END as inventory_status
FROM "inventoryManagement_inventorystock" inv
JOIN master_products mp ON inv.product = mp.id
LEFT JOIN stock_movements sm ON inv.id = sm.inventory_id
LEFT JOIN "inventoryManagement_warehouse" w ON inv.warehouse_id = w.id
WHERE mp.status = 'A'
  AND inv.quantity > 0
ORDER BY days_of_inventory ASC NULLS LAST;


