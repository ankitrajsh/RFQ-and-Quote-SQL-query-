/*
================================================================================
DASHBOARD 3: OPERATIONS & FULFILLMENT DASHBOARD
================================================================================
Purpose: "Am I delivering reliably?"
Combines: Logistics & Fulfillment + Inventory Management

KPIs:
- On-Time Delivery Rate %
- Avg Delivery Time (days)
- Promised SLA (days)
- Return/RTO Rate %
- Current Stock Level
- Dead Stock %

Charts:
- Gauge: On-Time Delivery Rate
- Bar Chart: Delivery Performance vs SLA
- Pie Chart: Shipment Status Breakdown
- Table: Inventory Health Summary
================================================================================
*/

/*----------------------------------------------------------------
3.1 MAIN KPIs: Delivery & Fulfillment Metrics
-----------------------------------------------------------------*/

WITH params AS (
    SELECT
        509::bigint AS seller_org_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

-- On-Time Delivery Rate
otd_data AS (
    SELECT
        a.seller_org_id,
        a."Actual_delivery_date",
        a.expected_delivery_date
    FROM po_asn a
    JOIN params p ON a.seller_org_id = p.seller_org_id
    WHERE "Actual_delivery_date" IS NOT NULL
),

otd_metrics AS (
    SELECT
        ROUND(
            100.0 * AVG(
                CASE
                    WHEN "Actual_delivery_date"::date <= expected_delivery_date
                    THEN 1
                    ELSE 0
                END
            ),
            2
        ) AS on_time_delivery_rate_pct
    FROM otd_data
),

-- Avg Delivery Time & SLA
delivery_time_data AS (
    SELECT
        a.seller_org_id,
        a."Actual_delivery_date",
        a.created_date,
        a.expected_delivery_date
    FROM po_asn a
    JOIN params p ON a.seller_org_id = p.seller_org_id
),

delivery_metrics AS (
    SELECT
        ROUND(
            AVG(EXTRACT(EPOCH FROM ("Actual_delivery_date" - created_date))) / 86400,
            1
        ) AS avg_actual_delivery_days,
        ROUND(
            AVG(expected_delivery_date - created_date::date),
            1
        ) AS avg_promised_sla_days
    FROM delivery_time_data
),

-- Return/RTO Rate
shipment_data AS (
    SELECT
        a.id,
        a.seller_org_id,
        a.status
    FROM po_asn a
    JOIN params p ON a.seller_org_id = p.seller_org_id
),

rto_metrics AS (
    SELECT
        COUNT(*) AS total_shipments,
        COUNT(*) FILTER (WHERE status = '19') AS undelivered_shipments,
        COUNT(*) FILTER (WHERE status = '20') AS returns,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE status IN ('19', '20'))
            / NULLIF(COUNT(*), 0),
            2
        ) AS return_rto_rate_pct
    FROM shipment_data
)

SELECT 
    (SELECT seller_org_id FROM params) AS vendor_id,
    otd.on_time_delivery_rate_pct,
    dm.avg_actual_delivery_days,
    dm.avg_promised_sla_days,
    rto.total_shipments,
    rto.undelivered_shipments,
    rto.returns,
    rto.return_rto_rate_pct
FROM otd_metrics otd
CROSS JOIN delivery_metrics dm
CROSS JOIN rto_metrics rto;


