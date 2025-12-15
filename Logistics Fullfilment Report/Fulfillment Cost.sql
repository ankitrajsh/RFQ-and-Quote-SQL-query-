

-----Fulfillment Cost: Avg. ₹ spent per order. 

WITH params AS (
    SELECT
        509::bigint AS seller_org_id
),

base AS (
    SELECT
        a.id,
        a.seller_org_id,
        a.fulfillment_cost
    FROM po_asn a
    JOIN params p
      ON a.seller_org_id = p.seller_org_id
    WHERE a.fulfillment_cost IS NOT NULL
)

SELECT
    seller_org_id,

    COUNT(*) AS total_orders,

    ROUND(
        SUM(fulfillment_cost),
        2
    ) AS total_fulfillment_cost,

    ROUND(
        AVG(fulfillment_cost),
        2
    ) AS avg_fulfillment_cost_per_order

FROM base
GROUP BY seller_org_id;
