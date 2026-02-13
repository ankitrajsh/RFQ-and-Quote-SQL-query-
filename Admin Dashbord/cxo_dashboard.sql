/*
=============================================================================
  CXO DASHBOARD - SQL QUERIES
  Dashboard: index (1).html — Vipani CXO Dashboard
  Description: Enterprise-wide visibility into spend, risk, performance, and growth
=============================================================================

  FILTERS (from HTML dashboard):
    - Period       : This Quarter (Q1 2026) / Last Quarter (Q4 2025) / YTD 2026 / Last 12 Months
    - Region       : Global / specific region
    - Category     : All Categories / specific category
    - Spend Type   : Direct & Indirect / Direct / Indirect
    - Supplier Tier: Strategic Only / All Tiers

  KPIs (6 cards):
    1. Total Spend           — $142.5M  (+12% vs last period)
    2. Cost Savings           — $18.2M   (+8.5% vs last period)
    3. EBITDA Impact          — $4.3M    (+2.1% vs last period)
    4. Procurement ROI        — 6.4x     (+0.3x vs last period)
    5. Risk Exposure          — Medium   (+2 vs last period)
    6. Compliance Score       — 94.2%    (-1.2% vs last period)

  CHARTS (4 charts):
    1. Spend by Category      — Pie Chart  (IT Services, Logistics, Marketing, Facilities, Professional Svc)
    2. Spend by Region ($M)   — Bar Chart  (NA, EU, APAC, LATAM, EMEA)
    3. Managed vs Unmanaged   — Donut Chart (82% Managed, 18% Unmanaged)
    4. Budget vs Actual        — Bar Chart  (Q1, Q2, Q3, Q4)

  SAVINGS SECTION:
    - Total Value Realized YTD — $23.6M (+18.5% YoY)
    - Hard Savings             — $15.2M
    - Soft Savings             — $8.4M
    - Savings Breakdown by Source (Stacked Bar: Negotiation, Volume Discounts, Consolidation)

  RISK & GOVERNANCE (5 cards):
    1. Maverick Spend          — 12.4%  (2.4% above tolerance)
    2. Supplier Concentration  — High   (3 critical suppliers > 40%)
    3. Contract Compliance     — 96%    (Best in class)
    4. High-Risk Suppliers     — 7      (Requires immediate review)
    5. Audit Exceptions        — 2      (Pending resolution)

  OPERATIONAL PERFORMANCE:
    1. Avg. Approval Cycle Time — 1.2 Days (▼ 0.4 Days)
    2. PO to Invoice Cycle      — 14 Days  (Stable)
    3. SLA Adherence            — 98.5%    (▲ 1.2%)

  PROCESS BOTTLENECKS:
    1. Legal Review Queue — Contracts >$50k stuck for avg 5 days, 12 pending
    2. IT Hardware Approvals — 2-day delay from CTO office

  EXECUTIVE ALERTS:
    1. Q1 Marketing Budget Overrun — Critical — $450k excess
    2. Critical Supplier Risk: TechFlow Inc. — Critical — sole supplier
    3. Contract Expiry: Global Facilities — High — $2.5M, 45 days
=============================================================================
*/


-- =====================================================
-- COMMON PARAMS CTE (reused by all queries)
-- =====================================================
-- Adjust these filter values to match dashboard filters.
-- NULL means "no filter" (show all).
-- period_type: 'quarter', 'ytd', 'last_12_months'
-- =====================================================

/*
  PARAM REFERENCE:
    vendor_id      => NULL for CXO-level (all orgs), or specific org_id
    start_date     => Derived from Period filter
    end_date       => Derived from Period filter
    prev_start     => Previous period start for trend comparison
    prev_end       => Previous period end for trend comparison
    region_filter  => NULL = Global, else specific region/state
    category_filter=> NULL = All Categories, else specific category name
    spend_type     => NULL = Direct & Indirect, 'Direct', 'Indirect'
    supplier_tier  => NULL = All, 'Strategic' = Strategic Only
*/


-- =============================================================================
-- KPI 1: TOTAL SPEND
-- Dashboard shows: $142.5M (+12% vs last period)
-- =============================================================================
WITH params AS (
    SELECT
        NULL::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-10-01'::DATE AS prev_start,
        '2025-12-31'::DATE AS prev_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter,
        NULL::TEXT AS spend_type,
        'Strategic'::TEXT AS supplier_tier
),
product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),
current_spend AS (
    SELECT
        COALESCE(SUM(pi.total_amount), 0) AS total_spend
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
      AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
),
previous_spend AS (
    SELECT
        COALESCE(SUM(pi.total_amount), 0) AS total_spend
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_start AND p.prev_end
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
      AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
)
SELECT
    'Total Spend' AS kpi_name,
    ROUND(cs.total_spend::NUMERIC, 2) AS current_value,
    ROUND(ps.total_spend::NUMERIC, 2) AS previous_value,
    CASE WHEN ps.total_spend > 0
         THEN ROUND(((cs.total_spend - ps.total_spend) / ps.total_spend * 100)::NUMERIC, 1)
         ELSE 0
    END AS pct_change_vs_last_period,
    'neutral' AS trend_status
FROM current_spend cs, previous_spend ps;


-- =============================================================================
-- KPI 2: COST SAVINGS
-- Dashboard shows: $18.2M (+8.5% vs last period)
-- Logic: Difference between quoted price (unit_price * qty) and actual total_amount
-- =============================================================================
WITH params AS (
    SELECT
        NULL::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-10-01'::DATE AS prev_start,
        '2025-12-31'::DATE AS prev_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),