/*----------------------------------------------------------------
3.2 KPIs: Inventory Health Metrics
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        NULL::INTEGER AS warehouse_id,
        NULL::TEXT AS sku,
        91::INTEGER AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

filtered_inventory AS (
    SELECT 
        inv.id AS inventory_id,
        inv.product,
        inv.warehouse_id,
        inv.quantity,
        inv.price_per_unit,
        mp.id AS product_id,
        mp.product_name,
        mp.sku,
        w.name AS warehouse_name
    FROM "inventoryManagement_inventorystock" inv
    INNER JOIN master_products mp ON inv.product = mp.id
    LEFT JOIN "inventoryManagement_warehouse" w ON inv.warehouse_id = w.id
    CROSS JOIN params p
    WHERE mp.status = 'A'
      AND inv.quantity > 0
      AND (p.warehouse_id IS NULL OR inv.warehouse_id = p.warehouse_id)
      AND (p.sku IS NULL OR mp.sku = p.sku)
      AND (p.vendor_id IS NULL OR inv.org_id = p.vendor_id)
),

stock_movements AS (
    SELECT 
        sl.inventory_id_id AS inventory_id,
        AVG(CASE WHEN sl.transaction_type = 'OUT' THEN ABS(sl.quantity) END) AS avg_daily_outflow,
        SUM(CASE WHEN sl.transaction_type = 'OUT' THEN ABS(sl.quantity * sl.price_per_unit) ELSE 0 END) AS total_cogs,
        AVG(sl.balance_value) AS avg_balance_value,
        MAX(CASE WHEN sl.transaction_type = 'OUT' THEN sl.posting_datetime END) AS last_sale_date
    FROM "inventoryManagement_stockledger" sl
    CROSS JOIN params p
    WHERE sl.posting_datetime BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR sl.org_id = p.vendor_id)
    GROUP BY sl.inventory_id_id
),

product_metrics AS (
    SELECT 
        fi.product_id,
        fi.quantity AS current_stock,
        CASE 
            WHEN COALESCE(sm.avg_daily_outflow, 0) > 0 
            THEN ROUND((fi.quantity / sm.avg_daily_outflow)::NUMERIC, 1)
            ELSE NULL 
        END AS days_of_inventory,
        CASE 
            WHEN sm.last_sale_date IS NULL 
                 OR sm.last_sale_date < CURRENT_DATE - INTERVAL '90 days' 
            THEN 1 
            ELSE 0 
        END AS is_dead_stock
    FROM filtered_inventory fi
    LEFT JOIN stock_movements sm ON fi.inventory_id = sm.inventory_id
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    SUM(current_stock) AS stock_level,
    ROUND(
        SUM(current_stock * COALESCE(days_of_inventory, 0)) / 
        NULLIF(SUM(CASE WHEN days_of_inventory IS NOT NULL THEN current_stock END), 0)
    , 0)::INTEGER AS days_of_inventory,
    ROUND(100.0 * SUM(is_dead_stock) / NULLIF(COUNT(*), 0), 2) AS dead_stock_pct,
    COUNT(*) AS total_products
FROM product_metrics;


/*----------------------------------------------------------------
3.3 CHART: Delivery Performance vs SLA (Bar Chart)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT
        509::bigint AS seller_org_id
)

SELECT
    'Actual Delivery (Avg Days)' AS metric,
    ROUND(
        AVG(EXTRACT(EPOCH FROM ("Actual_delivery_date" - created_date))) / 86400,
        1
    ) AS days
FROM po_asn a
JOIN params p ON a.seller_org_id = p.seller_org_id

UNION ALL

SELECT
    'Promised SLA (Avg Days)' AS metric,
    ROUND(
        AVG(expected_delivery_date - created_date::date),
        1
    ) AS days
FROM po_asn a
JOIN params p ON a.seller_org_id = p.seller_org_id;


/*----------------------------------------------------------------
3.4 CHART: Shipment Status Breakdown (Pie Chart)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT
        509::bigint AS seller_org_id
),

shipment_data AS (
    SELECT
        a.id,
        a.status
    FROM po_asn a
    JOIN params p ON a.seller_org_id = p.seller_org_id
)

SELECT
    CASE 
        WHEN status = '19' THEN 'Undelivered'
        WHEN status = '20' THEN 'Returned'
        ELSE 'Delivered'
    END AS shipment_status,
    COUNT(*) AS count,
    ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER(), 0), 2) AS percentage
FROM shipment_data
GROUP BY 
    CASE 
        WHEN status = '19' THEN 'Undelivered'
        WHEN status = '20' THEN 'Returned'
        ELSE 'Delivered'
    END
ORDER BY count DESC;


/*----------------------------------------------------------------
3.5 TABLE: Inventory Health Detail
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        NULL::INTEGER AS warehouse_id,
        91::INTEGER AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

filtered_inventory AS (
    SELECT 
        inv.id AS inventory_id,
        inv.quantity,
        inv.price_per_unit,
        mp.id AS product_id,
        mp.product_name,
        mp.sku,
        w.name AS warehouse_name
    FROM "inventoryManagement_inventorystock" inv
    INNER JOIN master_products mp ON inv.product = mp.id
    LEFT JOIN "inventoryManagement_warehouse" w ON inv.warehouse_id = w.id
    CROSS JOIN params p
    WHERE mp.status = 'A'
      AND inv.quantity > 0
      AND (p.warehouse_id IS NULL OR inv.warehouse_id = p.warehouse_id)
      AND (p.vendor_id IS NULL OR inv.org_id = p.vendor_id)
),

stock_movements AS (
    SELECT 
        sl.inventory_id_id AS inventory_id,
        AVG(CASE WHEN sl.transaction_type = 'OUT' THEN ABS(sl.quantity) END) AS avg_daily_outflow,
        MAX(CASE WHEN sl.transaction_type = 'OUT' THEN sl.posting_datetime END) AS last_sale_date
    FROM "inventoryManagement_stockledger" sl
    CROSS JOIN params p
    WHERE sl.posting_datetime BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR sl.org_id = p.vendor_id)
    GROUP BY sl.inventory_id_id
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    fi.product_name,
    fi.sku,
    fi.warehouse_name,
    fi.quantity AS current_stock,
    CASE 
        WHEN COALESCE(sm.avg_daily_outflow, 0) > 0 
        THEN ROUND((fi.quantity / sm.avg_daily_outflow)::NUMERIC, 0)
        ELSE NULL 
    END AS days_of_inventory,
    CASE 
        WHEN sm.last_sale_date IS NULL 
             OR sm.last_sale_date < CURRENT_DATE - INTERVAL '90 days' 
        THEN 'Yes'
        ELSE 'No'
    END AS is_dead_stock,
    sm.last_sale_date
FROM filtered_inventory fi
LEFT JOIN stock_movements sm ON fi.inventory_id = sm.inventory_id
ORDER BY fi.quantity DESC;


/*----------------------------------------------------------------
3.6 CHART: On-Time vs Late Deliveries (for Gauge context)
-----------------------------------------------------------------*/

WITH params AS (
    SELECT
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

delivery_data AS (
    SELECT
        CASE
            WHEN a."Actual_delivery_date"::date <= a.expected_delivery_date THEN 'On-Time'
            ELSE 'Late'
        END AS delivery_status
    FROM po_asn a
    JOIN params p ON a.seller_org_id = p.vendor_id
    WHERE a."Actual_delivery_date" IS NOT NULL
      AND a.created_date::DATE BETWEEN p.start_date AND p.end_date
)

SELECT
    delivery_status,
    COUNT(*) AS count,
    ROUND(100.0 * COUNT(*) / NULLIF(SUM(COUNT(*)) OVER(), 0), 2) AS percentage
FROM delivery_data
GROUP BY delivery_status
ORDER BY delivery_status;
