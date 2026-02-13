/*================================================================
  PROCUREMENT PROCESS DASHBOARD - SQL Queries
  Dashboard: index (4).html
  Database: bluet_devpy_final_stg
  
  Sections:
    KPI 1-6  : Process Health Overview
    WORKFLOW  : Procurement Workflow Status (6 steps)
    OPS 1-5  : Operational Metrics
    RISK 1-5 : Process Risks & Exceptions
    CHART 1  : Spend by Category (Donut)
    CHART 2  : Approval Cycle Time (Line)
    CHART 3  : Savings by Initiative (Bar)
    ALERTS   : Alerts & Required Actions
================================================================*/


/*-----------------------------------------
 KPI 1. Total Requisitions
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT 
    COUNT(DISTINCT pd.id) AS total_requisitions,
    COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '30 days') THEN pd.id END) AS last_30_days,
    ROUND((
        (COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '30 days') THEN pd.id END) -
         COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '60 days') 
               AND pd.created_date < (p.end_date - INTERVAL '30 days') THEN pd.id END)
        ) * 100.0 / NULLIF(
         COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '60 days') 
               AND pd.created_date < (p.end_date - INTERVAL '30 days') THEN pd.id END), 0)
    )::NUMERIC, 1) AS growth_pct
FROM po_details pd
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
  AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%');


/*-----------------------------------------
 KPI 2. Approved POs
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT 
    COUNT(DISTINCT pd.id) AS approved_pos,
    ROUND((
        COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '30 days') THEN pd.id END) * 100.0 /
        NULLIF(COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '60 days') 
               AND pd.created_date < (p.end_date - INTERVAL '30 days') THEN pd.id END), 0) - 100
    )::NUMERIC, 1) AS growth_pct
FROM po_details pd
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pd.status IN (3, 4, 5, 6)
  AND pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
  AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%');


/*-----------------------------------------
 KPI 3. Avg Approval Time (Days)
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT 
    ROUND(AVG(
        EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400
    )::NUMERIC, 1) AS avg_approval_days,
    ROUND(AVG(
        CASE WHEN pd.created_date >= (p.end_date - INTERVAL '60 days') 
             AND pd.created_date < (p.end_date - INTERVAL '30 days')
        THEN EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400 END
    )::NUMERIC, 1) AS prev_period_days,
    ROUND(
        AVG(CASE WHEN pd.created_date >= (p.end_date - INTERVAL '30 days')
            THEN EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400 END)::NUMERIC -
        AVG(CASE WHEN pd.created_date >= (p.end_date - INTERVAL '60 days') 
             AND pd.created_date < (p.end_date - INTERVAL '30 days')
            THEN EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400 END)::NUMERIC
    , 1) AS change_days
FROM po_details pd
JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pd.status IN (3, 4, 5, 6)
  AND pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
  AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%');


/*-----------------------------------------
 KPI 4. On-Time PO Rate (%)
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT 
    ROUND((
        COUNT(CASE WHEN asn."Actual_delivery_date" <= asn.expected_delivery_date THEN 1 END) * 100.0 /
        NULLIF(COUNT(*), 0)
    )::NUMERIC, 1) AS on_time_rate,
    ROUND((
        (COUNT(CASE WHEN asn."Actual_delivery_date" <= asn.expected_delivery_date 
              AND pd.created_date >= (p.end_date - INTERVAL '30 days') THEN 1 END) * 100.0 /
         NULLIF(COUNT(CASE WHEN pd.created_date >= (p.end_date - INTERVAL '30 days') THEN 1 END), 0)
        ) -
        (COUNT(CASE WHEN asn."Actual_delivery_date" <= asn.expected_delivery_date 
              AND pd.created_date >= (p.end_date - INTERVAL '60 days')
              AND pd.created_date < (p.end_date - INTERVAL '30 days') THEN 1 END) * 100.0 /
         NULLIF(COUNT(CASE WHEN pd.created_date >= (p.end_date - INTERVAL '60 days')
              AND pd.created_date < (p.end_date - INTERVAL '30 days') THEN 1 END), 0)
        )
    )::NUMERIC, 1) AS change_pct
FROM po_asn asn
JOIN po_tax_invoice ti ON asn.tax_invoice_id = ti.id
JOIN po_details pd ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE asn."Actual_delivery_date" IS NOT NULL
  AND pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
  AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%');


/*-----------------------------------------
 KPI 5. Invoice Match Rate (%)
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT 
    ROUND((
        COUNT(CASE WHEN ti.id IS NOT NULL THEN 1 END) * 100.0 /
        NULLIF(COUNT(DISTINCT pd.id), 0)
    )::NUMERIC, 1) AS invoice_match_rate,
    COUNT(DISTINCT ti.id) AS matched_invoices,
    COUNT(DISTINCT pd.id) AS total_pos,
    ROUND((
        (COUNT(CASE WHEN ti.id IS NOT NULL AND pd.created_date >= (p.end_date - INTERVAL '30 days') THEN 1 END) * 100.0 /
         NULLIF(COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '30 days') THEN pd.id END), 0)
        ) -
        (COUNT(CASE WHEN ti.id IS NOT NULL AND pd.created_date >= (p.end_date - INTERVAL '60 days')
              AND pd.created_date < (p.end_date - INTERVAL '30 days') THEN 1 END) * 100.0 /
         NULLIF(COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '60 days')
              AND pd.created_date < (p.end_date - INTERVAL '30 days') THEN pd.id END), 0)
        )
    )::NUMERIC, 1) AS change_pct
FROM po_details pd
LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
  AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%');


/*-----------------------------------------
 KPI 6. Process Compliance (%)
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT 
    ROUND((
        COUNT(CASE WHEN pd.status IN (3, 4, 5, 6) AND ti.id IS NOT NULL THEN 1 END) * 100.0 /
        NULLIF(COUNT(DISTINCT pd.id), 0)
    )::NUMERIC, 1) AS process_compliance_pct,
    ROUND((
        (COUNT(CASE WHEN pd.status IN (3, 4, 5, 6) AND ti.id IS NOT NULL 
              AND pd.created_date >= (p.end_date - INTERVAL '30 days') THEN 1 END) * 100.0 /
         NULLIF(COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '30 days') THEN pd.id END), 0)
        ) -
        (COUNT(CASE WHEN pd.status IN (3, 4, 5, 6) AND ti.id IS NOT NULL 
              AND pd.created_date >= (p.end_date - INTERVAL '60 days')
              AND pd.created_date < (p.end_date - INTERVAL '30 days') THEN 1 END) * 100.0 /
         NULLIF(COUNT(DISTINCT CASE WHEN pd.created_date >= (p.end_date - INTERVAL '60 days')
              AND pd.created_date < (p.end_date - INTERVAL '30 days') THEN pd.id END), 0)
        )
    )::NUMERIC, 1) AS change_pct
FROM po_details pd
LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
  AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%');


/*-----------------------------------------
 WORKFLOW: Procurement Workflow Status (6 Steps)
 Steps: Requisition → Approval → PO Created → GRN → Invoice → Payment
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),
workflow_data AS (
    SELECT 
        pd.id AS po_id,
        pd.status,
        pd.created_date,
        ti.id AS invoice_id,
        ti.created_date AS invoice_date,
        asn.id AS asn_id,
        asn."Actual_delivery_date",
        asn.expected_delivery_date,
        -- Step flags
        1 AS has_requisition,
        CASE WHEN pd.status >= 2 THEN 1 ELSE 0 END AS has_approval,
        CASE WHEN pd.status >= 3 THEN 1 ELSE 0 END AS has_po,
        CASE WHEN asn.id IS NOT NULL THEN 1 ELSE 0 END AS has_grn,
        CASE WHEN ti.id IS NOT NULL THEN 1 ELSE 0 END AS has_invoice,
        CASE WHEN pd.status IN (5, 6) THEN 1 ELSE 0 END AS has_payment
    FROM po_details pd
    LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN po_asn asn ON asn.tax_invoice_id = ti.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
      AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%')
)
SELECT 
    'Requisition' AS step_name, 1 AS step_order,
    SUM(has_requisition) AS total_done,
    SUM(CASE WHEN has_approval = 0 THEN 1 ELSE 0 END) AS pending,
    COUNT(CASE WHEN has_approval = 0 AND created_date < CURRENT_DATE - INTERVAL '5 days' THEN 1 END) AS delayed
FROM workflow_data
UNION ALL
SELECT 
    'Approval', 2,
    SUM(has_approval),
    SUM(CASE WHEN has_approval = 1 AND has_po = 0 THEN 1 ELSE 0 END),
    COUNT(CASE WHEN has_approval = 1 AND has_po = 0 AND created_date < CURRENT_DATE - INTERVAL '5 days' THEN 1 END)
FROM workflow_data
UNION ALL
SELECT 
    'PO Created', 3,
    SUM(has_po),
    SUM(CASE WHEN has_po = 1 AND has_grn = 0 THEN 1 ELSE 0 END),
    COUNT(CASE WHEN has_po = 1 AND has_grn = 0 AND created_date < CURRENT_DATE - INTERVAL '7 days' THEN 1 END)
FROM workflow_data
UNION ALL
SELECT 
    'GRN', 4,
    SUM(has_grn),
    SUM(CASE WHEN has_grn = 1 AND has_invoice = 0 THEN 1 ELSE 0 END),
    COUNT(CASE WHEN has_grn = 1 AND has_invoice = 0 AND created_date < CURRENT_DATE - INTERVAL '7 days' THEN 1 END)
FROM workflow_data
UNION ALL
SELECT 
    'Invoice', 5,
    SUM(has_invoice),
    SUM(CASE WHEN has_invoice = 1 AND has_payment = 0 THEN 1 ELSE 0 END),
    COUNT(CASE WHEN has_invoice = 1 AND has_payment = 0 AND created_date < CURRENT_DATE - INTERVAL '10 days' THEN 1 END)
FROM workflow_data
UNION ALL
SELECT 
    'Payment', 6,
    SUM(has_payment),
    SUM(CASE WHEN has_invoice = 1 AND has_payment = 0 THEN 1 ELSE 0 END),
    0
FROM workflow_data
ORDER BY step_order;


/*-----------------------------------------
 OPS: Operational Metrics (5 metrics)
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT 
    -- POs Created (this week)
    COUNT(DISTINCT CASE WHEN pd.created_date >= CURRENT_DATE - INTERVAL '7 days' 
          AND pd.status >= 3 THEN pd.id END) AS pos_created_this_week,
    -- Pending Approval
    COUNT(DISTINCT CASE WHEN pd.status IN (1, 2) THEN pd.id END) AS pending_approval,
    -- Invoices Received
    COUNT(DISTINCT ti.id) AS invoices_received,
    -- Pending Match (invoices without completed payment)
    COUNT(DISTINCT CASE WHEN ti.id IS NOT NULL AND pd.status NOT IN (5, 6) THEN ti.id END) AS pending_match,
    -- Blocked/Disputed Invoices
    COUNT(DISTINCT CASE WHEN pi.total_amount != (pi.qty * pi.unit_price) 
          AND ti.id IS NOT NULL THEN ti.id END) AS blocked_invoices
FROM po_details pd
LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN po_items pi ON pi.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
  AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%');


/*-----------------------------------------
 RISK: Process Risks & Exceptions (5 risk metrics)
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),
risk_data AS (
    SELECT 
        pd.id AS po_id,
        pd.status,
        pd.created_date,
        ti.id AS invoice_id,
        pi.total_amount,
        pi.qty * pi.unit_price AS quoted_amount,
        EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400 AS approval_days
    FROM po_details pd
    LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
      AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%')
)
SELECT 
    -- Maverick Spend %: orders with significant price deviation from quoted
    ROUND((
        COUNT(CASE WHEN ABS(total_amount - quoted_amount) > (quoted_amount * 0.1) THEN 1 END) * 100.0 /
        NULLIF(COUNT(*), 0)
    )::NUMERIC, 1) AS maverick_spend_pct,
    -- PO Bypasses: invoices without proper PO (status < 3 but has invoice)
    COUNT(DISTINCT CASE WHEN status < 3 AND invoice_id IS NOT NULL THEN po_id END) AS po_bypasses, 
    -- Invoices without PO
    COUNT(DISTINCT CASE WHEN invoice_id IS NOT NULL AND status < 3 THEN invoice_id END) AS invoices_without_po, 
    -- Delayed Approvals %: POs taking > 5 days
    ROUND((
        COUNT(CASE WHEN approval_days > 5 THEN 1 END) * 100.0 /
        NULLIF(COUNT(CASE WHEN approval_days IS NOT NULL THEN 1 END), 0)
    )::NUMERIC, 1) AS delayed_approvals_pct, 
    -- Policy Exceptions: POs with abnormal amounts (> 3x avg)
    COUNT(CASE WHEN total_amount > (SELECT AVG(total_amount) * 3 FROM risk_data) THEN 1 END) AS policy_exceptions
FROM risk_data;


/*-----------------------------------------
 CHART 1. Spend by Category (Donut Chart)
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT 
    COALESCE(
        CASE 
            WHEN pi."productName" ILIKE '%IT%' OR pi."productName" ILIKE '%computer%' 
                 OR pi."productName" ILIKE '%tech%' OR pi."productName" ILIKE '%software%' 
            THEN 'IT Equipment'
            WHEN pi."productName" ILIKE '%office%' OR pi."productName" ILIKE '%stationery%' 
                 OR pi."productName" ILIKE '%paper%' 
            THEN 'Office Supplies'
            WHEN pi."productName" ILIKE '%service%' OR pi."productName" ILIKE '%consult%' 
            THEN 'Services'
            WHEN pi."productName" ILIKE '%logistic%' OR pi."productName" ILIKE '%shipping%' 
                 OR pi."productName" ILIKE '%transport%' 
            THEN 'Logistics'
            ELSE 'Other'
        END,
        'Uncategorized'
    ) AS category,
    ROUND(SUM(pi.total_amount)::NUMERIC, 2) AS total_spend,
    ROUND((SUM(pi.total_amount) * 100.0 / NULLIF(SUM(SUM(pi.total_amount)) OVER(), 0))::NUMERIC, 1) AS spend_pct,
    COUNT(DISTINCT pd.id) AS po_count
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
  AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%')
GROUP BY 1
ORDER BY total_spend DESC;


/*-----------------------------------------
 CHART 2. Approval Cycle Time (Line Chart - Weekly)
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT 
    TO_CHAR(DATE_TRUNC('week', pd.created_date), 'YYYY-"W"IW') AS week_label,
    DATE_TRUNC('week', pd.created_date) AS week_start,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400
    )::NUMERIC, 1) AS avg_cycle_days,
    COUNT(DISTINCT pd.id) AS po_count,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400
    )::NUMERIC, 1) AS median_cycle_days
FROM po_details pd
JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pd.status IN (3, 4, 5, 6)
  AND pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
  AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%')
GROUP BY DATE_TRUNC('week', pd.created_date)
ORDER BY week_start;


/*-----------------------------------------
 CHART 3. Savings by Initiative (Horizontal Bar Chart)
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS supplier_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),
savings_data AS (
    SELECT 
        pi.total_amount,
        pi.qty * pi.unit_price AS base_amount,
        COALESCE(pi.discount, 0) AS discount_amount,
        COALESCE(pi.logistics, 0) + COALESCE(pi.shipping, 0) AS logistics_cost,
        COALESCE(pi.gst, 0) AS tax_amount,
        COALESCE(pi.insurance, 0) AS insurance_amount
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
      AND (p.supplier_filter IS NULL OR org.company_name ILIKE '%' || p.supplier_filter || '%')
)
SELECT 
    initiative,
    ROUND(savings::NUMERIC, 2) AS savings_amount
FROM (
    VALUES
        ('Sourcing', (SELECT SUM(base_amount - total_amount) FROM savings_data WHERE base_amount > total_amount)),
        ('Compliance', (SELECT SUM(discount_amount) FROM savings_data)),
        ('Discounts', (SELECT SUM(discount_amount) FROM savings_data WHERE discount_amount > 0)),
        ('Process', (SELECT SUM(GREATEST(base_amount - total_amount, 0)) * 0.15 FROM savings_data))
) AS s(initiative, savings)
WHERE savings > 0
ORDER BY savings DESC;


/*-----------------------------------------
 ALERTS: Alerts & Required Actions
-----------------------------------------*/
WITH params AS (
    SELECT 
        91::INTEGER AS vendor_id,
        NULL::TEXT AS business_unit,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
-- Approval SLA Breaches (> 5 days pending)
SELECT 
    'critical' AS alert_type,
    'Approval SLA Breach' AS alert_title,
    'PO #' || pd.id || ' pending approval for > 5 days' AS alert_description,
    pd.created_date AS alert_time,
    pd.id AS reference_id
FROM po_details pd
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
CROSS JOIN params p
WHERE pd.status IN (1, 2)
  AND EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pd.created_date)) / 86400 > 5
  AND pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