current_savings AS (
    SELECT
        COALESCE(SUM(pi.qty * pi.unit_price) - SUM(pi.total_amount), 0) AS cost_savings
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
      AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
),
previous_savings AS (
    SELECT
        COALESCE(SUM(pi.qty * pi.unit_price) - SUM(pi.total_amount), 0) AS cost_savings
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_start AND p.prev_end
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
      AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
)
SELECT
    'Cost Savings' AS kpi_name,
    ROUND(cs.cost_savings::NUMERIC, 2) AS current_value,
    ROUND(ps.cost_savings::NUMERIC, 2) AS previous_value,
    CASE WHEN ps.cost_savings > 0
         THEN ROUND(((cs.cost_savings - ps.cost_savings) / ps.cost_savings * 100)::NUMERIC, 1)
         ELSE 0
    END AS pct_change_vs_last_period,
    'positive' AS trend_status
FROM current_savings cs, previous_savings ps;


-- =============================================================================
-- KPI 3: EBITDA IMPACT
-- Dashboard shows: $4.3M (+2.1% vs last period)
-- Logic: Net savings impact = Cost Savings - Procurement operational cost
--        Procurement operational cost approximated from discount + logistics + shipping + insurance
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-10-01'::DATE AS prev_start,
        '2025-12-31'::DATE AS prev_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),
current_ebitda AS (
    SELECT
        COALESCE(
            SUM(pi.qty * pi.unit_price) - SUM(pi.total_amount)
            - SUM(COALESCE(pi.logistics, 0) + COALESCE(pi.shipping, 0) + COALESCE(pi.insurance, 0)),
        0) AS ebitda_impact
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
      AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
),
previous_ebitda AS (
    SELECT
        COALESCE(
            SUM(pi.qty * pi.unit_price) - SUM(pi.total_amount)
            - SUM(COALESCE(pi.logistics, 0) + COALESCE(pi.shipping, 0) + COALESCE(pi.insurance, 0)),
        0) AS ebitda_impact
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_start AND p.prev_end
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
      AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
)
SELECT
    'EBITDA Impact' AS kpi_name,
    ROUND(ce.ebitda_impact::NUMERIC, 2) AS current_value,
    ROUND(pe.ebitda_impact::NUMERIC, 2) AS previous_value,
    CASE WHEN pe.ebitda_impact > 0
         THEN ROUND(((ce.ebitda_impact - pe.ebitda_impact) / pe.ebitda_impact * 100)::NUMERIC, 1)
         ELSE 0
    END AS pct_change_vs_last_period,
    'positive' AS trend_status
FROM current_ebitda ce, previous_ebitda pe;


-- =============================================================================
-- KPI 4: PROCUREMENT ROI
-- Dashboard shows: 6.4x (+0.3x vs last period)
-- Logic: Cost Savings / Procurement Operating Cost
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-10-01'::DATE AS prev_start,
        '2025-12-31'::DATE AS prev_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),
current_roi AS (
    SELECT
        COALESCE(SUM(pi.qty * pi.unit_price) - SUM(pi.total_amount), 0) AS cost_savings,
        COALESCE(SUM(COALESCE(pi.logistics, 0) + COALESCE(pi.shipping, 0) + COALESCE(pi.insurance, 0)), 1) AS procurement_cost
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
      AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
),
previous_roi AS (
    SELECT
        COALESCE(SUM(pi.qty * pi.unit_price) - SUM(pi.total_amount), 0) AS cost_savings,
        COALESCE(SUM(COALESCE(pi.logistics, 0) + COALESCE(pi.shipping, 0) + COALESCE(pi.insurance, 0)), 1) AS procurement_cost
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_start AND p.prev_end
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
      AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
)
SELECT
    'Procurement ROI' AS kpi_name,
    ROUND((cr.cost_savings / NULLIF(cr.procurement_cost, 0))::NUMERIC, 1) AS current_roi_x,
    ROUND((pr.cost_savings / NULLIF(pr.procurement_cost, 0))::NUMERIC, 1) AS previous_roi_x,
    ROUND((
        (cr.cost_savings / NULLIF(cr.procurement_cost, 0))
        - (pr.cost_savings / NULLIF(pr.procurement_cost, 0))
    )::NUMERIC, 1) AS roi_change_x,
    'positive' AS trend_status
FROM current_roi cr, previous_roi pr;


-- =============================================================================
-- KPI 5: RISK EXPOSURE
-- Dashboard shows: Medium (+2 vs last period)
-- Logic: Count of high-risk events (supplier concentration, maverick spend,
--        contract issues, low-rated suppliers)
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-10-01'::DATE AS prev_start,
        '2025-12-31'::DATE AS prev_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
