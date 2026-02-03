/*
================================================================================
DASHBOARD 7: INVOICE & CASHFLOW DASHBOARD
================================================================================
Purpose: "What's my billing status and outstanding receivables?"
Data Source: po_tax_invoice, po_details, po_status

KPIs:
- Total Invoiced Amount
- Outstanding Invoice Value
- Paid Invoice Value
- Average Days to Invoice (PO → Invoice)
- Invoice Count

Charts:
- Invoicing Trend (Monthly)
- Invoice Status Breakdown (Pie)
- Receivables Aging Buckets
- Top Outstanding Buyers
================================================================================
*/

/*----------------------------------------------------------------
7.1 MAIN KPIs: Invoice & Cashflow Metrics
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

invoice_data AS (
    SELECT 
        ti.id,
        ti.po_id,
        ti.net_amount,
        ti.status,
        ti.created_date AS invoice_date,
        pd.created_date AS po_date,
        pd.buyer_org_id
    FROM po_tax_invoice ti
    JOIN po_details pd ON ti.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE ti.created_date::DATE BETWEEN p.start_date AND p.end_date
),

invoice_metrics AS (
    SELECT
        COUNT(*) AS invoice_count,
        ROUND(SUM(net_amount)::numeric, 2) AS total_invoiced,
        ROUND(SUM(CASE WHEN status IN (1, 2) THEN net_amount ELSE 0 END)::numeric, 2) AS outstanding_amount,
        ROUND(SUM(CASE WHEN status >= 3 THEN net_amount ELSE 0 END)::numeric, 2) AS paid_amount,
        ROUND(AVG(EXTRACT(EPOCH FROM (invoice_date - po_date)) / 86400)::numeric, 1) AS avg_days_to_invoice
    FROM invoice_data
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    invoice_count,
    total_invoiced,
    outstanding_amount,
    paid_amount,
    avg_days_to_invoice,
    ROUND(paid_amount * 100 / NULLIF(total_invoiced, 0), 2) AS collection_rate_pct
FROM invoice_metrics;


/*----------------------------------------------------------------
7.2 CHART: Monthly Invoicing Trend
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    TO_CHAR(DATE_TRUNC('month', ti.created_date), 'YYYY-MM') AS month,
    COUNT(*) AS invoice_count,
    ROUND(SUM(ti.net_amount)::numeric, 2) AS invoiced_amount
FROM po_tax_invoice ti
JOIN po_details pd ON ti.po_id = pd.id
JOIN params p ON pd.seller_org_id = p.vendor_id
WHERE ti.created_date::DATE BETWEEN p.start_date AND p.end_date
GROUP BY DATE_TRUNC('month', ti.created_date)
ORDER BY month;


/*----------------------------------------------------------------
7.3 CHART: Invoice Status Breakdown
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),

status_map AS (
    SELECT 1 AS status_id, 'Pending' AS status_name UNION ALL
    SELECT 2, 'Sent' UNION ALL
    SELECT 3, 'Paid' UNION ALL
    SELECT 4, 'Partially Paid' UNION ALL
    SELECT 5, 'Cancelled'
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    COALESCE(sm.status_name, 'Unknown') AS status,
    COUNT(*) AS invoice_count,
    ROUND(SUM(ti.net_amount)::numeric, 2) AS amount
FROM po_tax_invoice ti
JOIN po_details pd ON ti.po_id = pd.id
JOIN params p ON pd.seller_org_id = p.vendor_id
LEFT JOIN status_map sm ON ti.status = sm.status_id
WHERE ti.created_date::DATE BETWEEN p.start_date AND p.end_date
GROUP BY COALESCE(sm.status_name, 'Unknown')
ORDER BY amount DESC;


/*----------------------------------------------------------------
7.4 CHART: Receivables Aging Buckets
-----------------------------------------------------------------*/

WITH params AS (
    SELECT 
        91 AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        CURRENT_DATE AS today
),

outstanding_invoices AS (
    SELECT 
        ti.id,
        ti.net_amount,
        ti.created_date,
        EXTRACT(DAY FROM (CURRENT_DATE - ti.created_date::DATE)) AS days_outstanding
    FROM po_tax_invoice ti
    JOIN po_details pd ON ti.po_id = pd.id
    JOIN params p ON pd.seller_org_id = p.vendor_id
    WHERE ti.status IN (1, 2)  -- Pending or Sent
      AND ti.created_date::DATE BETWEEN p.start_date AND p.end_date
),

aging_buckets AS (
    SELECT 
        CASE 
            WHEN days_outstanding <= 30 THEN '0-30 days'
            WHEN days_outstanding <= 60 THEN '31-60 days'
            WHEN days_outstanding <= 90 THEN '61-90 days'
            WHEN days_outstanding <= 180 THEN '91-180 days'
            ELSE '180+ days'
        END AS aging_bucket,
        CASE 
            WHEN days_outstanding <= 30 THEN 1
            WHEN days_outstanding <= 60 THEN 2
            WHEN days_outstanding <= 90 THEN 3
            WHEN days_outstanding <= 180 THEN 4
            ELSE 5
        END AS bucket_order,
        net_amount
    FROM outstanding_invoices
)

SELECT 
    (SELECT vendor_id FROM params) AS vendor_id,
    aging_bucket,
    bucket_order,
    COUNT(*) AS invoice_count,
    ROUND(SUM(net_amount)::numeric, 2) AS outstanding_amount
FROM aging_buckets
GROUP BY aging_bucket, bucket_order
ORDER BY bucket_order;


/*----------------------------------------------------------------
7.5 CHART: Top Outstanding Buyers
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
    COALESCE(org.org_name, 'Buyer ' || pd.buyer_org_id) AS buyer_name,
    COUNT(*) AS outstanding_invoices,
    ROUND(SUM(ti.net_amount)::numeric, 2) AS outstanding_amount,
    ROUND(AVG(EXTRACT(DAY FROM (CURRENT_DATE - ti.created_date::DATE)))::numeric, 0) AS avg_days_outstanding
FROM po_tax_invoice ti
JOIN po_details pd ON ti.po_id = pd.id
JOIN params p ON pd.seller_org_id = p.vendor_id
LEFT JOIN "userApis_organization" org ON pd.buyer_org_id = org.org_id
WHERE ti.status IN (1, 2)  -- Pending or Sent
  AND ti.created_date::DATE BETWEEN p.start_date AND p.end_date
GROUP BY pd.buyer_org_id, org.org_name
ORDER BY outstanding_amount DESC
LIMIT 10;