UNION ALL
-- Budget Overrun Risk
SELECT 
    'warning' AS alert_type,
    'Budget Overrun Risk' AS alert_title,
    'Spend projected to exceed budget by ' || 
    ROUND(((SUM(pi.total_amount) - SUM(pi.qty * pi.unit_price)) * 100.0 / 
          NULLIF(SUM(pi.qty * pi.unit_price), 0))::NUMERIC, 1) || '%' AS alert_description,
    MAX(pd.created_date) AS alert_time,
    0 AS reference_id
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
HAVING SUM(pi.total_amount) > SUM(pi.qty * pi.unit_price)
UNION ALL
-- Supplier Non-Compliance (low rated suppliers with active orders)
SELECT 
    'critical' AS alert_type,
    'Supplier Non-Compliance' AS alert_title,
    org.company_name || ' has rating below 3.0 with active orders' AS alert_description,
    MAX(pd.created_date) AS alert_time,
    org.org_id AS reference_id
FROM "userApis_organization" org
JOIN po_details pd ON pd.seller_org_id = org.org_id
CROSS JOIN params p
WHERE org.supplier_avg_rating IS NOT NULL
  AND org.supplier_avg_rating < 3.0
  AND pd.status NOT IN (5, 6)
  AND pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR org.org_id = p.vendor_id)
GROUP BY org.org_id, org.company_name

ORDER BY alert_time DESC
LIMIT 10;