-- Count suppliers with low ratings (<3.0) in current period
current_risk_factors AS (
    SELECT
        -- Low-rated suppliers
        COUNT(DISTINCT CASE WHEN org.supplier_avg_rating < 3.0 THEN org.org_id END) AS low_rated_suppliers,
        -- Single-source categories (supplier concentration risk)
        COUNT(DISTINCT CASE
            WHEN supplier_counts.supplier_cnt = 1 THEN supplier_counts.category_name
        END) AS single_source_categories,
        -- Overdue deliveries
        COUNT(DISTINCT CASE
            WHEN asn."Actual_delivery_date" > asn.expected_delivery_date THEN pd.id
        END) AS overdue_deliveries
    FROM po_details pd
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN po_asn asn ON asn.tax_invoice_id = ti.id
    LEFT JOIN (
        SELECT
            pc_inner.category_name,
            COUNT(DISTINCT pd_inner.seller_org_id) AS supplier_cnt
        FROM po_details pd_inner
        JOIN po_items pi_inner ON pi_inner.po_id = pd_inner.id
        LEFT JOIN (
            SELECT vp.id AS product_id,
                   (SELECT cat->>'name' FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
                    ORDER BY (cat->>'level')::INT DESC LIMIT 1) AS category_name
            FROM vendor_products vp
        ) pc_inner ON pi_inner.product_id = pc_inner.product_id
        CROSS JOIN params p
        WHERE pd_inner.created_date BETWEEN p.start_date AND p.end_date
        GROUP BY pc_inner.category_name
    ) supplier_counts ON TRUE
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
),
previous_risk_factors AS (
    SELECT
        COUNT(DISTINCT CASE WHEN org.supplier_avg_rating < 3.0 THEN org.org_id END) AS low_rated_suppliers
    FROM po_details pd
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_start AND p.prev_end
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
)
SELECT
    'Risk Exposure' AS kpi_name,
    crf.low_rated_suppliers + crf.single_source_categories AS current_risk_score,
    CASE
        WHEN (crf.low_rated_suppliers + crf.single_source_categories) >= 10 THEN 'High'
        WHEN (crf.low_rated_suppliers + crf.single_source_categories) >= 5 THEN 'Medium'
        ELSE 'Low'
    END AS risk_level,
    (crf.low_rated_suppliers + crf.single_source_categories)
    - prf.low_rated_suppliers AS change_vs_last_period,
    'warning' AS trend_status
FROM current_risk_factors crf, previous_risk_factors prf;


-- =============================================================================
-- KPI 6: COMPLIANCE SCORE
-- Dashboard shows: 94.2% (-1.2% vs last period)
-- Logic: % of POs that went through proper approval flow (have tax invoice)
--        and were fulfilled within SLA
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-10-01'::DATE AS prev_start,
        '2025-12-31'::DATE AS prev_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
current_compliance AS (
    SELECT
        COUNT(*) AS total_pos,
        COUNT(CASE WHEN pd.status IN (5, 6) AND ti.id IS NOT NULL THEN 1 END) AS compliant_pos,
        ROUND((
            COUNT(CASE WHEN pd.status IN (5, 6) AND ti.id IS NOT NULL THEN 1 END) * 100.0
            / NULLIF(COUNT(*), 0)
        )::NUMERIC, 1) AS compliance_pct
    FROM po_details pd
    LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
),
previous_compliance AS (
    SELECT
        ROUND((
            COUNT(CASE WHEN pd.status IN (5, 6) AND ti.id IS NOT NULL THEN 1 END) * 100.0
            / NULLIF(COUNT(*), 0)
        )::NUMERIC, 1) AS compliance_pct
    FROM po_details pd
    LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_start AND p.prev_end
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
)
SELECT
    'Compliance Score' AS kpi_name,
    cc.compliance_pct AS current_value,
    pc.compliance_pct AS previous_value,
    ROUND((cc.compliance_pct - pc.compliance_pct)::NUMERIC, 1) AS pct_change_vs_last_period,
    CASE
        WHEN cc.compliance_pct >= 95 THEN 'positive'
        WHEN cc.compliance_pct >= 90 THEN 'warning'
        ELSE 'negative'
    END AS trend_status
FROM current_compliance cc, previous_compliance pc;


-- =============================================================================
-- CHART 1: SPEND BY CATEGORY (Pie Chart)
-- Dashboard shows: IT Services, Logistics, Marketing, Facilities, Professional Svc
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
)
SELECT
    COALESCE(pc.category_name, 'Uncategorized') AS category,
    ROUND(SUM(pi.total_amount)::NUMERIC, 2) AS spend_amount,
    ROUND((
        SUM(pi.total_amount) * 100.0 / NULLIF(SUM(SUM(pi.total_amount)) OVER(), 0)
    )::NUMERIC, 1) AS spend_pct
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
  AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
GROUP BY COALESCE(pc.category_name, 'Uncategorized')
ORDER BY spend_amount DESC
LIMIT 10;


-- =============================================================================
-- CHART 2: SPEND BY REGION ($M) (Bar Chart)
-- Dashboard shows: NA, EU, APAC, LATAM, EMEA bars
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
)
SELECT
    COALESCE(ua.region, org.state, 'Unknown') AS region,
    ROUND(SUM(pi.total_amount)::NUMERIC, 2) AS spend_amount,
    ROUND((SUM(pi.total_amount) / 1000000.0)::NUMERIC, 2) AS spend_in_millions
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
  AND (p.category_filter IS NULL OR pc.category_name ILIKE '%' || p.category_filter || '%')
GROUP BY COALESCE(ua.region, org.state, 'Unknown')
ORDER BY spend_amount DESC;


-- =============================================================================
-- CHART 3: MANAGED VS UNMANAGED SPEND (Donut Chart)
-- Dashboard shows: 82% Managed, 18% Unmanaged
-- Logic: Managed = POs with tax invoice (proper procurement flow)
--        Unmanaged = POs without proper documentation
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
)
SELECT
    CASE WHEN ti.id IS NOT NULL THEN 'Managed' ELSE 'Unmanaged' END AS spend_type,
    ROUND(SUM(pi.total_amount)::NUMERIC, 2) AS spend_amount,
    ROUND((
        SUM(pi.total_amount) * 100.0 / NULLIF(SUM(SUM(pi.total_amount)) OVER(), 0)
    )::NUMERIC, 1) AS spend_pct
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
GROUP BY CASE WHEN ti.id IS NOT NULL THEN 'Managed' ELSE 'Unmanaged' END
ORDER BY spend_pct DESC;


