--------------------------------------------------------------
-- Card 1: Products Purchased per Number of Active Vendors
--------------------------------------------------------------

-- WITH product_vendor_stats AS (
--     SELECT
--         poi.product_id,
--         vp.product_name,
--         COUNT(DISTINCT poi.source_id) AS supplier_count,
--         SUM(poi.total_amount::numeric) AS total_purchase_volume
--     FROM po_items poi
--     JOIN vendor_products vp ON poi.product_id = vp.product_id
--     WHERE poi.total_amount IS NOT NULL
--     GROUP BY poi.product_id, vp.product_name
-- ),
-- bucketed_stats AS (
--     SELECT
--         *,
--         CASE
--             WHEN supplier_count = 1 THEN '1 supplier'
--             WHEN supplier_count = 2 THEN '2 suppliers'
--             WHEN supplier_count = 3 THEN '3 suppliers'
--             WHEN supplier_count BETWEEN 4 AND 5 THEN '4-5 suppliers'
--             ELSE '>5 suppliers'
--         END AS supplier_bucket
--     FROM product_vendor_stats
-- ),
-- bar_chart_data AS (
--     SELECT
--         supplier_bucket,
--         SUM(total_purchase_volume) AS total_volume_in_bucket
--     FROM bucketed_stats
--     GROUP BY supplier_bucket
-- )
-- SELECT
--     b.product_id,
--     b.product_name,
--     b.supplier_count,
--     b.supplier_bucket,
--     b.total_purchase_volume AS volume_per_product,        -- for scatter plot
--     bc.total_volume_in_bucket                             -- for stacked bar chart
-- FROM bucketed_stats b
-- JOIN bar_chart_data bc ON b.supplier_bucket = bc.supplier_bucket
-- ORDER BY b.supplier_count, b.total_purchase_volume DESC;

--------------------------------------------------------------
-- Card 2: Single Supplier Dependencies
--------------------------------------------------------------

-- WITH product_supplier_stats AS (
--     SELECT
--         poi.product_id,
--         vp.product_name,
--         poi.source_id::int AS supplier_id,
--         COUNT(DISTINCT poi.source_id) AS supplier_count,
--         SUM(poi.total_amount::numeric) AS total_volume,
--         MIN(poi.unit_price::numeric) AS min_price,
--         ROUND(AVG(poi.unit_price::numeric), 2) AS avg_price,
--         MAX(poi.unit_price::numeric) AS max_price
--     FROM po_items poi
--     JOIN vendor_products vp ON poi.product_id = vp.product_id
--     WHERE poi.unit_price IS NOT NULL
--     GROUP BY poi.product_id, vp.product_name, poi.source_id
-- ),
-- single_supplier_products AS (
--     SELECT *
--     FROM product_supplier_stats
--     WHERE supplier_count = 1
-- )
-- SELECT
--     product_id,
--     product_name,
--     supplier_id,
--     total_volume,
--     min_price,
--     avg_price,
--     max_price,
--     (max_price - min_price) AS delta_price,
--     ROUND(((max_price - min_price) / NULLIF(min_price, 0)) * 100, 2) AS delta_price_pct
-- FROM single_supplier_products
-- ORDER BY total_volume DESC;

--------------------------------------------------------------
-- Card 3: Savings Opportunities
--------------------------------------------------------------
WITH product_stats AS (
    SELECT
        vp.product_id,
        vp.product_name,
        COUNT(DISTINCT vp.org_id) AS vendor_count,
        MIN(CASE WHEN vp.price::text ~ '^\d+(\.\d+)?$' THEN vp.price::numeric ELSE NULL END) AS min_price_vendor,
        ROUND(AVG(CASE WHEN vp.price::text ~ '^\d+(\.\d+)?$' THEN vp.price::numeric ELSE NULL END), 2) AS avg_price_by_vendor
    FROM vendor_products vp
    WHERE vp.price::text ~ '^\d+(\.\d+)?$'
    GROUP BY vp.product_id, vp.product_name
),
purchase_stats AS (
    SELECT
        poi.product_id,
        SUM(poi.total_amount::numeric) AS total_volume,
        MIN(CASE WHEN poi.unit_price::text ~ '^\d+(\.\d+)?$' THEN poi.unit_price::numeric ELSE NULL END) AS min_purchase_price,
        ROUND(AVG(CASE WHEN poi.unit_price::text ~ '^\d+(\.\d+)?$' THEN poi.unit_price::numeric ELSE NULL END), 2) AS avg_purchase_price,
        MAX(CASE WHEN poi.unit_price::text ~ '^\d+(\.\d+)?$' THEN poi.unit_price::numeric ELSE NULL END) AS max_purchase_price
    FROM po_items poi
    WHERE poi.unit_price::text ~ '^\d+(\.\d+)?$'
    GROUP BY poi.product_id
)
SELECT
    ps.product_id,
    ps.product_name,
    pu.total_volume AS volume,
    ps.vendor_count AS vendors,
    ps.avg_price_by_vendor AS avg_price_by_vendor,
    ps.min_price_vendor AS min_price_vendor,
    pu.avg_purchase_price AS avg_price,
    pu.max_purchase_price AS max_price,
    (pu.max_purchase_price - ps.min_price_vendor) AS delta_price,
    ROUND(((pu.max_purchase_price - ps.min_price_vendor) / NULLIF(ps.min_price_vendor, 0)) * 100, 2) AS delta_price_pct
FROM product_stats ps
JOIN purchase_stats pu ON ps.product_id = pu.product_id
ORDER BY delta_price_pct DESC NULLS LAST;



