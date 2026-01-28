-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Card 1 Top Items
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Overall: Top 10 Products
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- SELECT 
--     vp.product_name,
--     SUM(pi.total_amount) AS total_purchase_volume
-- FROM po_items pi
-- JOIN vendor_products vp ON pi.product_id = vp.id
-- WHERE DATE_TRUNC('month', pi.updated_date) = DATE_TRUNC('month', CURRENT_DATE)
-- GROUP BY vp.product_name
-- ORDER BY total_purchase_volume DESC
-- LIMIT 10;

-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Graph 1: Purchasing Volume
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

WITH top_products AS (
    SELECT 
        product_id,
        SUM(total_amount) AS total_spend
    FROM po_items
    WHERE DATE_TRUNC('month', updated_date) = DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY product_id
    ORDER BY total_spend DESC
    LIMIT 10
),
params AS (
    SELECT 
        DATE '2025-01-23' AS start_date,
        DATE '2025-06-23' AS end_date,
        CASE 
            WHEN AGE(DATE '2025-06-23', DATE '2025-01-23') > INTERVAL '6 years' THEN 'year'
            WHEN AGE(DATE '2025-06-23', DATE '2025-01-23') > INTERVAL '6 months' THEN 'month'
            WHEN AGE(DATE '2025-06-23', DATE '2025-01-23') > INTERVAL '6 weeks' THEN 'week'
            ELSE 'day'
        END AS period_type
),
filtered_data AS (
    SELECT 
        p.product_id,
        p.updated_date,
        p.total_amount
    FROM po_items p
    JOIN top_products tp ON p.product_id = tp.product_id
    WHERE p.updated_date BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
),
period_data AS (
    SELECT 
        product_id,
        DATE_TRUNC((SELECT period_type FROM params), updated_date) AS period,
        SUM(total_amount) AS total_volume
    FROM filtered_data
    GROUP BY product_id, period
),
ranked_periods AS (
    SELECT 
        product_id,
        period,
        total_volume,
        ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY period DESC) AS period_rank
    FROM period_data
),
labeled_data AS (
    SELECT 
        product_id,
        TO_CHAR(period, 
            CASE 
                WHEN (SELECT period_type FROM params) = 'year' THEN 'YYYY'
                WHEN (SELECT period_type FROM params) = 'month' THEN 'Mon YYYY'
                WHEN (SELECT period_type FROM params) = 'week' THEN '"Week "IW, YYYY'
                ELSE 'DD Mon YYYY'
            END) AS period_label,
        total_volume,
        period_rank
    FROM ranked_periods
    WHERE period_rank <= 12
),
summary AS (
    SELECT 
        product_id,
        MAX(CASE WHEN period_rank = 1 THEN total_volume END) AS current_value,
        MAX(CASE WHEN period_rank = 2 THEN total_volume END) AS previous_value
    FROM ranked_periods
    GROUP BY product_id
)
SELECT 
    json_agg(
        json_build_object(
            'product_id', ld.product_id,
            'trend', (
                SELECT json_agg(json_build_object(
                    'period_label', l2.period_label,
                    'total_volume', l2.total_volume
                ) ORDER BY l2.period_rank DESC)
                FROM labeled_data l2
                WHERE l2.product_id = ld.product_id
            ),
            'current_value', s.current_value,
            'percentage_change', 
                CASE 
                    WHEN s.previous_value = 0 THEN 100
                    -- ELSE ROUND(((s.current_value - s.previous_value) / s.previous_value::numeric) * 100, 2)
					ELSE ROUND((((s.current_value - s.previous_value) / s.previous_value::numeric) * 100)::numeric, 2)
                END
        )
    ) AS purchasing_volume_per_product
FROM summary s
JOIN labeled_data ld ON s.product_id = ld.product_id
GROUP BY ld.product_id, s.current_value, s.previous_value;