-- =============================================================================
-- CHART 4: BUDGET VS ACTUAL (Bar Chart)
-- Dashboard shows: Q1, Q2, Q3, Q4 bars with Budget (gray) and Actual (blue dots)
-- Logic: Budget = quoted amount (unit_price * qty), Actual = total_amount
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2025-01-01'::DATE AS start_date,  -- Full year for quarterly view
        '2025-12-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
)
SELECT
    'Q' || EXTRACT(QUARTER FROM pd.created_date)::TEXT AS quarter,
    ROUND(SUM(pi.qty * pi.unit_price)::NUMERIC, 2) AS budget_amount,
    ROUND(SUM(pi.total_amount)::NUMERIC, 2) AS actual_amount,
    ROUND((
        (SUM(pi.total_amount) - SUM(pi.qty * pi.unit_price)) * 100.0
        / NULLIF(SUM(pi.qty * pi.unit_price), 0)
    )::NUMERIC, 1) AS variance_pct
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
GROUP BY EXTRACT(QUARTER FROM pd.created_date)
ORDER BY EXTRACT(QUARTER FROM pd.created_date);


-- =============================================================================
-- SAVINGS: TOTAL VALUE REALIZED (YTD)
-- Dashboard shows: $23.6M (+18.5% YoY), Hard Savings $15.2M, Soft Savings $8.4M
-- Hard Savings = direct price negotiation savings (quoted - actual)
-- Soft Savings = cost avoidance (discount + logistics optimization)
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-01-01'::DATE AS prev_year_start,
        '2025-03-31'::DATE AS prev_year_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
current_savings AS (
    SELECT
        -- Hard savings: negotiation savings (quoted vs actual price)
        COALESCE(SUM(pi.qty * pi.unit_price) - SUM(pi.net_total), 0) AS hard_savings,
        -- Soft savings: cost avoidance from discounts and optimized logistics
        COALESCE(SUM(COALESCE(pi.discount, 0)), 0) AS soft_savings
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
),
previous_year_savings AS (
    SELECT
        COALESCE(SUM(pi.qty * pi.unit_price) - SUM(pi.net_total), 0) AS hard_savings,
        COALESCE(SUM(COALESCE(pi.discount, 0)), 0) AS soft_savings
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_year_start AND p.prev_year_end
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
)
SELECT
    'Total Value Realized' AS metric_name,
    ROUND((cs.hard_savings + cs.soft_savings)::NUMERIC, 2) AS total_value_ytd,
    ROUND(cs.hard_savings::NUMERIC, 2) AS hard_savings,
    ROUND(cs.soft_savings::NUMERIC, 2) AS soft_savings_cost_avoidance,
    CASE WHEN (pys.hard_savings + pys.soft_savings) > 0
         THEN ROUND((
            ((cs.hard_savings + cs.soft_savings) - (pys.hard_savings + pys.soft_savings))
            / (pys.hard_savings + pys.soft_savings) * 100
         )::NUMERIC, 1)
         ELSE 0
    END AS yoy_change_pct,
    ROUND((cs.hard_savings * 100.0 / NULLIF(cs.hard_savings + cs.soft_savings, 0))::NUMERIC, 1) AS hard_savings_pct,
    ROUND((cs.soft_savings * 100.0 / NULLIF(cs.hard_savings + cs.soft_savings, 0))::NUMERIC, 1) AS soft_savings_pct
FROM current_savings cs, previous_year_savings pys;


-- =============================================================================
-- SAVINGS: BREAKDOWN BY SOURCE (Stacked Bar Chart)
-- Dashboard shows: Q1-Q4 stacked bars with Negotiation, Volume Discounts, Consolidation
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2025-01-01'::DATE AS start_date,
        '2025-12-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
)
SELECT
    'Q' || EXTRACT(QUARTER FROM pd.created_date)::TEXT AS quarter,
    -- Negotiation savings: difference between unit_price * qty and gross_amount
    ROUND(SUM(GREATEST(pi.qty * pi.unit_price - pi.gross_amount, 0))::NUMERIC, 2) AS negotiation_savings,
    -- Volume discount savings: actual discount column
    ROUND(SUM(COALESCE(pi.discount, 0))::NUMERIC, 2) AS volume_discount_savings,
    -- Consolidation savings: logistics + shipping optimization
    ROUND(SUM(
        GREATEST(
            (pi.qty * pi.unit_price * 0.05) - COALESCE(pi.logistics, 0) - COALESCE(pi.shipping, 0),
            0
        )
    )::NUMERIC, 2) AS consolidation_savings
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
GROUP BY EXTRACT(QUARTER FROM pd.created_date)
ORDER BY EXTRACT(QUARTER FROM pd.created_date);


