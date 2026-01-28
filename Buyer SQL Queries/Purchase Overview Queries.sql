-- WITH params AS (
--     SELECT 
--         DATE '2025-06-01' AS start_date,
--         DATE '2025-06-20' AS end_date,
--         DATE '2025-05-01' AS prev_start_date,
--         DATE '2025-05-31' AS prev_end_date
-- ),
-- current_period AS (
--     SELECT 
--         jsonb_extract_path_text(cat.value, 'name') AS category_name,
--         SUM(pi.total_amount) AS total_spend
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.product_id
--     CROSS JOIN params p
--     CROSS JOIN LATERAL jsonb_array_elements(vp.category_ids -> 'cat_0') AS cat
--     WHERE 
--         pi.updated_date BETWEEN p.start_date AND p.end_date
--         AND cat.value ->> 'level' = '3'
--     GROUP BY category_name
-- ),
-- previous_period AS (
--     SELECT 
--         jsonb_extract_path_text(cat.value, 'name') AS category_name,
--         SUM(pi.total_amount) AS total_spend
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.product_id
--     CROSS JOIN params p
--     CROSS JOIN LATERAL jsonb_array_elements(vp.category_ids -> 'cat_0') AS cat
--     WHERE 
--         pi.updated_date BETWEEN p.prev_start_date AND p.prev_end_date
--         AND cat.value ->> 'level' = '3'
--     GROUP BY category_name
-- ),
-- combined AS (
--     SELECT 
--         curr.category_name,
--         ROUND(curr.total_spend::numeric, 2) AS current_volume,
--         ROUND(prev.total_spend::numeric, 2) AS previous_volume,
--         ROUND((
--             CASE 
--                 WHEN prev.total_spend = 0 THEN 100
--                 ELSE ((curr.total_spend - prev.total_spend) / prev.total_spend) * 100
--             END
--         )::numeric, 2) AS percent_change
--     FROM current_period curr
--     LEFT JOIN previous_period prev ON curr.category_name = prev.category_name
-- )
-- SELECT *
-- FROM combined
-- ORDER BY current_volume DESC
-- LIMIT 10;
-- ==========================================================

-- WITH params AS (
--     SELECT 
--         DATE '2025-06-01' AS start_date,
--         DATE '2025-06-20' AS end_date
-- ),
-- category_spend AS (
--     SELECT 
--         jsonb_extract_path_text(category_elem.value, 'name') AS category_name,
--         SUM(pi.total_amount) AS total_spend
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.product_id
--     CROSS JOIN params p
--     CROSS JOIN LATERAL jsonb_array_elements(
--         vp.category_ids -> 'cat_0'
--     ) AS category_elem
--     WHERE 
--         pi.updated_date BETWEEN p.start_date AND p.end_date
--         AND category_elem.value ->> 'level' = '3'
--     GROUP BY category_name
-- )
-- SELECT 
--     category_name,
--     ROUND(total_spend::numeric, 2) AS purchasing_volume
-- FROM category_spend
-- ORDER BY total_spend DESC
-- LIMIT 10;
-- ==========================================================

-- WITH params AS (
--     SELECT 
--         '2025-06-01'::date AS start_date,
--         '2025-06-20'::date AS end_date,
--         CASE 
--             WHEN AGE('2025-06-20', '2025-06-01') > INTERVAL '6 years' THEN 'year'
--             WHEN AGE('2025-06-20', '2025-06-01') > INTERVAL '6 months' THEN 'month'
--             WHEN AGE('2025-06-20', '2025-06-01') > INTERVAL '6 weeks' THEN 'week'
--             ELSE 'day'
--         END AS period_type
-- ),
-- filtered_data AS (
--     SELECT 
--         total_amount,
--         updated_date
--     FROM po_items
--     WHERE updated_date BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
-- ),
-- data_with_periods AS (
--     SELECT 
--         DATE_TRUNC((SELECT period_type FROM params), updated_date) AS period,
--         SUM(total_amount) AS purchase_volume
--     FROM filtered_data
--     GROUP BY period
-- ),
-- ranked_periods AS (
--     SELECT 
--         period,
--         purchase_volume,
--         ROW_NUMBER() OVER (ORDER BY period DESC) AS period_rank
--     FROM data_with_periods
-- ),
-- labeled_data AS (
--     SELECT 
--         TO_CHAR(
--             period, 
--             CASE 
--                 WHEN (SELECT period_type FROM params) = 'year' THEN 'YYYY'
--                 WHEN (SELECT period_type FROM params) = 'month' THEN 'Mon YYYY'
--                 WHEN (SELECT period_type FROM params) = 'week' THEN '"Week "IW, YYYY'
--                 ELSE 'DD Mon YYYY'
--             END
--         ) AS period_label,
--         purchase_volume,
--         period_rank
--     FROM ranked_periods
--     WHERE period_rank <= 6
-- ),
-- summary AS (
--     SELECT 
--         MAX(CASE WHEN period_rank = 1 THEN purchase_volume END) AS current_volume,
--         MAX(CASE WHEN period_rank = 2 THEN purchase_volume END) AS previous_volume
--     FROM labeled_data
-- )
-- SELECT 
--     (SELECT json_agg(row_to_json(ld) ORDER BY ld.period_rank DESC) FROM labeled_data ld) AS trend,
--     (SELECT current_volume FROM summary) AS current_value,
--     (SELECT 
--         ROUND(
--             CASE 
--                 WHEN previous_volume = 0 THEN 100
--                 ELSE ((current_volume - previous_volume) / previous_volume::numeric) * 100
--             END::numeric, 2
--         ) 
--      FROM summary) AS percentage_change;
-- ==========================================================

