/*================================================================
  AUDIT & GOVERNANCE DASHBOARD - SQL Queries
  Dashboard: index (2).html
  Database: bluet_devpy_final_stg
  
  Sections:
    KPI 1-6       : Overview KPIs (Total Audits, Open Findings,
                     High-Risk Issues, Compliance Score,
                     Policy Adherence, Avg Closure Time)
    COMPLIANCE 1-5: Compliance & Control Metrics
    RISK CHART    : Risk Exposure Summary (Bar chart + list)
    FINDINGS TABLE: Audit Findings & Observations
    ACTION TRACKER: Corrective Actions & Closure
    ALERTS        : Governance Alerts

  Key Tables Used:
    po_details, po_items, po_tax_invoice, po_asn,
    bt_po_activity_logs, bt_po_approve_users,
    bt_rfq_activity_logs, approver_flow,
    "userApis_organization", contracts,
    po_updates, po_update_documents

  Filters:
    Audit Period     → start_date / end_date
    Business Unit    → business_unit  (org.state)
    Category         → category_filter (pi."productName")
    Process Type     → process_type_filter (NULL=All, 'PO', 'RFQ', 'PRF')
    Risk Level       → risk_level_filter (NULL=All, 'High', 'Medium', 'Low')

  Notes:
    - "Audit" is derived from PO activity logs & approval flows
      as the Vipani platform doesn't have a dedicated audit table.
    - Each PO lifecycle (creation → approval → invoice → delivery)
      is treated as an auditable process.
    - Findings = POs or processes with deviations (price variance,
      late delivery, missing approvals, etc.)
================================================================*/


