-- SELECT DISTINCT
--     vp.product_id,
--     vp.product_name
-- FROM vendor_products vp
-- WHERE vp.product_id IS NOT NULL
-- ORDER BY vp.product_name;

------------------------------------------------------
-- Card 1: Product Details
------------------------------------------------------

-- WITH level_3_category AS (
--     SELECT 
--         vp.product_id,
--         vp.product_name,
--         vp.price,
--         jsonb_array_elements(vp.category_ids -> 'cat_0') AS cat
--     FROM vendor_products vp
--     WHERE vp.product_id = 73079
-- )
-- SELECT
--     l3.product_id,
--     l3.product_name,
--     l3.cat ->> 'name' AS purchasing_category,
--     MIN(l3.price::numeric) AS min_price,
--     ROUND(AVG(poi.total_amount::numeric / NULLIF(poi.qty, 0))::numeric, 2) AS avg_buying_price,
--     MAX(l3.price::numeric) AS max_price,
--     COUNT(DISTINCT vp.vendor_sku) AS distinct_vendors
-- FROM level_3_category l3
-- LEFT JOIN po_items poi ON poi.product_id = l3.product_id
-- LEFT JOIN vendor_products vp ON vp.product_id = l3.product_id
-- WHERE l3.price IS NOT NULL
--   AND l3.price <> ''
--   AND l3.price ~ '^[0-9.]+$'
--   AND l3.cat ->> 'level' = '3'
-- GROUP BY 
--     l3.product_id, 
--     l3.product_name, 
--     l3.cat ->> 'name';

------------------------------------------------------
-- Card 2: Vendors
-----------------------------------------------------

-- SELECT
--     vp.org_id AS vendor_id,
--     vp.product_name,
--     MIN(vp.price::numeric) AS min_price,
--     ROUND(AVG(vp.price::numeric), 2) AS avg_price,
--     MAX(vp.price::numeric) AS max_price,
--     SUM(poi.qty::numeric) AS total_purchase_quantity,
--     SUM(poi.total_amount::numeric) AS total_purchase_volume
-- FROM vendor_products vp
-- LEFT JOIN po_items poi
--     ON vp.product_id = poi.product_id
--     AND vp.org_id::text = poi.source_id
-- WHERE vp.product_id = 73079
-- GROUP BY vp.org_id, vp.product_name
-- ORDER BY total_purchase_volume DESC NULLS LAST;

------------------------------------------------------
-- Card 3: Product History
------------------------------------------------------

-- WITH months AS (
--     SELECT TO_CHAR(DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month' * n, 'YYYY-MM') AS month_year
--     FROM generate_series(0, 11) AS n
-- ),
-- product_history AS (
--     SELECT
--         TO_CHAR(DATE_TRUNC('month', poi.updated_date), 'YYYY-MM') AS month_year,
--         ROUND(AVG((poi.total_amount::numeric / NULLIF(poi.qty, 0))::numeric), 2) AS avg_buying_price,
--         MIN(poi.unit_price::numeric) AS min_price,
--         MAX(poi.unit_price::numeric) AS max_price,
--         SUM(poi.qty::numeric) AS total_qty
--     FROM po_items poi
--     WHERE poi.product_id = 73079
--       AND poi.updated_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '12 months'
--     GROUP BY DATE_TRUNC('month', poi.updated_date)
-- ),
-- vendor_avg_prices AS (
--     SELECT
--         TO_CHAR(DATE_TRUNC('month', poi.updated_date), 'YYYY-MM') AS month_year,
--         poi.source_id AS vendor_id,
--         ROUND(AVG((poi.total_amount::numeric / NULLIF(poi.qty, 0))::numeric), 2) AS avg_price_by_vendor
--     FROM po_items poi
--     WHERE poi.product_id = 73079
--       AND poi.updated_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '12 months'
--     GROUP BY month_year, poi.source_id
-- )
-- SELECT
--     m.month_year,
    
--     -- Graph 1: Product-wise price & quantity history
--     ph.avg_buying_price,
--     ph.min_price,
--     ph.max_price,
--     ph.total_qty,

--     -- Graph 2: Vendor-wise avg buying price as JSON array
--     (
--         SELECT JSON_AGG(json_build_object(
--             'vendor_id', vap.vendor_id,
--             'avg_price_by_vendor', vap.avg_price_by_vendor
--         ))
--         FROM vendor_avg_prices vap
--         WHERE vap.month_year = m.month_year
--     ) AS vendor_price_distribution

-- FROM months m
-- LEFT JOIN product_history ph ON ph.month_year = m.month_year
-- ORDER BY m.month_year;

------------------------------------------------------
-- Card 4: Purchasing Volume by Product
------------------------------------------------------

-- WITH product_spend AS (
--     SELECT
--         vp.product_id,
--         vp.product_name,
--         SUM(poi.total_amount::numeric) AS total_purchase_volume
--     FROM po_items poi
--     JOIN vendor_products vp ON vp.product_id = poi.product_id
--     WHERE poi.updated_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '12 months'
--     GROUP BY vp.product_id, vp.product_name
-- ),
-- total_spend AS (
--     SELECT SUM(total_purchase_volume) AS overall_purchase_volume
--     FROM product_spend
-- )
-- SELECT
--     ps.product_id,
--     ps.product_name,
--     ps.total_purchase_volume,
--     ROUND((ps.total_purchase_volume / NULLIF(ts.overall_purchase_volume, 0)) * 100, 2) AS contribution_percentage
-- FROM product_spend ps
-- CROSS JOIN total_spend ts
-- ORDER BY ps.total_purchase_volume DESC;

------------------------------------------------------
-- Card 5: Amount per Buyer by Purchasing Category
------------------------------------------------------

WITH category_summary AS (
    SELECT
        vp.category_ids,
        poi.source_id AS buyer_id,
        SUM(poi.total_amount::numeric) AS total_spend
    FROM po_items poi
    JOIN vendor_products vp ON vp.product_id = poi.product_id
    WHERE vp.category_ids IS NOT NULL
    GROUP BY vp.category_ids, poi.source_id
),
category_level3 AS (
    SELECT
        (
            jsonb_path_query(category_ids, '$.cat_0[*] ? (@.level == 3)')
        )->>'name' AS category_name,
        buyer_id,
        total_spend
    FROM category_summary
),
category_agg AS (
    SELECT
        category_name,
        COUNT(DISTINCT buyer_id) AS total_buyers,
        SUM(total_spend) AS total_spend,
        SUM(total_spend) / NULLIF(COUNT(DISTINCT buyer_id), 0) AS avg_amount_per_buyer
    FROM category_level3
    GROUP BY category_name
),
final_output AS (
    SELECT
        category_name,
        avg_amount_per_buyer,
        SUM(total_spend) OVER () AS grand_total,
        SUM(total_spend) OVER (ORDER BY avg_amount_per_buyer DESC) AS running_total
    FROM category_agg
)
SELECT
    category_name,
    ROUND(avg_amount_per_buyer, 2) AS avg_amount_per_buyer,
    ROUND(running_total * 100.0 / NULLIF(grand_total, 0), 2) AS cumulative_contribution_pct
FROM final_output
ORDER BY avg_amount_per_buyer DESC;





