-- Overall: Product Categories
---------------------------------------------------------------------------
-- WITH params AS (
--     SELECT 
--         DATE '2024-12-01' AS start_date,
--         DATE '2024-12-31' AS end_date
-- ),
-- category_spend AS (
--     SELECT 
--         jsonb_extract_path_text(category_elem.value, 'name') AS category_name,
--         SUM(pi.total_amount) AS total_spend
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.id
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
-- LIMIT 10

----------------------------------------------------------
-- Graph 1: Purchasing Volume
----------------------------------------------------------
-- WITH params AS (
--     SELECT 
--         DATE '2024-12-01' AS start_date,
--         DATE '2024-12-31' AS end_date,
--         DATE '2024-11-01' AS prev_start_date,
--         DATE '2024-11-30' AS prev_end_date
-- ),
-- current_period AS (
--     SELECT 
--         jsonb_extract_path_text(cat.value, 'name') AS category_name,
--         SUM(pi.total_amount) AS total_spend
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.id
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
--     JOIN vendor_products vp ON pi.product_id = vp.id
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
--         ROUND(
--             (
--                 CASE 
--                     WHEN prev.total_spend = 0 THEN 100
--                     ELSE ((curr.total_spend - prev.total_spend) / prev.total_spend) * 100
--                 END
--             )::numeric, 2
--         ) AS percent_change
--     FROM current_period curr
--     LEFT JOIN previous_period prev ON curr.category_name = prev.category_name
-- )
-- SELECT *
-- FROM combined
-- ORDER BY current_volume DESC
-- LIMIT 10;

----------------------------------------------------------
-- Graph 2: Suppliers
----------------------------------------------------------
-- WITH category_suppliers AS (
--     SELECT
--         jsonb_extract_path_text(category_elem, 'name') AS category_name,
--         vp.org_id AS supplier_id,
--         pi.updated_date
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.product_id,
--     LATERAL jsonb_array_elements(vp.category_ids -> 'cat_0') AS category_elem
--     WHERE (category_elem ->> 'level')::int = 3
-- ),
-- time_filtered AS (
--     SELECT *,
--         CASE
--             WHEN updated_date BETWEEN :start_date AND :end_date THEN 'current'
--             WHEN updated_date BETWEEN (:start_date - (:end_date - :start_date)) AND :start_date THEN 'previous'
--         END AS period
--     FROM category_suppliers
--     WHERE updated_date BETWEEN (:start_date - (:end_date - :start_date)) AND :end_date
-- ),
-- supplier_counts AS (
--     SELECT
--         category_name,
--         period,
--         COUNT(DISTINCT supplier_id) AS supplier_count
--     FROM time_filtered
--     GROUP BY category_name, period
-- ),
-- pivoted AS (
--     SELECT
--         category_name,
--         MAX(CASE WHEN period = 'current' THEN supplier_count END) AS current_supplier_count,
--         MAX(CASE WHEN period = 'previous' THEN supplier_count END) AS previous_supplier_count
--     FROM supplier_counts
--     GROUP BY category_name
-- )
-- SELECT
--     category_name,
--     COALESCE(current_supplier_count, 0) AS current_supplier_count,
--     COALESCE(previous_supplier_count, 0) AS previous_supplier_count,
--     CASE 
--         WHEN previous_supplier_count IS NULL OR previous_supplier_count = 0 THEN NULL
--         ELSE ROUND(100.0 * (current_supplier_count - previous_supplier_count) / previous_supplier_count, 2)
--     END AS percent_change
-- FROM pivoted
-- ORDER BY current_supplier_count DESC;

-- ++++++++++++++++ Working Query ++++++++++++++++++++++++++++++++++++
-- WITH category_suppliers AS (
--     SELECT
--         jsonb_extract_path_text(category_elem, 'name') AS category_name,
--         vp.org_id AS supplier_id,
--         pi.updated_date
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.id,
--     LATERAL jsonb_array_elements(vp.category_ids -> 'cat_0') AS category_elem
--     WHERE (category_elem ->> 'level')::int = 3
-- ),
-- time_filtered AS (
--     SELECT *,
--         CASE
--             WHEN updated_date BETWEEN DATE '2024-12-01' AND DATE '2024-12-31' THEN 'current'
--             WHEN updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-28' - DATE '2025-07-01')) AND DATE '2025-07-01' THEN 'previous'
--         END AS period
--     FROM category_suppliers
--     WHERE updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-31' - DATE '2024-12-01')) AND DATE '2024-12-31'
-- ),
-- supplier_counts AS (
--     SELECT
--         category_name,
--         period,
--         COUNT(DISTINCT supplier_id) AS supplier_count
--     FROM time_filtered
--     GROUP BY category_name, period
-- ),
-- pivoted AS (
--     SELECT
--         category_name,
--         MAX(CASE WHEN period = 'current' THEN supplier_count END) AS current_supplier_count,
--         MAX(CASE WHEN period = 'previous' THEN supplier_count END) AS previous_supplier_count
--     FROM supplier_counts
--     GROUP BY category_name
-- )
-- SELECT
--     category_name,
--     COALESCE(current_supplier_count, 0) AS current_supplier_count,
--     COALESCE(previous_supplier_count, 0) AS previous_supplier_count,
--     CASE 
--         WHEN previous_supplier_count IS NULL OR previous_supplier_count = 0 THEN NULL
--         ELSE ROUND(100.0 * (current_supplier_count - previous_supplier_count) / previous_supplier_count, 2)
--     END AS percent_change
-- FROM pivoted
-- ORDER BY current_supplier_count DESC;

----------------------------------------------------------
-- Graph 3: Volume Per Supplier
----------------------------------------------------------
-- Using start_date: '2024-12-01'
-- Using end_date:   '2024-12-31'

-- WITH category_data AS (
--     SELECT
--         jsonb_extract_path_text(category_elem, 'name') AS category_name,
--         vp.org_id AS supplier_id,
--         pi.updated_date,
--         pi.total_amount
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.id,
--     LATERAL jsonb_array_elements(vp.category_ids -> 'cat_0') AS category_elem
--     WHERE (category_elem ->> 'level')::int = 3
-- ),
-- time_filtered AS (
--     SELECT *,
--         CASE
--             WHEN updated_date BETWEEN DATE '2024-12-01' AND DATE '2024-12-31' THEN 'current'
--             WHEN updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-31' - DATE '2024-12-01')) AND DATE '2024-12-01' THEN 'previous'
--         END AS period
--     FROM category_data
--     WHERE updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-31' - DATE '2024-12-01')) AND DATE '2024-12-31'
-- ),
-- aggregated AS (
--     SELECT
--         category_name,
--         period,
--         COUNT(DISTINCT supplier_id) AS supplier_count,
--         SUM(total_amount) AS total_volume
--     FROM time_filtered
--     GROUP BY category_name, period
-- ),
-- pivoted AS (
--     SELECT
--         category_name,
--         MAX(CASE WHEN period = 'current' THEN total_volume / NULLIF(supplier_count, 0) END) AS current_volume_per_supplier,
--         MAX(CASE WHEN period = 'previous' THEN total_volume / NULLIF(supplier_count, 0) END) AS previous_volume_per_supplier
--     FROM aggregated
--     GROUP BY category_name
-- )
-- SELECT
--     category_name,
--     ROUND(CAST(COALESCE(current_volume_per_supplier, 0) AS numeric), 2) AS current_volume_per_supplier,
--     ROUND(CAST(COALESCE(previous_volume_per_supplier, 0) AS numeric), 2) AS previous_volume_per_supplier,
--     CASE
--         WHEN previous_volume_per_supplier IS NULL OR previous_volume_per_supplier = 0 THEN NULL
--         ELSE ROUND(
--             (100.0 * (current_volume_per_supplier - previous_volume_per_supplier) / previous_volume_per_supplier)::numeric,
--             2
--         )
--     END AS percent_change
-- FROM pivoted
-- ORDER BY current_volume_per_supplier DESC;

----------------------------------------------------------
-- Graph 4: Items Purchased
----------------------------------------------------------
-- Using start_date: '2024-12-01'
-- Using end_date:   '2024-12-31'

-- WITH category_data AS (
--     SELECT
--         jsonb_extract_path_text(category_elem, 'name') AS category_name,
--         pi.updated_date,
--         pi.qty
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.id,
--     LATERAL jsonb_array_elements(vp.category_ids -> 'cat_0') AS category_elem
--     WHERE (category_elem ->> 'level')::int = 3
-- ),
-- time_filtered AS (
--     SELECT *,
--         CASE
--             WHEN updated_date BETWEEN DATE '2024-12-01' AND DATE '2024-12-31' THEN 'current'
--             WHEN updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-31' - DATE '2024-12-01')) AND DATE '2024-12-01' THEN 'previous'
--         END AS period
--     FROM category_data
--     WHERE updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-31' - DATE '2024-12-01')) AND DATE '2024-12-31'
-- ),
-- aggregated AS (
--     SELECT
--         category_name,
--         period,
--         SUM(qty) AS total_items_purchased
--     FROM time_filtered
--     GROUP BY category_name, period
-- ),
-- pivoted AS (
--     SELECT
--         category_name,
--         MAX(CASE WHEN period = 'current' THEN total_items_purchased END) AS current_items,
--         MAX(CASE WHEN period = 'previous' THEN total_items_purchased END) AS previous_items
--     FROM aggregated
--     GROUP BY category_name
-- )
-- SELECT
--     category_name,
--     COALESCE(current_items, 0) AS current_items_purchased,
--     COALESCE(previous_items, 0) AS previous_items_purchased,
--     CASE
--         WHEN previous_items IS NULL OR previous_items = 0 THEN NULL
--         ELSE ROUND((100.0 * (current_items - previous_items) / previous_items)::numeric, 2)
--     END AS percent_change
-- FROM pivoted
-- ORDER BY current_items_purchased DESC;

----------------------------------------------------------
-- Graph 5: Total Purchase Quantity
----------------------------------------------------------
-- Using start_date: '2024-12-01'
-- Using end_date:   '2024-12-31'

-- WITH category_data AS (
--     SELECT
--         jsonb_extract_path_text(category_elem, 'name') AS category_name,
--         pi.updated_date,
--         pi.qty
--     FROM po_items pi
--     JOIN vendor_products vp ON pi.product_id = vp.id,
--     LATERAL jsonb_array_elements(vp.category_ids -> 'cat_0') AS category_elem
--     WHERE (category_elem ->> 'level')::int = 3
-- ),
-- time_filtered AS (
--     SELECT *,
--         CASE
--             WHEN updated_date BETWEEN DATE '2024-12-01' AND DATE '2024-12-31' THEN 'current'
--             WHEN updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-31' - DATE '2024-12-01')) AND DATE '2024-12-01' THEN 'previous'
--         END AS period
--     FROM category_data
--     WHERE updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-31' - DATE '2024-12-01')) AND DATE '2024-12-31'
-- ),
-- aggregated AS (
--     SELECT
--         category_name,
--         period,
--         SUM(qty) AS total_qty
--     FROM time_filtered
--     GROUP BY category_name, period
-- ),
-- pivoted AS (
--     SELECT
--         category_name,
--         MAX(CASE WHEN period = 'current' THEN total_qty END) AS current_qty,
--         MAX(CASE WHEN period = 'previous' THEN total_qty END) AS previous_qty
--     FROM aggregated
--     GROUP BY category_name
-- )
-- SELECT
--     category_name,
--     COALESCE(current_qty, 0) AS current_purchase_quantity,
--     COALESCE(previous_qty, 0) AS previous_purchase_quantity,
--     CASE
--         WHEN previous_qty IS NULL OR previous_qty = 0 THEN NULL
--         ELSE ROUND((100.0 * (current_qty - previous_qty) / previous_qty)::numeric, 2)
--     END AS percent_change
-- FROM pivoted
-- ORDER BY current_purchase_quantity DESC;

----------------------------------------------------------
-- Graph 6: Average Buying Price
----------------------------------------------------------

-- Using start_date: '2024-12-01'
-- Using end_date:   '2024-12-31'

WITH category_data AS (
    SELECT
        jsonb_extract_path_text(category_elem, 'name') AS category_name,
        pi.updated_date,
        pi.qty,
        pi.total_amount
    FROM po_items pi
    JOIN vendor_products vp ON pi.product_id = vp.id,
    LATERAL jsonb_array_elements(vp.category_ids -> 'cat_0') AS category_elem
    WHERE (category_elem ->> 'level')::int = 3
),
time_filtered AS (
    SELECT *,
        CASE
            WHEN updated_date BETWEEN DATE '2024-12-01' AND DATE '2024-12-31' THEN 'current'
            WHEN updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-31' - DATE '2024-12-01')) AND DATE '2024-12-01' THEN 'previous'
        END AS period
    FROM category_data
    WHERE updated_date BETWEEN (DATE '2024-12-01' - (DATE '2024-12-31' - DATE '2024-12-01')) AND DATE '2024-12-31'
),
aggregated AS (
    SELECT
        category_name,
        period,
        SUM(total_amount) AS total_spend,
        SUM(qty) AS total_qty
    FROM time_filtered
    GROUP BY category_name, period
),
pivoted AS (
    SELECT
        category_name,
        MAX(CASE WHEN period = 'current' THEN total_spend END) AS current_spend,
        MAX(CASE WHEN period = 'previous' THEN total_spend END) AS previous_spend,
        MAX(CASE WHEN period = 'current' THEN total_qty END) AS current_qty,
        MAX(CASE WHEN period = 'previous' THEN total_qty END) AS previous_qty
    FROM aggregated
    GROUP BY category_name
)
SELECT
    category_name,
    ROUND(
        CASE 
            WHEN current_qty > 0 THEN (current_spend / current_qty)::numeric
            ELSE NULL
        END, 2
    ) AS current_avg_price,
    ROUND(
        CASE 
            WHEN previous_qty > 0 THEN (previous_spend / previous_qty)::numeric
            ELSE NULL
        END, 2
    ) AS previous_avg_price,
    CASE
        WHEN previous_qty IS NULL OR previous_qty = 0 THEN NULL
        ELSE ROUND(
            (
                (
                    CASE WHEN current_qty > 0 THEN current_spend / current_qty ELSE 0 END
                    -
                    CASE WHEN previous_qty > 0 THEN previous_spend / previous_qty ELSE 0 END
                )
                /
                CASE WHEN previous_qty > 0 THEN previous_spend / previous_qty ELSE 1 END
            )::numeric * 100, 2
        )
    END AS percent_change
FROM pivoted
ORDER BY current_avg_price DESC;