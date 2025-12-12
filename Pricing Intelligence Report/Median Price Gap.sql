-----Median Price Gap: Difference between listed and market median.
-- ==== Filter Parameters ====
WITH params AS (
    SELECT 
        130::bigint  AS vendor_id,
        'Gears'::text AS cat_name
),
master_table AS (
    SELECT 
        vp.org_id AS vendor_id,
        vp.category_ids #>> '{cat_0,-1,name}' AS cat_name,
        (random() * 999 + 1)::int AS product_price
    FROM public.vendor_products vp
    CROSS JOIN params p
    WHERE vp.org_id = p.vendor_id
      AND (vp.category_ids #>> '{cat_0,-1,name}') = p.cat_name
),
median_table AS (
    SELECT 
        vendor_id,
        cat_name,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY product_price) AS median_price
    FROM master_table
    GROUP BY vendor_id, cat_name
),

price_diff AS (
    SELECT 
        m.vendor_id,
        m.cat_name,
        (m.product_price - md.median_price) AS price_difference
    FROM master_table m
    JOIN median_table md
          ON m.vendor_id = md.vendor_id
         AND m.cat_name = md.cat_name
)

SELECT 
    vendor_id,
    cat_name,
    AVG(price_difference) AS avg_price_difference
FROM price_diff
GROUP BY vendor_id, cat_name
ORDER BY vendor_id, cat_name;


