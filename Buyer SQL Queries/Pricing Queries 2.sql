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

-- WITH top_products AS (
--     SELECT 
--         product_id,
--         SUM(total_amount) AS total_spend
--     FROM po_items
--     WHERE DATE_TRUNC('month', updated_date) = DATE_TRUNC('month', CURRENT_DATE)
--     GROUP BY product_id
--     ORDER BY total_spend DESC
--     LIMIT 10
-- ),
-- params AS (
--     SELECT 
--         DATE '2025-01-23' AS start_date,
--         DATE '2025-06-23' AS end_date,
--         CASE 
--             WHEN AGE(DATE '2025-06-23', DATE '2025-01-23') > INTERVAL '6 years' THEN 'year'
--             WHEN AGE(DATE '2025-06-23', DATE '2025-01-23') > INTERVAL '6 months' THEN 'month'
--             WHEN AGE(DATE '2025-06-23', DATE '2025-01-23') > INTERVAL '6 weeks' THEN 'week'
--             ELSE 'day'
--         END AS period_type
-- ),
-- filtered_data AS (
--     SELECT 
--         p.product_id,
--         p.updated_date,
--         p.total_amount
--     FROM po_items p
--     JOIN top_products tp ON p.product_id = tp.product_id
--     WHERE p.updated_date BETWEEN (SELECT start_date FROM params) AND (SELECT end_date FROM params)
-- ),
-- period_data AS (
--     SELECT 
--         product_id,
--         DATE_TRUNC((SELECT period_type FROM params), updated_date) AS period,
--         SUM(total_amount) AS total_volume
--     FROM filtered_data
--     GROUP BY product_id, period
-- ),
-- ranked_periods AS (
--     SELECT 
--         product_id,
--         period,
--         total_volume,
--         ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY period DESC) AS period_rank
--     FROM period_data
-- ),
-- labeled_data AS (
--     SELECT 
--         product_id,
--         TO_CHAR(period, 
--             CASE 
--                 WHEN (SELECT period_type FROM params) = 'year' THEN 'YYYY'
--                 WHEN (SELECT period_type FROM params) = 'month' THEN 'Mon YYYY'
--                 WHEN (SELECT period_type FROM params) = 'week' THEN '"Week "IW, YYYY'
--                 ELSE 'DD Mon YYYY'
--             END) AS period_label,
--         total_volume,
--         period_rank
--     FROM ranked_periods
--     WHERE period_rank <= 12
-- ),
-- summary AS (
--     SELECT 
--         product_id,
--         MAX(CASE WHEN period_rank = 1 THEN total_volume END) AS current_value,
--         MAX(CASE WHEN period_rank = 2 THEN total_volume END) AS previous_value
--     FROM ranked_periods
--     GROUP BY product_id
-- )
-- SELECT 
--     json_agg(
--         json_build_object(
--             'product_id', ld.product_id,
--             'trend', (
--                 SELECT json_agg(json_build_object(
--                     'period_label', l2.period_label,
--                     'total_volume', l2.total_volume
--                 ) ORDER BY l2.period_rank DESC)
--                 FROM labeled_data l2
--                 WHERE l2.product_id = ld.product_id
--             ),
--             'current_value', s.current_value,
--             'percentage_change', 
--                 CASE 
--                     WHEN s.previous_value = 0 THEN 100
--                     -- ELSE ROUND(((s.current_value - s.previous_value) / s.previous_value::numeric) * 100, 2)
-- 					ELSE ROUND((((s.current_value - s.previous_value) / s.previous_value::numeric) * 100)::numeric, 2)
--                 END
--         )
--     ) AS purchasing_volume_per_product
-- FROM summary s
-- JOIN labeled_data ld ON s.product_id = ld.product_id
-- GROUP BY ld.product_id, s.current_value, s.previous_value;

