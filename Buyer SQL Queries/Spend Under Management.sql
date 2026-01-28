---------------------------------------------------------------
-- Card 1
---------------------------------------------------------------
-- WITH purchases AS (
--     SELECT 
--         poi.product_id,
--         poi.source_id::text AS vendor_id,
--         poi.total_amount,
--         poi.updated_date,
--         DATE_TRUNC('month', poi.updated_date) AS month
--     FROM po_items poi
--     WHERE poi.updated_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '12 months'
-- ),

-- contracts AS (
--     SELECT 
--         LOWER(TRIM(cd."partyEmail")) AS vendor_email,
--         LOWER(TRIM(cd."partyName")) AS vendor_name,
--         cd."startDate",
--         cd."expiryDate",
--         cd."status"
--     FROM contract_details cd
--     WHERE cd."status" ILIKE 'active'
-- ),

-- classified AS (
--     SELECT
--         p.month,
--         p.total_amount,
--         CASE 
--             WHEN EXISTS (
--                 SELECT 1 FROM contracts c
--                 WHERE p.updated_date BETWEEN c."startDate" AND c."expiryDate"
--                 AND (
--                     p.vendor_id = LOWER(TRIM(c.vendor_name))
--                     OR p.vendor_id = LOWER(TRIM(c.vendor_email))
--                 )
--             ) THEN 'Covered'

--             WHEN EXISTS (
--                 SELECT 1 FROM contracts c
--                 WHERE p.updated_date BETWEEN c."startDate" AND c."expiryDate"
--             ) THEN 'AvailableButNotUsed'

--             ELSE 'NotCovered'
--         END AS contract_status
--     FROM purchases p
-- ),

-- aggregated AS (
--     SELECT 
--         TO_CHAR(month, 'YYYY-MM') AS month,
--         contract_status,
--         SUM(total_amount) AS spend
--     FROM classified
--     GROUP BY month, contract_status
-- ),

-- monthly_totals AS (
--     SELECT 
--         month,
--         SUM(spend) AS total_spend
--     FROM aggregated
--     GROUP BY month
-- ),

-- final AS (
--     SELECT 
--         a.month,
--         a.contract_status,
--         ROUND((100.0 * a.spend / NULLIF(t.total_spend, 0))::numeric, 2) AS spend_percentage
--     FROM aggregated a
--     JOIN monthly_totals t ON a.month = t.month
-- )

-- SELECT 
--     month,
--     COALESCE(MAX(CASE WHEN contract_status = 'Covered' THEN spend_percentage END), 0) AS covered_pct,
--     COALESCE(MAX(CASE WHEN contract_status = 'AvailableButNotUsed' THEN spend_percentage END), 0) AS available_but_not_used_pct,
--     COALESCE(MAX(CASE WHEN contract_status = 'NotCovered' THEN spend_percentage END), 0) AS not_covered_pct
-- FROM final
-- GROUP BY month
-- ORDER BY month;

---------------------------------------------------------------
-- Card 2: Contract Coverage
---------------------------------------------------------------

WITH contract_suppliers AS (
    SELECT DISTINCT "receivedByOrg" AS supplier_org_id
    FROM contract_details
    WHERE status = 'active'
),

purchases AS (
    SELECT 
        poi.product_id,
        poi.total_amount::NUMERIC AS spend,
        poi.updated_date,
        poi.source_id::INTEGER AS supplier_org_id
    FROM po_items poi
    WHERE poi.updated_date >= CURRENT_DATE - INTERVAL '12 months'
),

product_categories AS (
    SELECT 
        vp.product_id,
        vp.org_id AS vendor_org_id,
        cat.value ->> 'name' AS category_l1
    FROM vendor_products vp,
    LATERAL jsonb_array_elements(vp.category_ids -> 'cat_0') AS cat
    WHERE (cat.value ->> 'level')::INT = 3
),

purchases_with_category AS (
    SELECT 
        p.supplier_org_id,
        pc.category_l1,
        p.spend
    FROM purchases p
    JOIN product_categories pc ON p.product_id = pc.product_id
),

spend_classified AS (
    SELECT 
        pwc.category_l1,
        pwc.supplier_org_id,
        pwc.spend,
        CASE
            WHEN cs.supplier_org_id IS NOT NULL THEN 'covered_by_contracts'
            ELSE 'not_covered_by_contracts'
        END AS contract_status
    FROM purchases_with_category pwc
    LEFT JOIN contract_suppliers cs ON pwc.supplier_org_id = cs.supplier_org_id
),

available_contracts AS (
    SELECT DISTINCT 
        pc.category_l1,
        cs.supplier_org_id
    FROM product_categories pc
    JOIN contract_suppliers cs ON pc.vendor_org_id = cs.supplier_org_id
),

final_grouped AS (
    -- Available contract not used: vendors with contracts but no actual spend
    SELECT 
        ac.category_l1,
        'available_contract_not_used' AS contract_status,
        0.0 AS spend
    FROM available_contracts ac
    LEFT JOIN spend_classified sc
        ON ac.category_l1 = sc.category_l1 AND ac.supplier_org_id = sc.supplier_org_id
    WHERE sc.supplier_org_id IS NULL

    UNION ALL

    -- Actual spend (covered / not covered)
    SELECT 
        category_l1,
        contract_status,
        SUM(spend) AS spend
    FROM spend_classified
    GROUP BY category_l1, contract_status
)

SELECT 
    category_l1,
    ROUND(SUM(CASE WHEN contract_status = 'covered_by_contracts' THEN spend ELSE 0 END), 2) AS covered_by_contracts,
    ROUND(SUM(CASE WHEN contract_status = 'available_contract_not_used' THEN spend ELSE 0 END), 2) AS available_contract_not_used,
    ROUND(SUM(CASE WHEN contract_status = 'not_covered_by_contracts' THEN spend ELSE 0 END), 2) AS not_covered_by_contracts,
    ROUND(SUM(spend), 2) AS total_spend
FROM final_grouped
GROUP BY category_l1
ORDER BY total_spend DESC;