-- =============================================================================
-- RISK 1: MAVERICK SPEND
-- Dashboard shows: 12.4% (2.4% above tolerance)
-- Logic: % of spend on POs without proper approval flow (no tax invoice or
--        non-standard procurement path)
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter,
        10.0::NUMERIC AS tolerance_pct  -- 10% tolerance threshold
)
SELECT
    'Maverick Spend' AS metric_name,
    ROUND((
        SUM(CASE WHEN ti.id IS NULL THEN pi.total_amount ELSE 0 END) * 100.0
        / NULLIF(SUM(pi.total_amount), 0)
    )::NUMERIC, 1) AS maverick_spend_pct,
    ROUND(SUM(CASE WHEN ti.id IS NULL THEN pi.total_amount ELSE 0 END)::NUMERIC, 2) AS maverick_spend_amount,
    ROUND(SUM(pi.total_amount)::NUMERIC, 2) AS total_spend,
    ROUND((
        SUM(CASE WHEN ti.id IS NULL THEN pi.total_amount ELSE 0 END) * 100.0
        / NULLIF(SUM(pi.total_amount), 0)
        - p.tolerance_pct
    )::NUMERIC, 1) AS above_tolerance_pct,
    CASE
        WHEN SUM(CASE WHEN ti.id IS NULL THEN pi.total_amount ELSE 0 END) * 100.0
             / NULLIF(SUM(pi.total_amount), 0) > p.tolerance_pct
        THEN 'warning'
        ELSE 'safe'
    END AS status
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
GROUP BY p.tolerance_pct;


-- =============================================================================
-- RISK 2: SUPPLIER CONCENTRATION
-- Dashboard shows: High (3 critical suppliers > 40%)
-- Logic: Identify suppliers whose spend share exceeds 40% in any category
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),
supplier_category_spend AS (
    SELECT
        pd.seller_org_id,
        org.company_name AS supplier_name,
        COALESCE(pc.category_name, 'Uncategorized') AS category,
        SUM(pi.total_amount) AS supplier_spend,
        SUM(SUM(pi.total_amount)) OVER(PARTITION BY COALESCE(pc.category_name, 'Uncategorized')) AS category_total
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
    GROUP BY pd.seller_org_id, org.company_name, COALESCE(pc.category_name, 'Uncategorized')
)
SELECT
    'Supplier Concentration' AS metric_name,
    COUNT(*) FILTER (WHERE (supplier_spend / NULLIF(category_total, 0) * 100) > 40) AS critical_suppliers_above_40pct,
    CASE
        WHEN COUNT(*) FILTER (WHERE (supplier_spend / NULLIF(category_total, 0) * 100) > 40) >= 3 THEN 'High'
        WHEN COUNT(*) FILTER (WHERE (supplier_spend / NULLIF(category_total, 0) * 100) > 40) >= 1 THEN 'Medium'
        ELSE 'Low'
    END AS concentration_level,
    'critical' AS status;


-- =============================================================================
-- RISK 3: CONTRACT COMPLIANCE
-- Dashboard shows: 96% (Best in class)
-- Logic: % of POs with complete documentation (tax invoice + proper status)
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
)
SELECT
    'Contract Compliance' AS metric_name,
    COUNT(*) AS total_contracts,
    COUNT(CASE WHEN pd.status IN (5, 6) AND ti.id IS NOT NULL THEN 1 END) AS compliant_contracts,
    ROUND((
        COUNT(CASE WHEN pd.status IN (5, 6) AND ti.id IS NOT NULL THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0)
    )::NUMERIC, 1) AS compliance_pct,
    CASE
        WHEN COUNT(CASE WHEN pd.status IN (5, 6) AND ti.id IS NOT NULL THEN 1 END) * 100.0
             / NULLIF(COUNT(*), 0) >= 95 THEN 'Best in class'
        WHEN COUNT(CASE WHEN pd.status IN (5, 6) AND ti.id IS NOT NULL THEN 1 END) * 100.0
             / NULLIF(COUNT(*), 0) >= 85 THEN 'Good'
        ELSE 'Needs improvement'
    END AS compliance_label,
    'safe' AS status
FROM po_details pd
LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter);


-- =============================================================================
-- RISK 4: HIGH-RISK SUPPLIERS
-- Dashboard shows: 7 (Requires immediate review)
-- Logic: Suppliers with avg rating < 2.5 OR overdue deliveries > 30%
-- =============================================================================
WITH params AS (
    SELECT
        NULL::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
supplier_performance AS (
    SELECT
        pd.seller_org_id,
        org.company_name AS supplier_name,
        org.supplier_avg_rating,
        COUNT(*) AS total_deliveries,
        COUNT(CASE WHEN asn."Actual_delivery_date" > asn.expected_delivery_date THEN 1 END) AS overdue_deliveries,
        ROUND((
            COUNT(CASE WHEN asn."Actual_delivery_date" > asn.expected_delivery_date THEN 1 END) * 100.0
            / NULLIF(COUNT(*), 0)
        )::NUMERIC, 1) AS overdue_pct
    FROM po_details pd
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN po_asn asn ON asn.tax_invoice_id = ti.id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
    GROUP BY pd.seller_org_id, org.company_name, org.supplier_avg_rating
)
SELECT
    'High-Risk Suppliers' AS metric_name,
    COUNT(*) AS high_risk_count,
    CASE WHEN COUNT(*) > 5 THEN 'Requires immediate review'
         WHEN COUNT(*) > 0 THEN 'Monitor closely'
         ELSE 'No high-risk suppliers'
    END AS action_required,
    'critical' AS status
FROM supplier_performance
WHERE supplier_avg_rating < 2.5 OR overdue_pct > 30;


-- =============================================================================
-- RISK 5: AUDIT EXCEPTIONS
-- Dashboard shows: 2 (Pending resolution)
-- Logic: POs with status discrepancies (fulfilled but missing documents)
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
)
SELECT
    'Audit Exceptions' AS metric_name,
    COUNT(DISTINCT pd.id) AS exception_count,
    CASE WHEN COUNT(DISTINCT pd.id) > 0 THEN 'Pending resolution'
         ELSE 'No exceptions'
    END AS resolution_status,
    CASE WHEN COUNT(DISTINCT pd.id) > 3 THEN 'critical'
         WHEN COUNT(DISTINCT pd.id) > 0 THEN 'warning'
         ELSE 'safe'
    END AS status