-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Card 2: Overview
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-- WITH monthly_data AS (
--     SELECT
--         DATE_TRUNC('month', updated_date) AS month,
--         product_id,
--         SUM(qty) AS total_qty,
--         SUM(total_amount) AS total_spend
--     FROM po_items
--     WHERE updated_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month'
--     GROUP BY 1, 2
-- ),
-- aggregated AS (
--     SELECT
--         month,
--         SUM(total_qty) AS qty,
--         SUM(total_spend) AS spend
--     FROM monthly_data
--     GROUP BY month
-- ),
-- pivoted AS (
--     SELECT
--         MAX(CASE WHEN month = DATE_TRUNC('month', CURRENT_DATE) THEN spend END) AS total_current,
--         MAX(CASE WHEN month = DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month' THEN spend END) AS total_previous,
--         MAX(CASE WHEN month = DATE_TRUNC('month', CURRENT_DATE) THEN qty END) AS qty_current,
--         MAX(CASE WHEN month = DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month' THEN qty END) AS qty_previous
--     FROM aggregated
-- )
-- SELECT
--     ROUND(total_current::numeric, 2) AS total_purchase_volume_current_month,
--     ROUND(total_previous::numeric, 2) AS total_purchase_volume_previous_month,

--     -- Price Impact
--     ROUND(
--         (
--             (total_current::numeric / NULLIF(qty_current, 0)) -
--             (total_previous::numeric / NULLIF(qty_previous, 0))
--         )::numeric,
--         2
--     ) AS price_impact_value,
--     ROUND(
--         (
--             (
--                 (total_current::numeric / NULLIF(qty_current, 0)) -
--                 (total_previous::numeric / NULLIF(qty_previous, 0))
--             ) /
--             NULLIF((total_previous::numeric / NULLIF(qty_previous, 0)), 0)
--         )::numeric * 100,
--         2
--     ) AS price_impact_percentage,

--     -- Volume Impact
--     ROUND(
--         (
--             (qty_current - qty_previous)::numeric *
--             (total_previous::numeric / NULLIF(qty_previous, 0))
--         )::numeric,
--         2
--     ) AS volume_impact_value,
--     ROUND(
--         (
--             (
--                 (qty_current - qty_previous)::numeric *
--                 (total_previous::numeric / NULLIF(qty_previous, 0))
--             ) /
--             NULLIF(total_previous::numeric, 0)
--         )::numeric * 100,
--         2
--     ) AS volume_impact_percentage,

--     -- Mix Impact
--     ROUND(
--         (
--             total_current::numeric - total_previous::numeric
--             - ((total_current::numeric / NULLIF(qty_current, 0)) -
--                (total_previous::numeric / NULLIF(qty_previous, 0))) * qty_current
--             - ((qty_current - qty_previous)::numeric *
--                (total_previous::numeric / NULLIF(qty_previous, 0)))
--         )::numeric,
--         2
--     ) AS mix_impact_value,
--     ROUND(
--         (
--             (
--                 total_current::numeric - total_previous::numeric
--                 - ((total_current::numeric / NULLIF(qty_current, 0)) -
--                    (total_previous::numeric / NULLIF(qty_previous, 0))) * qty_current
--                 - ((qty_current - qty_previous)::numeric *
--                    (total_previous::numeric / NULLIF(qty_previous, 0)))
--             ) / NULLIF(total_previous::numeric, 0)
--         )::numeric * 100,
--         2
--     ) AS mix_impact_percentage
-- FROM pivoted;

-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Card 3: Top 5 Product By Purchasing Volume
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-- WITH monthly_data AS (
--     SELECT
--         product_id,
--         DATE_TRUNC('month', updated_date) AS month,
--         SUM(qty) AS total_qty,
--         SUM(total_amount) AS total_spend
--     FROM po_items
--     WHERE updated_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '2 months'
--     GROUP BY 1, 2
-- ),
-- aggregated AS (
--     SELECT
--         product_id,
--         MAX(CASE WHEN month = DATE_TRUNC('month', CURRENT_DATE) THEN total_spend END) AS total_current,
--         MAX(CASE WHEN month = DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month' THEN total_spend END) AS total_previous,
--         MAX(CASE WHEN month = DATE_TRUNC('month', CURRENT_DATE) THEN total_qty END) AS qty_current,
--         MAX(CASE WHEN month = DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month' THEN total_qty END) AS qty_previous
--     FROM monthly_data
--     GROUP BY product_id
-- ),
-- ranked_products AS (
--     SELECT *
--     FROM aggregated
--     ORDER BY COALESCE(total_current, 0) DESC
--     LIMIT 5
-- )
-- SELECT
--     product_id,
--     ROUND(COALESCE(total_current, 0)::numeric, 2) AS total_purchase_volume_current_month,
--     ROUND(COALESCE(total_previous, 0)::numeric, 2) AS total_purchase_volume_previous_month,

--     -- Price Impact
--     ROUND(
--         (
--             (COALESCE(total_current, 0)::numeric / NULLIF(COALESCE(qty_current, 0), 0)) -
--             (COALESCE(total_previous, 0)::numeric / NULLIF(COALESCE(qty_previous, 0), 0))
--         )::numeric,
--         2
--     ) AS price_impact_value,
--     ROUND(
--         (
--             (
--                 (COALESCE(total_current, 0)::numeric / NULLIF(COALESCE(qty_current, 0), 0)) -
--                 (COALESCE(total_previous, 0)::numeric / NULLIF(COALESCE(qty_previous, 0), 0))
--             ) /
--             NULLIF((COALESCE(total_previous, 0)::numeric / NULLIF(COALESCE(qty_previous, 0), 0)), 0)
--         )::numeric * 100,
--         2
--     ) AS price_impact_percentage,

--     -- Volume Impact
--     ROUND(
--         (
--             (COALESCE(qty_current, 0) - COALESCE(qty_previous, 0))::numeric *
--             (COALESCE(total_previous, 0)::numeric / NULLIF(COALESCE(qty_previous, 0), 0))
--         )::numeric,
--         2
--     ) AS volume_impact_value,
--     ROUND(
--         (
--             (
--                 (COALESCE(qty_current, 0) - COALESCE(qty_previous, 0))::numeric *
--                 (COALESCE(total_previous, 0)::numeric / NULLIF(COALESCE(qty_previous, 0), 0))
--             ) /
--             NULLIF(COALESCE(total_previous, 0)::numeric, 0)
--         )::numeric * 100,
--         2
--     ) AS volume_impact_percentage,

--     -- Mix Impact
--     ROUND(
--         (
--             COALESCE(total_current, 0)::numeric - COALESCE(total_previous, 0)::numeric
--             - ((COALESCE(total_current, 0)::numeric / NULLIF(COALESCE(qty_current, 0), 0)) -
--                (COALESCE(total_previous, 0)::numeric / NULLIF(COALESCE(qty_previous, 0), 0))) * COALESCE(qty_current, 0)
--             - ((COALESCE(qty_current, 0) - COALESCE(qty_previous, 0))::numeric *
--                (COALESCE(total_previous, 0)::numeric / NULLIF(COALESCE(qty_previous, 0), 0)))
--         )::numeric,
--         2
--     ) AS mix_impact_value,
--     ROUND(
--         (
--             (
--                 COALESCE(total_current, 0)::numeric - COALESCE(total_previous, 0)::numeric
--                 - ((COALESCE(total_current, 0)::numeric / NULLIF(COALESCE(qty_current, 0), 0)) -
--                    (COALESCE(total_previous, 0)::numeric / NULLIF(COALESCE(qty_previous, 0), 0))) * COALESCE(qty_current, 0)
--                 - ((COALESCE(qty_current, 0) - COALESCE(qty_previous, 0))::numeric *
--                    (COALESCE(total_previous, 0)::numeric / NULLIF(COALESCE(qty_previous, 0), 0)))
--             ) / NULLIF(COALESCE(total_previous, 0)::numeric, 0)
--         )::numeric * 100,
--         2
--     ) AS mix_impact_percentage
-- FROM ranked_products;

-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Card 4: AVERAGE BUYING PRICE Growth VS TOTAL PURCHASING QUANTITY Growth
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-- WITH product_data AS (
--     SELECT
--         product_id,
--         DATE_TRUNC('month', updated_date) AS month,
--         SUM(qty) AS total_qty,
--         SUM(total_amount) AS total_amount
--     FROM po_items
--     WHERE updated_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '2 months'
--       AND updated_date < DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month'
--     GROUP BY product_id, DATE_TRUNC('month', updated_date)
-- ),
-- pivoted_data AS (
--     SELECT
--         pd_current.product_id,
--         pd_current.total_qty AS current_qty,
--         pd_current.total_amount AS current_total,
--         pd_previous.total_qty AS previous_qty,
--         pd_previous.total_amount AS previous_total
--     FROM product_data pd_current
--     LEFT JOIN product_data pd_previous
--         ON pd_current.product_id = pd_previous.product_id
--         AND pd_previous.month = DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month'
--     WHERE pd_current.month = DATE_TRUNC('month', CURRENT_DATE)
-- ),
-- calculated_changes AS (
--     SELECT
--         product_id,
--         CASE 
--             WHEN previous_total IS NULL OR previous_qty = 0 THEN NULL
--             ELSE ROUND(
--                 (
--                     (current_total::numeric / NULLIF(current_qty::numeric, 0)) - 
--                     (previous_total::numeric / NULLIF(previous_qty::numeric, 0))
--                 ) / NULLIF((previous_total::numeric / NULLIF(previous_qty::numeric, 0)), 0) * 100,
--                 2
--             )
--         END AS avg_buying_price_change_pct,

--         CASE 
--             WHEN previous_qty IS NULL OR previous_qty = 0 THEN NULL
--             ELSE ROUND(
--                 ((current_qty::numeric - previous_qty::numeric) / NULLIF(previous_qty::numeric, 0)) * 100,
--                 2
--             )
--         END AS qty_change_pct
--     FROM pivoted_data
-- ),
-- with_labels AS (
--     SELECT
--         product_id,
--         avg_buying_price_change_pct,
--         qty_change_pct,
--         CASE
--             WHEN avg_buying_price_change_pct > 0 AND qty_change_pct < 0 THEN 'Red'
--             WHEN avg_buying_price_change_pct < 0 AND qty_change_pct > 0 THEN 'Green'
--             ELSE 'Yellow'
--         END AS color_label
--     FROM calculated_changes
-- )
-- SELECT * FROM with_labels
-- ORDER BY product_id;


-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- Card 5: Product for which the Average Buying Price increased whereas the Total Purchase Quantity is higher than previous period
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


WITH purchase_data AS (
    SELECT
        product_id,
        DATE_TRUNC('month', updated_date) AS month,
        SUM(total_amount) AS total_spend,
        SUM(qty) AS total_qty
    FROM po_items
    WHERE updated_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month'
      AND updated_date < DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month'
    GROUP BY product_id, DATE_TRUNC('month', updated_date)
),
pivoted AS (
    SELECT
        current.product_id,
        vp.product_name,

        -- Average Buying Price
        ROUND((current.total_spend / NULLIF(current.total_qty, 0))::numeric, 2) AS avg_buying_price_current,
        ROUND((prev.total_spend / NULLIF(prev.total_qty, 0))::numeric, 2) AS avg_buying_price_previous,

        -- Delta % in Buying Price
        CASE 
            WHEN prev.total_qty = 0 OR prev.total_qty IS NULL THEN NULL
            ELSE ROUND(
                (
                    100.0 * (
                        (current.total_spend / NULLIF(current.total_qty, 0)) -
                        (prev.total_spend / NULLIF(prev.total_qty, 0))
                    ) / (prev.total_spend / NULLIF(prev.total_qty, 0))
                )::numeric, 2)
        END AS avg_price_change_pct,

        -- Purchase Quantity
        current.total_qty AS total_qty_current,
        prev.total_qty AS total_qty_previous,

        -- Delta % in Quantity
        CASE
            WHEN prev.total_qty = 0 OR prev.total_qty IS NULL THEN NULL
            ELSE ROUND(
                (100.0 * (current.total_qty - prev.total_qty) / prev.total_qty)::numeric, 2)
        END AS qty_change_pct

    FROM purchase_data current
    LEFT JOIN purchase_data prev
        ON current.product_id = prev.product_id
        AND current.month = DATE_TRUNC('month', CURRENT_DATE)
        AND prev.month = DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month'
    LEFT JOIN vendor_products vp
        ON current.product_id = vp.product_id
    WHERE
        (current.total_spend / NULLIF(current.total_qty, 0)) >
        (prev.total_spend / NULLIF(prev.total_qty, 0))
        AND current.total_qty > COALESCE(prev.total_qty, 0)
)

SELECT 
    product_id,
    product_name,
    avg_buying_price_current,
    avg_price_change_pct,
    total_qty_current,
    qty_change_pct
FROM pivoted
ORDER BY avg_price_change_pct DESC NULLS LAST;



-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
--Card 6: Product for which the Average Buying Price increased (considering the Total Purchase Quantity is lower than previous period)
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

WITH purchase_data AS (
    SELECT
        product_id,
        DATE_TRUNC('month', updated_date) AS month,
        SUM(total_amount) AS total_spend,
        SUM(qty) AS total_qty
    FROM po_items
    WHERE updated_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month'
      AND updated_date < DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month'
    GROUP BY product_id, DATE_TRUNC('month', updated_date)
),
pivoted AS (
    SELECT
        current.product_id,
        vp.product_name,

        -- Average Buying Price
        ROUND((current.total_spend / NULLIF(current.total_qty, 0))::numeric, 2) AS avg_buying_price_current,
        ROUND((prev.total_spend / NULLIF(prev.total_qty, 0))::numeric, 2) AS avg_buying_price_previous,

        -- Delta % in Buying Price
        CASE 
            WHEN prev.total_qty = 0 OR prev.total_qty IS NULL THEN NULL
            ELSE ROUND((
                100.0 * (
                    (current.total_spend / NULLIF(current.total_qty, 0)) -
                    (prev.total_spend / NULLIF(prev.total_qty, 0))
                ) / (prev.total_spend / NULLIF(prev.total_qty, 0))
            )::numeric, 2)
        END AS avg_price_change_pct,

        -- Purchase Quantity
        current.total_qty AS total_qty_current,
        prev.total_qty AS total_qty_previous,

        -- Delta % in Quantity
        CASE
            WHEN prev.total_qty = 0 OR prev.total_qty IS NULL THEN NULL
            ELSE ROUND((
                100.0 * (current.total_qty - prev.total_qty) / prev.total_qty
            )::numeric, 2)
        END AS qty_change_pct

    FROM purchase_data current
    LEFT JOIN purchase_data prev
        ON current.product_id = prev.product_id
        AND prev.month = DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month'
    LEFT JOIN vendor_products vp
        ON current.product_id = vp.product_id
    WHERE current.month = DATE_TRUNC('month', CURRENT_DATE)
)

SELECT 
    product_id,
    product_name,
    avg_buying_price_current,
    avg_price_change_pct,
    total_qty_current,
    qty_change_pct
FROM pivoted
WHERE 
    avg_buying_price_current > avg_buying_price_previous -- 🔺 price increased
    AND total_qty_current < total_qty_previous           -- 🔻 quantity decreased
ORDER BY avg_price_change_pct DESC NULLS LAST;
