-- WITH params AS (
--     SELECT 
--         '2025-06-01'::date AS start_date,
--         '2025-06-20'::date AS end_date,
--         CASE 
--             WHEN AGE('2025-06-20', '2025-06-01') > INTERVAL '6 years' THEN 'year'
--             WHEN AGE('2025-06-20', '2025-06-01') > INTERVAL '6 months' THEN 'month'
--             WHEN AGE('2025-06-20', '2025-06-01') > INTERVAL '6 weeks' THEN 'week'
--             ELSE 'day'
--         END AS period_type
-- ),
-- filtered_data AS (
--     SELECT 
--         pi.total_amount,
--         pi.updated_date,
--         vp.org_id AS supplier_id
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.product_id
--     WHERE pi.updated_date BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
-- ),
-- data_with_periods AS (
--     SELECT 
--         DATE_TRUNC((SELECT period_type FROM params), updated_date) AS period,
--         supplier_id,
--         SUM(total_amount) AS total_volume
--     FROM filtered_data
--     GROUP BY period, supplier_id
-- ),
-- avg_volume_per_supplier AS (
--     SELECT 
--         period,
--         AVG(total_volume) AS avg_volume_per_supplier
--     FROM data_with_periods
--     GROUP BY period
-- ),
-- ranked_periods AS (
--     SELECT 
--         period,
--         avg_volume_per_supplier,
--         ROW_NUMBER() OVER (ORDER BY period DESC) AS period_rank
--     FROM avg_volume_per_supplier
-- ),
-- labeled_data AS (
--     SELECT 
--         TO_CHAR(
--             period, 
--             CASE 
--                 WHEN (SELECT period_type FROM params) = 'year' THEN 'YYYY'
--                 WHEN (SELECT period_type FROM params) = 'month' THEN 'Mon YYYY'
--                 WHEN (SELECT period_type FROM params) = 'week' THEN '"Week "IW, YYYY'
--                 ELSE 'DD Mon YYYY'
--             END
--         ) AS period_label,
--         avg_volume_per_supplier,
--         period_rank
--     FROM ranked_periods
--     WHERE period_rank <= 6
-- ),
-- summary AS (
--     SELECT 
--         MAX(CASE WHEN period_rank = 1 THEN avg_volume_per_supplier END) AS current_avg_volume,
--         MAX(CASE WHEN period_rank = 2 THEN avg_volume_per_supplier END) AS previous_avg_volume
--     FROM labeled_data
-- )
-- SELECT 
--     (SELECT json_agg(ld ORDER BY ld.period_rank DESC) FROM labeled_data ld) AS trend,
--     (SELECT current_avg_volume FROM summary) AS current_value,
--     (SELECT 
--         ROUND(
--             CASE 
--                 WHEN previous_avg_volume = 0 THEN 100
--                 ELSE ((current_avg_volume - previous_avg_volume) / previous_avg_volume::numeric) * 100
--             END::numeric, 2
--         ) 
--      FROM summary) AS percentage_change;

-- ==========================================================
-- Graph 3: Total Purchase Quantity
-- ==========================================================

