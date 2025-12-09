-----Pricing Intelligence Report: Median Price Gap-----

WITH master_table AS (
    SELECT 
        product_id,
        org_id,
        category_ids #>> '{cat_0,-1,name}' AS cat_name,
        product_name,
        (random() * 999 + 1)::int AS product_price
    FROM public.vendor_products
),

-- Median by org + category
median_table AS (
    SELECT 
        org_id,
        cat_name,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY product_price) AS median_price
    FROM master_table
    GROUP BY org_id, cat_name
)

SELECT 
    m.product_id,
    m.org_id,
    m.cat_name,
    m.product_name,
    m.product_price,
    md.median_price,
    (m.product_price - md.median_price) AS price_difference,
    CASE 
        WHEN m.product_price > md.median_price THEN 'Above Median'
        WHEN m.product_price < md.median_price THEN 'Below Median'
        ELSE 'Equal to Median'
    END AS price_position
FROM master_table m
JOIN median_table md
    ON m.org_id = md.org_id
   AND m.cat_name = md.cat_name
ORDER BY m.org_id, m.cat_name, price_difference DESC;
