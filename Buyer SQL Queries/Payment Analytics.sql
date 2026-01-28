---------------------------------------------------------------
-- Card 1: Invoice-to-due days by units
---------------------------------------------------------------

-- WITH base_data AS (
--     SELECT
--         ua.city,
--         ua.country_id,
--         pti.invoice_due_days,
--         EXTRACT(YEAR FROM pti.created_date) AS invoice_year
--     FROM po_tax_invoice pti
--     JOIN po_details pd ON pti.po_id = pd.id
--     JOIN user_address ua ON pd.billing_address = ua.id
--     WHERE pti.invoice_due_days IS NOT NULL
-- ),
-- aggregated AS (
--     SELECT
--         CONCAT_WS(', ', city, country_id) AS unit,
--         ROUND(AVG(invoice_due_days) FILTER (WHERE invoice_year = EXTRACT(YEAR FROM CURRENT_DATE))) AS current_year_avg_due_days,
--         ROUND(AVG(invoice_due_days) FILTER (WHERE invoice_year = EXTRACT(YEAR FROM CURRENT_DATE) - 1)) AS previous_year_avg_due_days,
--         COUNT(*) AS invoice_count
--     FROM base_data
--     GROUP BY city, country_id
-- )
-- SELECT *
-- FROM aggregated
-- ORDER BY unit;

---------------------------------------------------------------
-- Card 2: Invoice-to-due days by categories
---------------------------------------------------------------

-- WITH invoice_data AS (
--     SELECT
--         p.product_id,
--         pti.invoice_due_days,
--         pti.created_date::DATE AS invoice_date,
--         vp.category_ids
--     FROM po_tax_invoice pti
--     JOIN po_items p ON pti.po_id = p.po_id
--     JOIN vendor_products vp ON p.product_id = vp.product_id
--     WHERE pti.invoice_due_days IS NOT NULL
-- ),

-- category_exploded AS (
--     SELECT
--         invoice_due_days,
--         invoice_date,
--         jsonb_array_elements(category_ids -> 'cat_0') ->> 'name' AS category_name,
--         (jsonb_array_elements(category_ids -> 'cat_0') ->> 'level')::int AS category_level,
--         EXTRACT(YEAR FROM invoice_date) AS year
--     FROM invoice_data
-- ),

-- level_3_categories AS (
--     SELECT
--         category_name,
--         invoice_due_days,
--         year
--     FROM category_exploded
--     WHERE category_level = 3
-- ),

-- category_summary AS (
--     SELECT
--         category_name,
--         COUNT(*) FILTER (WHERE year = EXTRACT(YEAR FROM CURRENT_DATE)) AS current_year_count,
--         ROUND(AVG(invoice_due_days) FILTER (WHERE year = EXTRACT(YEAR FROM CURRENT_DATE)), 2) AS current_year_avg_due_days,
--         COUNT(*) FILTER (WHERE year = EXTRACT(YEAR FROM CURRENT_DATE) - 1) AS previous_year_count,
--         ROUND(AVG(invoice_due_days) FILTER (WHERE year = EXTRACT(YEAR FROM CURRENT_DATE) - 1), 2) AS previous_year_avg_due_days
--     FROM level_3_categories
--     GROUP BY category_name
--     ORDER BY category_name
-- )

-- SELECT *
-- FROM category_summary;

---------------------------------------------------------------
-- Card 3: Spend by payment terms (EUR)
---------------------------------------------------------------

-- SELECT
--     LOWER(TRIM(pod.terms)) AS payment_term,
--     ROUND(SUM(poi.total_amount)::numeric, 2) AS total_spend_eur
-- FROM po_items poi
-- JOIN po_details pod ON poi.po_id = pod.id
-- WHERE poi.updated_date IS NOT NULL
-- GROUP BY LOWER(TRIM(pod.terms))
-- ORDER BY total_spend_eur DESC;

---------------------------------------------------------------
-- Card 4: Average payment terms by supplier (EUR)
---------------------------------------------------------------

WITH terms_with_days AS (
    SELECT
        pod.seller_org_id AS supplier_id,
        poi.total_amount,
        COALESCE(
            regmatch.match::int,
            0
        ) AS payment_days
    FROM po_details pod
    JOIN po_items poi ON poi.po_id = pod.id
    LEFT JOIN LATERAL (
        SELECT (regexp_matches(lower(pod.terms), '\d+'))[1] AS match
    ) regmatch ON TRUE
    WHERE pod.terms IS NOT NULL
),
aggregated AS (
    SELECT
        supplier_id,
        ROUND(AVG(payment_days)::numeric, 0) AS avg_payment_term_days,
        ROUND(SUM(total_amount)::numeric, 2) AS total_spend_eur
    FROM terms_with_days
    GROUP BY supplier_id
)

SELECT *
FROM aggregated
ORDER BY total_spend_eur DESC;