-- WITH params AS (
--     SELECT 
--         '2025-06-01'::date AS start_date,
--         '2025-06-20'::date AS end_date,
--         CASE 
--             WHEN AGE('2025-06-20'::date, '2025-06-01'::date) > INTERVAL '6 years' THEN 'year'
--             WHEN AGE('2025-06-20'::date, '2025-06-01'::date) > INTERVAL '6 months' THEN 'month'
--             WHEN AGE('2025-06-20'::date, '2025-06-01'::date) > INTERVAL '6 weeks' THEN 'week'
--             ELSE 'day'
--         END AS period_type
-- ),
-- filtered_data AS (
--     SELECT 
--         qty,
--         updated_date
--     FROM po_items
--     WHERE updated_date BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
-- ),
-- grouped_data AS (
--     SELECT 
--         DATE_TRUNC((SELECT period_type FROM params), updated_date) AS period,
--         SUM(qty) AS total_qty
--     FROM filtered_data
--     GROUP BY period
-- ),
-- ranked_periods AS (
--     SELECT 
--         period,
--         total_qty,
--         ROW_NUMBER() OVER (ORDER BY period DESC) AS period_rank
--     FROM grouped_data
-- ),
-- labeled_data AS (
--     SELECT 
--         TO_CHAR(
--             period, 
--             CASE 
--                 WHEN (SELECT period_type FROM params) = 'year' THEN 'YYYY'
--                 WHEN (SELECT period_type FROM params) = 'month' THEN 'Mon YYYY'
--                 WHEN (SELECT period_type FROM params) = 'week' THEN '"Week "IW, YYYY'
--                 ELSE 'DD Mon YYYY'
--             END
--         ) AS period_label,
--         total_qty,
--         period_rank
--     FROM ranked_periods
--     WHERE period_rank <= 6
-- ),
-- summary AS (
--     SELECT 
--         MAX(CASE WHEN period_rank = 1 THEN total_qty END) AS current_qty,
--         MAX(CASE WHEN period_rank = 2 THEN total_qty END) AS previous_qty
--     FROM labeled_data
-- )
-- SELECT 
--     (SELECT json_agg(ld ORDER BY ld.period_rank DESC) FROM labeled_data ld) AS trend,
--     (SELECT current_qty FROM summary) AS current_value,
--     (SELECT 
--         ROUND(
--             CASE 
--                 WHEN previous_qty = 0 THEN 100
--                 ELSE ((current_qty - previous_qty) / previous_qty::numeric) * 100
--             END::numeric, 2
--         ) 
--      FROM summary) AS percentage_change;

-- ==========================================================
-- Graph 4: Average Buying Price
-- ==========================================================


WITH params AS (
    SELECT 
        '2025-06-01'::date AS start_date,
        '2025-06-20'::date AS end_date,
        CASE 
            WHEN AGE('2025-06-20'::date, '2025-06-01'::date) > INTERVAL '6 years' THEN 'year'
            WHEN AGE('2025-06-20'::date, '2025-06-01'::date) > INTERVAL '6 months' THEN 'month'
            WHEN AGE('2025-06-20'::date, '2025-06-01'::date) > INTERVAL '6 weeks' THEN 'week'
            ELSE 'day'
        END AS period_type
),
filtered_data AS (
    SELECT 
        qty,
        total_amount,
        updated_date
    FROM po_items
    WHERE updated_date BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
),
grouped_data AS (
    SELECT 
        DATE_TRUNC((SELECT period_type FROM params), updated_date) AS period,
        SUM(total_amount) AS total_amount,
        SUM(qty) AS total_qty
    FROM filtered_data
    GROUP BY period
),
avg_price_data AS (
    SELECT 
        period,
        CASE 
            WHEN total_qty = 0 THEN 0 
            ELSE ROUND((total_amount / total_qty)::numeric, 2) 
        END AS avg_buying_price
    FROM grouped_data
),
ranked_periods AS (
    SELECT 
        period,
        avg_buying_price,
        ROW_NUMBER() OVER (ORDER BY period DESC) AS period_rank
    FROM avg_price_data
),
labeled_data AS (
    SELECT 
        TO_CHAR(period, 
            CASE 
                WHEN (SELECT period_type FROM params) = 'year' THEN 'YYYY'
                WHEN (SELECT period_type FROM params) = 'month' THEN 'Mon YYYY'
                WHEN (SELECT period_type FROM params) = 'week' THEN '"Week "IW, YYYY'
                ELSE 'DD Mon YYYY'
            END) AS period_label,
        avg_buying_price,
        period_rank
    FROM ranked_periods
    WHERE period_rank <= 6
),
summary AS (
    SELECT 
        MAX(CASE WHEN period_rank = 1 THEN avg_buying_price END) AS current_avg_price,
        MAX(CASE WHEN period_rank = 2 THEN avg_buying_price END) AS previous_avg_price
    FROM labeled_data
)
SELECT 
    (SELECT json_agg(ld ORDER BY ld.period_rank DESC) FROM labeled_data ld) AS trend,
    (SELECT current_avg_price FROM summary) AS current_value,
    (SELECT 
        ROUND(
            CASE 
                WHEN previous_avg_price = 0 THEN 100
                ELSE ((current_avg_price - previous_avg_price) / previous_avg_price::numeric) * 100
            END::numeric, 2
        ) 
     FROM summary) AS percentage_change;