FROM po_details pd
LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN po_proforma_invoice ppi ON ppi.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND pd.status IN (5, 6)                    -- Fulfilled/completed
  AND (ti.id IS NULL OR ppi.id IS NULL)      -- Missing tax invoice OR proforma
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter);


-- =============================================================================
-- OPERATIONAL PERFORMANCE 1: AVG APPROVAL CYCLE TIME
-- Dashboard shows: 1.2 Days (▼ 0.4 Days)
-- Logic: Average time from PO creation to first tax invoice
-- =============================================================================
WITH params AS (
    SELECT
        NULL::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-10-01'::DATE AS prev_start,
        '2025-12-31'::DATE AS prev_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
current_cycle AS (
    SELECT
        ROUND(AVG(
            EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400
        )::NUMERIC, 1) AS avg_approval_days
    FROM po_details pd
    JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
),
previous_cycle AS (
    SELECT
        ROUND(AVG(
            EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400
        )::NUMERIC, 1) AS avg_approval_days
    FROM po_details pd
    JOIN po_tax_invoice ti ON ti.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_start AND p.prev_end
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
)
SELECT
    'Avg. Approval Cycle Time' AS metric_name,
    cc.avg_approval_days AS current_days,
    pc.avg_approval_days AS previous_days,
    ROUND((pc.avg_approval_days - cc.avg_approval_days)::NUMERIC, 1) AS improvement_days,
    CASE WHEN cc.avg_approval_days < pc.avg_approval_days THEN 'positive' ELSE 'negative' END AS trend,
    ROUND((cc.avg_approval_days / 4.0 * 100)::NUMERIC, 0) AS progress_pct  -- 4 days as max benchmark
FROM current_cycle cc, previous_cycle pc;


-- =============================================================================
-- OPERATIONAL PERFORMANCE 2: PO TO INVOICE CYCLE
-- Dashboard shows: 14 Days (Stable)
-- Logic: Average time from PO creation to proforma invoice
-- =============================================================================
WITH params AS (
    SELECT
        NULL::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-10-01'::DATE AS prev_start,
        '2025-12-31'::DATE AS prev_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
current_cycle AS (
    SELECT
        ROUND(AVG(COALESCE(ppi.invoice_due_days, 0))::NUMERIC, 0) AS avg_po_to_invoice_days
    FROM po_details pd
    JOIN po_proforma_invoice ppi ON ppi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
),
previous_cycle AS (
    SELECT
        ROUND(AVG(COALESCE(ppi.invoice_due_days, 0))::NUMERIC, 0) AS avg_po_to_invoice_days
    FROM po_details pd
    JOIN po_proforma_invoice ppi ON ppi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_start AND p.prev_end
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
)
SELECT
    'PO to Invoice Cycle' AS metric_name,
    cc.avg_po_to_invoice_days AS current_days,
    pc.avg_po_to_invoice_days AS previous_days,
    CASE
        WHEN ABS(cc.avg_po_to_invoice_days - pc.avg_po_to_invoice_days) <= 1 THEN 'Stable'
        WHEN cc.avg_po_to_invoice_days < pc.avg_po_to_invoice_days THEN 'Improved'
        ELSE 'Degraded'
    END AS trend,
    ROUND((cc.avg_po_to_invoice_days / 30.0 * 100)::NUMERIC, 0) AS progress_pct  -- 30 days as max
FROM current_cycle cc, previous_cycle pc;


-- =============================================================================
-- OPERATIONAL PERFORMANCE 3: SLA ADHERENCE
-- Dashboard shows: 98.5% (▲ 1.2%)
-- Logic: % of deliveries where actual delivery <= expected delivery date
-- =============================================================================
WITH params AS (
    SELECT
        NULL::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        '2025-10-01'::DATE AS prev_start,
        '2025-12-31'::DATE AS prev_end,
        NULL::TEXT AS region_filter,
        NULL::TEXT AS category_filter
),
current_sla AS (
    SELECT
        COUNT(*) AS total_deliveries,
        COUNT(CASE
            WHEN asn."Actual_delivery_date" <= asn.expected_delivery_date THEN 1
        END) AS on_time_deliveries,
        ROUND((
            COUNT(CASE WHEN asn."Actual_delivery_date" <= asn.expected_delivery_date THEN 1 END) * 100.0
            / NULLIF(COUNT(*), 0)
        )::NUMERIC, 1) AS sla_pct
    FROM po_details pd
    JOIN po_tax_invoice ti ON ti.po_id = pd.id
    JOIN po_asn asn ON asn.tax_invoice_id = ti.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    LEFT JOIN user_address ua ON pd.shipping_address = ua.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND asn."Actual_delivery_date" IS NOT NULL
      AND asn.expected_delivery_date IS NOT NULL
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
      AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
),
previous_sla AS (
    SELECT
        ROUND((
            COUNT(CASE WHEN asn."Actual_delivery_date" <= asn.expected_delivery_date THEN 1 END) * 100.0
            / NULLIF(COUNT(*), 0)
        )::NUMERIC, 1) AS sla_pct
    FROM po_details pd
    JOIN po_tax_invoice ti ON ti.po_id = pd.id
    JOIN po_asn asn ON asn.tax_invoice_id = ti.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.prev_start AND p.prev_end
      AND asn."Actual_delivery_date" IS NOT NULL
      AND asn.expected_delivery_date IS NOT NULL
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
)
SELECT
    'SLA Adherence' AS metric_name,
    cs.sla_pct AS current_pct,
    ps.sla_pct AS previous_pct,
    ROUND((cs.sla_pct - ps.sla_pct)::NUMERIC, 1) AS change_pct,
    CASE WHEN cs.sla_pct >= ps.sla_pct THEN 'positive' ELSE 'negative' END AS trend,
    cs.sla_pct AS progress_pct
FROM current_sla cs, previous_sla ps;


-- =============================================================================
-- PROCESS BOTTLENECK 1: LEGAL REVIEW QUEUE
-- Dashboard shows: Contracts >$50k stuck for avg 5 days, 12 pending
-- Logic: POs > $50k that have been created but not yet invoiced (stuck in approval)
-- =============================================================================
WITH params AS (
    SELECT
        NULL::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter,
        50000::NUMERIC AS threshold_amount
)
SELECT
    'Legal Review Queue' AS bottleneck_name,
    COUNT(DISTINCT pd.id) AS pending_contracts,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - pd.created_date)) / 86400
    )::NUMERIC, 1) AS avg_days_pending,
    ROUND(SUM(pd.total_amount)::NUMERIC, 2) AS total_value_pending
