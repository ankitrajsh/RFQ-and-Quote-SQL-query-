
WITH stock_outflow AS (
    SELECT 
        sl.inventory_id_id,
        SUM(CASE 
            WHEN sl.transaction_type IN ('OUT') 
            THEN ABS(sl.quantity * sl.price_per_unit)
            ELSE 0 
        END) as total_outflow_value_12m
    FROM "inventoryManagement_stockledger" sl
    WHERE sl.posting_datetime >= CURRENT_DATE - INTERVAL '12 months'
      AND sl.transaction_type IN ('OUT')
    GROUP BY sl.inventory_id_id
),
avg_inventory_value AS (
    SELECT 
        inventory_id_id,
        AVG(balance_value) as avg_inv_value
    FROM "inventoryManagement_stockledger"
    WHERE posting_datetime >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY inventory_id_id
)
SELECT 
    mp.id as product_id,
    mp.product_name,
    mp.sku,
    ROUND(COALESCE(so.total_outflow_value_12m, 0)::numeric, 2) as cogs_last_12_months,
    ROUND(COALESCE(aiv.avg_inv_value, 0)::numeric, 2) as avg_inventory_value,
    CASE 
        WHEN COALESCE(aiv.avg_inv_value, 0) > 0 
        THEN ROUND((so.total_outflow_value_12m / aiv.avg_inv_value)::numeric, 2)
        ELSE 0 
    END as turnover_ratio,
    w.name as warehouse_name,
    CASE
        WHEN so.total_outflow_value_12m / NULLIF(aiv.avg_inv_value, 0) > 12 THEN 'Excellent'
        WHEN so.total_outflow_value_12m / NULLIF(aiv.avg_inv_value, 0) > 6 THEN 'Good'
        WHEN so.total_outflow_value_12m / NULLIF(aiv.avg_inv_value, 0) > 3 THEN 'Average'
        ELSE 'Poor'
    END as turnover_rating
FROM "inventoryManagement_inventorystock" inv
JOIN master_products mp ON inv.product = mp.id
LEFT JOIN stock_outflow so ON inv.id = so.inventory_id_id
LEFT JOIN avg_inventory_value aiv ON inv.id = aiv.inventory_id_id
LEFT JOIN "inventoryManagement_warehouse" w ON inv.warehouse_id = w.id
WHERE mp.status = 'A'
  AND inv.quantity > 0
ORDER BY turnover_ratio DESC NULLS LAST;