/*-----------------------------------------
 KPI 1. Total Audits
 Counts distinct PO processes that have
 activity log entries (i.e. audited POs)
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT
    COUNT(DISTINCT pal.po_id) AS total_audits,
    COUNT(DISTINCT CASE
        WHEN pal.updated_date >= (p.end_date - INTERVAL '30 days')
        THEN pal.po_id END) AS audits_last_30d,
    ROUND((
        (COUNT(DISTINCT CASE
            WHEN pal.updated_date >= (p.end_date - INTERVAL '30 days')
            THEN pal.po_id END) -
         COUNT(DISTINCT CASE
            WHEN pal.updated_date >= (p.end_date - INTERVAL '60 days')
             AND pal.updated_date <  (p.end_date - INTERVAL '30 days')
            THEN pal.po_id END)
        ) * 100.0 /
        NULLIF(COUNT(DISTINCT CASE
            WHEN pal.updated_date >= (p.end_date - INTERVAL '60 days')
             AND pal.updated_date <  (p.end_date - INTERVAL '30 days')
            THEN pal.po_id END), 0)
    )::NUMERIC, 1) AS growth_pct
FROM bt_po_activity_logs pal
JOIN po_details pd ON pal.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pal.updated_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%');


/*-----------------------------------------
 KPI 2. Open Findings
 POs with issues: price discrepancies,
 missing invoices on approved POs,
 or overdue deliveries
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),
findings AS (
    SELECT DISTINCT pd.id AS po_id, pd.created_date
    FROM po_details pd
    LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN po_asn asn ON asn.tax_invoice_id = ti.id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
      AND pd.status NOT IN (5, 6)  -- not completed
      AND (
          -- Missing invoice on approved PO
          (pd.status IN (3, 4) AND ti.id IS NULL)
          -- Overdue delivery
          OR (asn.expected_delivery_date < CURRENT_DATE AND asn."Actual_delivery_date" IS NULL)
          -- Price discrepancy > 10%
          OR (pi.total_amount > pi.qty * pi.unit_price * 1.10)
      )
)
SELECT
    COUNT(*) AS open_findings,
    COUNT(CASE WHEN created_date >= ((SELECT end_date FROM params) - INTERVAL '30 days') THEN 1 END) AS last_30d,
    ROUND((
        (COUNT(CASE WHEN created_date >= ((SELECT end_date FROM params) - INTERVAL '30 days') THEN 1 END) -
         COUNT(CASE WHEN created_date >= ((SELECT end_date FROM params) - INTERVAL '60 days')
                    AND created_date <  ((SELECT end_date FROM params) - INTERVAL '30 days') THEN 1 END)
        ) * 100.0 /
        NULLIF(COUNT(CASE WHEN created_date >= ((SELECT end_date FROM params) - INTERVAL '60 days')
                         AND created_date <  ((SELECT end_date FROM params) - INTERVAL '30 days') THEN 1 END), 0)
    )::NUMERIC, 1) AS change_pct
FROM findings;


/*-----------------------------------------
 KPI 3. High-Risk Issues
 POs with severe deviations:
  - Price variance > 20%
  - Delivery overdue > 14 days
  - PO amount > threshold without approval
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),
high_risk AS (
    SELECT DISTINCT pd.id AS po_id, pd.created_date
    FROM po_details pd
    LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN po_asn asn ON asn.tax_invoice_id = ti.id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    LEFT JOIN bt_po_approve_users pau ON pau.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
      AND pd.status NOT IN (5, 6)
      AND (
          -- Price variance > 20%
          (pi.total_amount > pi.qty * pi.unit_price * 1.20)
          -- Delivery overdue > 14 days
          OR (asn.expected_delivery_date < CURRENT_DATE - INTERVAL '14 days'
              AND asn."Actual_delivery_date" IS NULL)
          -- Large PO without approval record
          OR (pd.total_amount > 50000 AND pau.id IS NULL)
      )
)
SELECT
    COUNT(*) AS high_risk_issues,
    COUNT(CASE WHEN created_date >= ((SELECT end_date FROM params) - INTERVAL '30 days') THEN 1 END) AS last_30d,
    COUNT(CASE WHEN created_date >= ((SELECT end_date FROM params) - INTERVAL '30 days') THEN 1 END) -
    COUNT(CASE WHEN created_date >= ((SELECT end_date FROM params) - INTERVAL '60 days')
               AND created_date <  ((SELECT end_date FROM params) - INTERVAL '30 days') THEN 1 END)
        AS change_vs_prev
FROM high_risk;


/*-----------------------------------------
 KPI 4. Compliance Score (%)
 Ratio of POs that followed proper process:
  approved (status 3-6) AND has invoice
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT
    ROUND((
        COUNT(DISTINCT CASE
            WHEN pd.status IN (3, 4, 5, 6) AND ti.id IS NOT NULL
            THEN pd.id END) * 100.0 /
        NULLIF(COUNT(DISTINCT pd.id), 0)
    )::NUMERIC, 1) AS compliance_score_pct,
    ROUND((
        (COUNT(DISTINCT CASE
            WHEN pd.status IN (3, 4, 5, 6) AND ti.id IS NOT NULL
             AND pd.created_date >= (p.end_date - INTERVAL '30 days')
            THEN pd.id END) * 100.0 /
         NULLIF(COUNT(DISTINCT CASE
            WHEN pd.created_date >= (p.end_date - INTERVAL '30 days')
            THEN pd.id END), 0)
        ) -
        (COUNT(DISTINCT CASE
            WHEN pd.status IN (3, 4, 5, 6) AND ti.id IS NOT NULL
             AND pd.created_date >= (p.end_date - INTERVAL '60 days')
             AND pd.created_date <  (p.end_date - INTERVAL '30 days')
            THEN pd.id END) * 100.0 /
         NULLIF(COUNT(DISTINCT CASE
            WHEN pd.created_date >= (p.end_date - INTERVAL '60 days')
             AND pd.created_date <  (p.end_date - INTERVAL '30 days')
            THEN pd.id END), 0)
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
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%');


/*-----------------------------------------
 KPI 5. Policy Adherence (%)
 POs that went through approval flow
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT
    ROUND((
        COUNT(DISTINCT CASE WHEN pau.id IS NOT NULL THEN pd.id END) * 100.0 /
        NULLIF(COUNT(DISTINCT pd.id), 0)
    )::NUMERIC, 1) AS policy_adherence_pct
FROM po_details pd
LEFT JOIN bt_po_approve_users pau ON pau.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%');


/*-----------------------------------------
 KPI 6. Avg Closure Time (Days)
 Average days from PO creation to
 completion (status 5 or 6)
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT
    ROUND(AVG(
        EXTRACT(EPOCH FROM (pd.updated_date - pd.created_date)) / 86400
    )::NUMERIC, 1) AS avg_closure_days,
    ROUND(
        AVG(CASE WHEN pd.created_date >= (p.end_date - INTERVAL '30 days')
            THEN EXTRACT(EPOCH FROM (pd.updated_date - pd.created_date)) / 86400 END)::NUMERIC -
        AVG(CASE WHEN pd.created_date >= (p.end_date - INTERVAL '60 days')
             AND pd.created_date <  (p.end_date - INTERVAL '30 days')
            THEN EXTRACT(EPOCH FROM (pd.updated_date - pd.created_date)) / 86400 END)::NUMERIC
    , 1) AS change_days
FROM po_details pd
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_items pi ON pi.po_id = pd.id
CROSS JOIN params p
WHERE pd.status IN (5, 6)
  AND pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%');


/*-----------------------------------------
 COMPLIANCE 1-5: Compliance & Control Metrics
 1) Policy Exceptions
 2) Control Failures
 3) SOP Deviations
 4) Unauthorized Txns
 5) Non-Compliant Spend
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
SELECT
    -- 1) Policy Exceptions: POs bypassing approval
    COUNT(DISTINCT CASE
        WHEN pd.status IN (3, 4, 5, 6) AND pau.id IS NULL
        THEN pd.id END) AS policy_exceptions,
    -- 2) Control Failures: POs with status changes skipping steps
    COUNT(DISTINCT CASE
        WHEN pal.old_status IS NOT NULL
         AND pal.new_status IS NOT NULL
         AND (pal.new_status - pal.old_status) > 1
        THEN pd.id END) AS control_failures,
    -- 3) SOP Deviations: POs with price variance > 10%
    COUNT(DISTINCT CASE
        WHEN pi.total_amount > pi.qty * pi.unit_price * 1.10
        THEN pd.id END) AS sop_deviations,
    -- 4) Unauthorized Txns: POs created but rejected (status suggests unauthorized)
    COUNT(DISTINCT CASE
        WHEN pd.status = 1 AND pd.reject_reason IS NOT NULL
        THEN pd.id END) AS unauthorized_txns,
    -- 5) Non-Compliant Spend: spend on POs without proper approvals
    ROUND((
        COALESCE(SUM(CASE
            WHEN pd.status IN (3, 4, 5, 6) AND pau.id IS NULL
            THEN pi.total_amount END), 0) * 100.0 /
        NULLIF(SUM(pi.total_amount), 0)
    )::NUMERIC, 1) AS non_compliant_spend_pct,
    ROUND(COALESCE(SUM(CASE
        WHEN pd.status IN (3, 4, 5, 6) AND pau.id IS NULL
        THEN pi.total_amount END), 0)::NUMERIC, 2) AS non_compliant_spend_amount
FROM po_details pd
LEFT JOIN po_items pi ON pi.po_id = pd.id
LEFT JOIN bt_po_approve_users pau ON pau.po_id = pd.id
LEFT JOIN bt_po_activity_logs pal ON pal.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.business_unit IS NULL OR org.state = p.business_unit)
  AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%');


/*-----------------------------------------
 RISK CHART: Risk Exposure Summary
 5 risk categories scored 0-100:
  Financial, Operational, Supplier,
  Regulatory, Process
 Returns score + High/Medium/Low label
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),
base AS (
    SELECT
        pd.id AS po_id,
        pd.status,
        pd.total_amount,
        pd.created_date,
        pd.updated_date,
        pi.total_amount AS item_total,
        pi.qty,
        pi.unit_price,
        ti.id AS invoice_id,
        asn.expected_delivery_date,
        asn."Actual_delivery_date",
        pau.id AS approval_id,
        org.supplier_avg_rating
    FROM po_details pd
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN po_asn asn ON asn.tax_invoice_id = ti.id
    LEFT JOIN bt_po_approve_users pau ON pau.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
)
SELECT
    risk_category,
    risk_score,
    CASE
        WHEN risk_score >= 70 THEN 'High'
        WHEN risk_score >= 40 THEN 'Medium'
        ELSE 'Low'
    END AS risk_level
FROM (
    -- Financial Risk: price variance ratio
    SELECT
        'Financial' AS risk_category,
        LEAST(100, ROUND((
            COUNT(CASE WHEN item_total > qty * unit_price * 1.10 THEN 1 END) * 100.0 /
            NULLIF(COUNT(*), 0)
        )::NUMERIC * 2, 0)) AS risk_score
    FROM base

    UNION ALL
    -- Operational Risk: late deliveries ratio
    SELECT
        'Operational',
        LEAST(100, ROUND((
            COUNT(CASE WHEN "Actual_delivery_date" > expected_delivery_date THEN 1 END) * 100.0 /
            NULLIF(COUNT(CASE WHEN expected_delivery_date IS NOT NULL THEN 1 END), 0)
        )::NUMERIC, 0))
    FROM base

    UNION ALL
    -- Supplier Risk: low-rated suppliers
    SELECT
        'Supplier',
        LEAST(100, ROUND((
            COUNT(CASE WHEN supplier_avg_rating IS NOT NULL AND supplier_avg_rating < 3.0 THEN 1 END) * 100.0 /
            NULLIF(COUNT(CASE WHEN supplier_avg_rating IS NOT NULL THEN 1 END), 0)
        )::NUMERIC * 2, 0))
    FROM base

    UNION ALL
    -- Regulatory Risk: missing documentation (invoices)
    SELECT
        'Regulatory',
        LEAST(100, ROUND((
            COUNT(CASE WHEN status IN (3, 4, 5, 6) AND invoice_id IS NULL THEN 1 END) * 100.0 /
            NULLIF(COUNT(CASE WHEN status IN (3, 4, 5, 6) THEN 1 END), 0)
        )::NUMERIC, 0))
    FROM base

    UNION ALL
    -- Process Risk: POs without approval flow
    SELECT
        'Process',
        LEAST(100, ROUND((
            COUNT(CASE WHEN approval_id IS NULL THEN 1 END) * 100.0 /
            NULLIF(COUNT(*), 0)
        )::NUMERIC * 1.5, 0))
    FROM base
) risk_data
ORDER BY
    CASE risk_category
        WHEN 'Financial'  THEN 1
        WHEN 'Operational' THEN 2
        WHEN 'Supplier'   THEN 3
        WHEN 'Regulatory' THEN 4
        WHEN 'Process'    THEN 5
    END;


/*-----------------------------------------
 FINDINGS TABLE: Audit Findings & Observations
 Returns top findings with area, description,
 risk level, owner, status, target date
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),
finding_details AS (
    -- Price discrepancy findings
    SELECT DISTINCT ON (pd.id)
        pd.id AS po_id,
        'Finance' AS audit_area,
        'PO #' || pd.po_number || ' - Price variance of ' ||
            ROUND(((pi.total_amount - pi.qty * pi.unit_price) * 100.0 /
                NULLIF(pi.qty * pi.unit_price, 0))::NUMERIC, 1) || '%' AS finding_description,
        CASE
            WHEN pi.total_amount > pi.qty * pi.unit_price * 1.20 THEN 'High'
            WHEN pi.total_amount > pi.qty * pi.unit_price * 1.10 THEN 'Medium'
            ELSE 'Low'
        END AS risk_level,
        org.company_name AS owner,
        CASE
            WHEN pd.status IN (5, 6) THEN 'Closed'
            WHEN pd.status IN (3, 4) THEN 'In Progress'
            ELSE 'Open'
        END AS finding_status,
        (pd.created_date + INTERVAL '30 days')::DATE AS target_date,
        pd.created_date
    FROM po_details pd
    JOIN po_items pi ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND pi.total_amount > pi.qty * pi.unit_price * 1.10
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
    UNION ALL
    -- Overdue delivery findings
    SELECT DISTINCT ON (pd.id)
        pd.id,
        'Logistics',
        'PO #' || pd.po_number || ' - Delivery overdue by ' ||
            (CURRENT_DATE - asn.expected_delivery_date) || ' days',
        CASE
            WHEN (CURRENT_DATE - asn.expected_delivery_date) > 14 THEN 'High'
            WHEN (CURRENT_DATE - asn.expected_delivery_date) > 7  THEN 'Medium'
            ELSE 'Low'
        END,
        org.company_name,
        'Open',
        asn.expected_delivery_date,
        pd.created_date
    FROM po_details pd
    JOIN po_tax_invoice ti ON ti.po_id = pd.id
    JOIN po_asn asn ON asn.tax_invoice_id = ti.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND asn.expected_delivery_date < CURRENT_DATE
      AND asn."Actual_delivery_date" IS NULL
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
    UNION ALL
    -- Missing approval findings
    SELECT DISTINCT ON (pd.id)
        pd.id,
        'Procurement',
        'PO #' || pd.po_number || ' - Approved without recorded approval flow',
        CASE
            WHEN pd.total_amount > 50000 THEN 'High'
            ELSE 'Medium'
        END,
        org.company_name,
        CASE
            WHEN pd.status IN (5, 6) THEN 'Closed'
            ELSE 'Open'
        END,
        (pd.created_date + INTERVAL '15 days')::DATE,
        pd.created_date
    FROM po_details pd
    LEFT JOIN bt_po_approve_users pau ON pau.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND pd.status IN (3, 4, 5, 6)
      AND pau.id IS NULL
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
)
SELECT
    audit_area,
    finding_description,
    risk_level,
    COALESCE(owner, 'Unassigned') AS owner,
    finding_status,
    target_date
FROM finding_details
WHERE (
    (SELECT risk_level_filter FROM params) IS NULL
    OR risk_level = (SELECT risk_level_filter FROM params)
)
ORDER BY
    CASE risk_level WHEN 'High' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END,
    created_date DESC
LIMIT 20;


/*-----------------------------------------
 ACTION TRACKER: Corrective Actions & Closure
 Open Actions, Closed Actions,
 Completion Rate, On-Time Closure,
 Overdue, SLA Breaches, Avg Resolution
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
),
action_data AS (
    SELECT
        pd.id AS po_id,
        pd.status,
        pd.created_date,
        pd.updated_date,
        -- SLA: 30 days from creation to completion
        CASE
            WHEN pd.status IN (5, 6)
            THEN EXTRACT(EPOCH FROM (pd.updated_date - pd.created_date)) / 86400
            ELSE NULL
        END AS resolution_days,
        CASE
            WHEN pd.status IN (5, 6)
             AND EXTRACT(EPOCH FROM (pd.updated_date - pd.created_date)) / 86400 <= 30
            THEN 1 ELSE 0
        END AS on_time_flag,
        CASE
            WHEN pd.status NOT IN (5, 6)
             AND pd.created_date < CURRENT_DATE - INTERVAL '30 days'
            THEN 1 ELSE 0
        END AS overdue_flag,
        CASE
            WHEN pd.status NOT IN (5, 6)
             AND pd.created_date < CURRENT_DATE - INTERVAL '45 days'
            THEN 1 ELSE 0
        END AS sla_breach_flag
    FROM po_details pd
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
)
SELECT
    -- Open vs Closed
    COUNT(DISTINCT CASE WHEN status NOT IN (5, 6) THEN po_id END) AS open_actions,
    COUNT(DISTINCT CASE WHEN status IN (5, 6)     THEN po_id END) AS closed_actions,
    -- Completion Rate
    ROUND((
        COUNT(DISTINCT CASE WHEN status IN (5, 6) THEN po_id END) * 100.0 /
        NULLIF(COUNT(DISTINCT po_id), 0)
    )::NUMERIC, 1) AS completion_rate_pct,
    -- On-Time Closure
    ROUND((
        SUM(on_time_flag) * 100.0 /
        NULLIF(COUNT(CASE WHEN status IN (5, 6) THEN 1 END), 0)
    )::NUMERIC, 1) AS on_time_closure_pct,
    -- Overdue count
    SUM(overdue_flag) AS overdue_count,
    -- SLA Breaches
    SUM(sla_breach_flag) AS sla_breaches,
    -- Avg Resolution Time
    ROUND(AVG(resolution_days)::NUMERIC, 1) AS avg_resolution_days
FROM action_data;


/*-----------------------------------------
 ALERTS: Governance Alerts
 Critical findings, overdue actions,
 policy violations, regulatory updates
-----------------------------------------*/
WITH params AS (
    SELECT
        91::INTEGER  AS vendor_id,
        NULL::TEXT    AS business_unit,
        NULL::TEXT    AS category_filter,
        NULL::TEXT    AS process_type_filter,
        NULL::TEXT    AS risk_level_filter,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date
)
-- Wrap UNION ALL in subquery so ORDER BY can use expressions
SELECT * FROM (
    -- Alert 1: High-risk findings detected
    SELECT
        'critical' AS alert_severity,
        'High-Risk Finding Detected' AS alert_title,
        'PO #' || pd.po_number || ' has price variance > 20% — amount ₹' ||
            ROUND(pi.total_amount::NUMERIC, 2) || ' vs expected ₹' ||
            ROUND((pi.qty * pi.unit_price)::NUMERIC, 2) AS alert_description,
        pd.created_date AS alert_time
    FROM po_details pd
    JOIN po_items pi ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND pi.total_amount > pi.qty * pi.unit_price * 1.20
      AND pd.status NOT IN (5, 6)
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')

    UNION ALL
    -- Alert 2: Overdue action items
    SELECT
        'warning',
        'Action Item Overdue',
        'PO #' || pd.po_number || ' from ' || COALESCE(org.company_name, 'Unknown') ||
            ' is ' || (CURRENT_DATE - pd.created_date::DATE) || ' days old without closure',
        pd.created_date
    FROM po_details pd
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND pd.status NOT IN (5, 6)
      AND pd.created_date < CURRENT_DATE - INTERVAL '30 days'
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')

    UNION ALL
    -- Alert 3: Policy violations (POs without approval)
    SELECT
        'warning',
        'Policy Violation — Missing Approval',
        'PO #' || pd.po_number || ' (₹' || ROUND(pd.total_amount::NUMERIC, 0) ||
            ') processed without recorded approval flow',
        pd.created_date
    FROM po_details pd
    LEFT JOIN bt_po_approve_users pau ON pau.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND pd.status IN (3, 4, 5, 6)
      AND pau.id IS NULL
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')

    UNION ALL
    -- Alert 4: Supplier risk (low-rated supplier with active POs)
    SELECT
        'info',
        'Supplier Risk Alert',
        org.company_name || ' has supplier rating ' ||
            ROUND(org.supplier_avg_rating::NUMERIC, 1) ||
            '/5 with ' || COUNT(DISTINCT pd.id) || ' active POs',
        MAX(pd.created_date)
    FROM po_details pd
    JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN po_items pi ON pi.po_id = pd.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND pd.status NOT IN (5, 6)
      AND org.supplier_avg_rating IS NOT NULL
      AND org.supplier_avg_rating < 3.0
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.business_unit IS NULL OR org.state = p.business_unit)
      AND (p.category_filter IS NULL OR pi."productName" ILIKE '%' || p.category_filter || '%')
    GROUP BY org.company_name, org.supplier_avg_rating
) alerts
ORDER BY
    CASE alert_severity WHEN 'critical' THEN 1 WHEN 'warning' THEN 2 ELSE 3 END,
    alert_time DESC
LIMIT 10;


/*-----------------------------------------
 FILTER DROPDOWNS
-----------------------------------------*/

-- Filter: Business Unit / Region dropdown
SELECT DISTINCT org.state AS business_unit
FROM "userApis_organization" org
WHERE org.state IS NOT NULL
ORDER BY org.state;

-- Filter: Category dropdown
SELECT DISTINCT pi."productName" AS category
FROM po_items pi
WHERE pi."productName" IS NOT NULL
ORDER BY pi."productName"
LIMIT 50;

-- Filter: Risk Level dropdown (static)
SELECT unnest(ARRAY['All Levels', 'High', 'Medium', 'Low']) AS risk_level;
