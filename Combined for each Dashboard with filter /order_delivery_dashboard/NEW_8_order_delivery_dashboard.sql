/*
================================================================================
DASHBOARD 8: ORDER-TO-DELIVERY PERFORMANCE DASHBOARD
================================================================================
Purpose: "How efficient is my order fulfillment process?"
Data Source: po_details, po_tax_invoice, po_asn

KPIs:
- Orders Received
- Orders with Invoice
- Orders Shipped (ASN Created)
- Orders Delivered
- Avg PO → Invoice Time
- Avg PO → Delivery Time
- Fulfillment Rate %

Charts:
- Order Fulfillment Funnel (PO → Invoice → ASN → Delivered)
- Cycle Time Trend
- Delivery Performance by Buyer
- On-Time Delivery Rate
================================================================================
*/

/*----------------------------------------------------------------
8.1 MAIN KPIs: Order-to-Delivery Metrics
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

orders AS (
    SELECT 
        pd.id AS po_id,
        pd.created_date AS po_date,
        pd.buyer_org_id
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
),

invoices AS (
    SELECT DISTINCT 
        ti.po_id,
        ti.created_date AS invoice_date
    FROM po_tax_invoice ti
    JOIN orders o ON ti.po_id = o.po_id
),

shipments AS (
    SELECT 
        asn.tax_invoice_id,
        ti.po_id,
        asn.created_date AS ship_date,
        asn.expected_delivery_date,
        asn."Actual_delivery_date" AS actual_delivery_date
    FROM po_asn asn
    JOIN po_tax_invoice ti ON asn.tax_invoice_id = ti.id
    JOIN orders o ON ti.po_id = o.po_id
),

delivered AS (
    SELECT * FROM shipments WHERE actual_delivery_date IS NOT NULL
),

cycle_times AS (
    SELECT 
        o.po_id,
        o.po_date,
        i.invoice_date,
        s.ship_date,
        s.actual_delivery_date,
        EXTRACT(EPOCH FROM (i.invoice_date - o.po_date)) / 86400 AS po_to_invoice_days,
        EXTRACT(EPOCH FROM (s.ship_date - i.invoice_date)) / 86400 AS invoice_to_ship_days,
        EXTRACT(EPOCH FROM (s.actual_delivery_date - o.po_date)) / 86400 AS po_to_delivery_days
    FROM orders o
    LEFT JOIN invoices i ON o.po_id = i.po_id
    LEFT JOIN shipments s ON o.po_id = s.po_id
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    (SELECT COUNT(*) FROM orders) AS total_orders,
    (SELECT COUNT(DISTINCT po_id) FROM invoices) AS orders_invoiced,
    (SELECT COUNT(DISTINCT po_id) FROM shipments) AS orders_shipped,
    (SELECT COUNT(DISTINCT po_id) FROM delivered) AS orders_delivered,
    ROUND((SELECT AVG(po_to_invoice_days) FROM cycle_times WHERE po_to_invoice_days IS NOT NULL)::numeric, 1) AS avg_po_to_invoice_days,
    ROUND((SELECT AVG(invoice_to_ship_days) FROM cycle_times WHERE invoice_to_ship_days IS NOT NULL)::numeric, 1) AS avg_invoice_to_ship_days,
    ROUND((SELECT AVG(po_to_delivery_days) FROM cycle_times WHERE po_to_delivery_days IS NOT NULL)::numeric, 1) AS avg_po_to_delivery_days,
    ROUND((SELECT COUNT(DISTINCT po_id) FROM delivered)::numeric * 100 / NULLIF((SELECT COUNT(*) FROM orders), 0), 2) AS fulfillment_rate_pct;


/*----------------------------------------------------------------
8.2 CHART: Order Fulfillment Funnel
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

orders AS (
    SELECT pd.id AS po_id
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
),

funnel AS (
    SELECT 'Orders Received' AS stage, 1 AS stage_order, COUNT(*) AS count FROM orders
    
    UNION ALL
    
    SELECT 'Invoice Created' AS stage, 2 AS stage_order, COUNT(DISTINCT ti.po_id)
    FROM po_tax_invoice ti
    JOIN orders o ON ti.po_id = o.po_id
    
    UNION ALL
    
    SELECT 'Shipped (ASN)' AS stage, 3 AS stage_order, COUNT(DISTINCT ti.po_id)
    FROM po_asn asn
    JOIN po_tax_invoice ti ON asn.tax_invoice_id = ti.id
    JOIN orders o ON ti.po_id = o.po_id
    
    UNION ALL
    
    SELECT 'Delivered' AS stage, 4 AS stage_order, COUNT(DISTINCT ti.po_id)
    FROM po_asn asn
    JOIN po_tax_invoice ti ON asn.tax_invoice_id = ti.id
    JOIN orders o ON ti.po_id = o.po_id
    WHERE asn."Actual_delivery_date" IS NOT NULL
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    stage,
    stage_order,
    count,
    ROUND(count::numeric * 100 / NULLIF(FIRST_VALUE(count) OVER (ORDER BY stage_order), 0), 2) AS conversion_pct
FROM funnel
ORDER BY stage_order;


/*----------------------------------------------------------------
8.3 CHART: Monthly Cycle Time Trend
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

cycle_data AS (
    SELECT 
        DATE_TRUNC('month', pd.created_date)::DATE AS month,
        pd.id AS po_id,
        pd.created_date AS po_date,
        ti.created_date AS invoice_date,
        asn.created_date AS ship_date,
        asn."Actual_delivery_date" AS delivery_date
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN po_tax_invoice ti ON pd.id = ti.po_id
    LEFT JOIN po_asn asn ON ti.id = asn.tax_invoice_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    TO_CHAR(month, 'YYYY-MM') AS month,
    COUNT(DISTINCT po_id) AS orders,
    ROUND(AVG(EXTRACT(EPOCH FROM (invoice_date - po_date)) / 86400)::numeric, 1) AS avg_po_to_invoice_days,
    ROUND(AVG(EXTRACT(EPOCH FROM (ship_date - po_date)) / 86400)::numeric, 1) AS avg_po_to_ship_days,
    ROUND(AVG(EXTRACT(EPOCH FROM (delivery_date - po_date)) / 86400)::numeric, 1) AS avg_po_to_delivery_days
FROM cycle_data
GROUP BY month
ORDER BY month;


/*----------------------------------------------------------------
8.4 CHART: Delivery Performance by Buyer
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    pd.buyer_org_id,
    COALESCE(org.company_name, 'Buyer ' || pd.buyer_org_id) AS buyer_name,
    COUNT(DISTINCT pd.id) AS total_orders,
    COUNT(DISTINCT CASE WHEN asn."Actual_delivery_date" IS NOT NULL THEN pd.id END) AS delivered_orders,
    ROUND(
        COUNT(DISTINCT CASE WHEN asn."Actual_delivery_date" IS NOT NULL THEN pd.id END)::numeric * 100 
        / NULLIF(COUNT(DISTINCT pd.id), 0), 
        2
    ) AS fulfillment_rate_pct,
    -- On-time rate: delivered on or before expected delivery date
    ROUND(
        COUNT(DISTINCT CASE 
            WHEN asn."Actual_delivery_date" IS NOT NULL 
                 AND asn."Actual_delivery_date" <= COALESCE(asn.expected_delivery_date, asn."Actual_delivery_date")
            THEN pd.id 
        END)::numeric * 100 
        / NULLIF(COUNT(DISTINCT CASE WHEN asn."Actual_delivery_date" IS NOT NULL THEN pd.id END), 0), 
        2
    ) AS on_time_rate,
    ROUND(
        AVG(
            CASE WHEN asn."Actual_delivery_date" IS NOT NULL 
            THEN (asn."Actual_delivery_date" - pd.created_date::DATE)
            END
        )::numeric, 
        1
    ) AS avg_cycle_days
FROM po_details pd
JOIN params p ON pd.seller_org_id = p.vendor_id
LEFT JOIN po_tax_invoice ti ON pd.id = ti.po_id
LEFT JOIN po_asn asn ON ti.id = asn.tax_invoice_id
LEFT JOIN "userApis_organization" org ON pd.buyer_org_id = org.org_id
WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
  AND pd.buyer_org_id IS NOT NULL
GROUP BY pd.buyer_org_id, org.company_name
HAVING COUNT(DISTINCT pd.id) >= 3  -- Only buyers with 3+ orders
ORDER BY total_orders DESC
LIMIT 10;


/*----------------------------------------------------------------
8.5 CHART: On-Time Delivery Analysis
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

delivery_data AS (
    SELECT 
        pd.id AS po_id,
        asn.expected_delivery_date,
        asn."Actual_delivery_date" AS actual_delivery_date,
        CASE 
            WHEN asn."Actual_delivery_date" IS NULL THEN 'Not Delivered'
            WHEN asn."Actual_delivery_date" <= asn.expected_delivery_date THEN 'On Time'
            WHEN asn."Actual_delivery_date" <= asn.expected_delivery_date + INTERVAL '3 days' THEN '1-3 Days Late'
            WHEN asn."Actual_delivery_date" <= asn.expected_delivery_date + INTERVAL '7 days' THEN '4-7 Days Late'
            ELSE '7+ Days Late'
        END AS delivery_status
    FROM po_details pd
    JOIN params p ON pd.seller_org_id = p.vendor_id
    LEFT JOIN po_tax_invoice ti ON pd.id = ti.po_id
    LEFT JOIN po_asn asn ON ti.id = asn.tax_invoice_id
    WHERE pd.created_date::DATE BETWEEN p.start_date AND p.end_date
      AND asn.id IS NOT NULL
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    delivery_status,
    COUNT(*) AS order_count,
    ROUND(COUNT(*)::numeric * 100 / NULLIF(SUM(COUNT(*)) OVER (), 0), 2) AS percentage
FROM delivery_data
GROUP BY delivery_status
ORDER BY 
    CASE delivery_status 
        WHEN 'On Time' THEN 1
        WHEN '1-3 Days Late' THEN 2
        WHEN '4-7 Days Late' THEN 3
        WHEN '7+ Days Late' THEN 4
        ELSE 5
    END;