FROM po_details pd
LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND pd.status NOT IN (5, 6)           -- Not yet fulfilled
  AND ti.id IS NULL                      -- No tax invoice yet (stuck in approval)
  AND pd.total_amount > p.threshold_amount  -- Contracts > $50k
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter);


-- =============================================================================
-- PROCESS BOTTLENECK 2: IT HARDWARE APPROVALS
-- Dashboard shows: 2-day delay from CTO office
-- Logic: POs for IT/Hardware category with longer-than-average approval time
-- =============================================================================
WITH params AS (
    SELECT
        NULL::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter
),
product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
),
avg_approval AS (
    SELECT
        ROUND(AVG(
            EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400
        )::NUMERIC, 1) AS overall_avg_days
    FROM po_details pd
    JOIN po_tax_invoice ti ON ti.po_id = pd.id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
)
SELECT
    'IT Hardware Approvals' AS bottleneck_name,
    ROUND(AVG(
        EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400
    )::NUMERIC, 1) AS avg_approval_days,
    aa.overall_avg_days AS overall_avg_days,
    ROUND((
        AVG(EXTRACT(EPOCH FROM (ti.created_date - pd.created_date)) / 86400)
        - aa.overall_avg_days
    )::NUMERIC, 1) AS delay_vs_average,
    COUNT(DISTINCT pd.id) AS affected_pos
FROM po_details pd
JOIN po_tax_invoice ti ON ti.po_id = pd.id
JOIN po_items pi ON pi.po_id = pd.id
LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
CROSS JOIN params p
CROSS JOIN avg_approval aa
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (pc.category_name ILIKE '%IT%' OR pc.category_name ILIKE '%Hardware%'
       OR pc.category_name ILIKE '%Computer%' OR pc.category_name ILIKE '%Electronic%')
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
GROUP BY aa.overall_avg_days;


-- =============================================================================
-- EXECUTIVE ALERT 1: BUDGET OVERRUN BY CATEGORY
-- Dashboard shows: Q1 Marketing Budget Overrun — $450k excess, 15% over
-- Logic: Categories where actual spend exceeds quoted/budgeted amount
-- =============================================================================
WITH params AS (
    SELECT
        NULL::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter
),
product_categories AS (
    SELECT
        vp.id AS product_id,
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
)
SELECT
    'Budget Overrun' AS alert_type,
    'Critical' AS severity,
    COALESCE(pc.category_name, 'Uncategorized') AS category,
    ROUND(SUM(pi.qty * pi.unit_price)::NUMERIC, 2) AS budgeted_amount,
    ROUND(SUM(pi.total_amount)::NUMERIC, 2) AS actual_amount,
    ROUND((SUM(pi.total_amount) - SUM(pi.qty * pi.unit_price))::NUMERIC, 2) AS excess_spend,
    ROUND((
        (SUM(pi.total_amount) - SUM(pi.qty * pi.unit_price)) * 100.0
        / NULLIF(SUM(pi.qty * pi.unit_price), 0)
    )::NUMERIC, 1) AS overrun_pct,
    COALESCE(ua.region, org.state, 'Unknown') AS region
FROM po_items pi
JOIN po_details pd ON pi.po_id = pd.id
LEFT JOIN product_categories pc ON pi.product_id = pc.product_id
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE pd.created_date BETWEEN p.start_date AND p.end_date
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
GROUP BY COALESCE(pc.category_name, 'Uncategorized'), COALESCE(ua.region, org.state, 'Unknown')
HAVING SUM(pi.total_amount) > SUM(pi.qty * pi.unit_price)
ORDER BY (SUM(pi.total_amount) - SUM(pi.qty * pi.unit_price)) DESC
LIMIT 5;


-- =============================================================================
-- EXECUTIVE ALERT 2: CRITICAL SUPPLIER RISK
-- Dashboard shows: TechFlow Inc. — sole supplier, financial instability
-- Logic: Suppliers with high spend concentration AND low rating
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        '2026-01-01'::DATE AS start_date,
        '2026-03-31'::DATE AS end_date,
        NULL::TEXT AS region_filter
),
supplier_spend AS (
    SELECT
        pd.seller_org_id,
        org.company_name AS supplier_name,
        org.supplier_avg_rating,
        SUM(pi.total_amount) AS supplier_total_spend,
        SUM(SUM(pi.total_amount)) OVER() AS overall_total_spend,
        COUNT(DISTINCT pd.id) AS po_count
    FROM po_items pi
    JOIN po_details pd ON pi.po_id = pd.id
    LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
    CROSS JOIN params p
    WHERE pd.created_date BETWEEN p.start_date AND p.end_date
      AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
    GROUP BY pd.seller_org_id, org.company_name, org.supplier_avg_rating
)
SELECT
    'Critical Supplier Risk' AS alert_type,
    'Critical' AS severity,
    supplier_name,
    ROUND(supplier_total_spend::NUMERIC, 2) AS total_spend,
    ROUND((supplier_total_spend / NULLIF(overall_total_spend, 0) * 100)::NUMERIC, 1) AS spend_share_pct,
    supplier_avg_rating,
    po_count,
    'High Operational Risk - Sole/Major supplier' AS impact
FROM supplier_spend
WHERE (supplier_total_spend / NULLIF(overall_total_spend, 0) * 100) > 20  -- >20% spend share
   OR supplier_avg_rating < 2.5                                             -- Low rated
ORDER BY supplier_total_spend DESC
LIMIT 5;


-- =============================================================================
-- EXECUTIVE ALERT 3: CONTRACT EXPIRY ALERTS
-- Dashboard shows: Global Facilities contract expiring in 45 days, $2.5M
-- Logic: POs/contracts that will reach expected delivery within next 60 days
--        and have high value
-- =============================================================================
WITH params AS (
    SELECT
        91::INTEGER AS vendor_id,
        CURRENT_DATE AS today,
        CURRENT_DATE + INTERVAL '60 days' AS expiry_window,
        NULL::TEXT AS region_filter
)
SELECT
    'Contract Expiry' AS alert_type,
    'High' AS severity,
    org.company_name AS supplier_name,
    pd.id AS po_id,
    ROUND(pd.total_amount::NUMERIC, 2) AS contract_value,
    asn.expected_delivery_date AS expiry_date,
    (asn.expected_delivery_date - p.today) AS days_until_expiry,
    COALESCE(ua.region, org.state, 'Unknown') AS region
FROM po_details pd
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN po_tax_invoice ti ON ti.po_id = pd.id
LEFT JOIN po_asn asn ON asn.tax_invoice_id = ti.id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
CROSS JOIN params p
WHERE asn.expected_delivery_date BETWEEN p.today AND p.expiry_window
  AND pd.status NOT IN (5, 6)   -- Not yet completed
  AND pd.total_amount > 10000   -- High-value contracts
  AND (p.vendor_id IS NULL OR pd.seller_org_id = p.vendor_id)
  AND (p.region_filter IS NULL OR org.state = p.region_filter OR ua.region = p.region_filter)
ORDER BY pd.total_amount DESC
LIMIT 10;


-- =============================================================================
-- FILTER DROPDOWNS: REGION LIST
-- Populates the Region filter dropdown
-- =============================================================================
SELECT DISTINCT
    COALESCE(ua.region, org.state) AS region_name
FROM po_details pd
LEFT JOIN "userApis_organization" org ON pd.seller_org_id = org.org_id
LEFT JOIN user_address ua ON pd.shipping_address = ua.id
WHERE COALESCE(ua.region, org.state) IS NOT NULL
ORDER BY region_name;


-- =============================================================================
-- FILTER DROPDOWNS: CATEGORY LIST
-- Populates the Category filter dropdown
-- =============================================================================
WITH product_categories AS (
    SELECT DISTINCT
        (
            SELECT cat->>'name'
            FROM jsonb_array_elements(vp.category_ids -> 'cat_0') cat
            ORDER BY (cat->>'level')::INT DESC
            LIMIT 1
        ) AS category_name
    FROM vendor_products vp
)
SELECT DISTINCT category_name
FROM product_categories
WHERE category_name IS NOT NULL
ORDER BY category_name;


-- =============================================================================
-- FILTER DROPDOWNS: SUPPLIER TIER LIST
-- Populates the Supplier Tier filter dropdown
-- =============================================================================
SELECT
    CASE
        WHEN org.supplier_avg_rating >= 4.0 THEN 'Strategic'
        WHEN org.supplier_avg_rating >= 3.0 THEN 'Preferred'
        WHEN org.supplier_avg_rating >= 2.0 THEN 'Approved'
        ELSE 'Transactional'
    END AS supplier_tier,
    COUNT(DISTINCT org.org_id) AS supplier_count
FROM "userApis_organization" org
WHERE org.supplier_avg_rating IS NOT NULL
GROUP BY
    CASE
        WHEN org.supplier_avg_rating >= 4.0 THEN 'Strategic'
        WHEN org.supplier_avg_rating >= 3.0 THEN 'Preferred'
        WHEN org.supplier_avg_rating >= 2.0 THEN 'Approved'
        ELSE 'Transactional'
    END
ORDER BY
    CASE
        WHEN MIN(org.supplier_avg_rating) >= 4.0 THEN 1
        WHEN MIN(org.supplier_avg_rating) >= 3.0 THEN 2
        WHEN MIN(org.supplier_avg_rating) >= 2.0 THEN 3
        ELSE 4
    END;
