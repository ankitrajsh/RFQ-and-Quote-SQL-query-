------Delivery Time vs. SLA: Avg. actual vs. promised delivery. 
WITH params AS (
    SELECT
        509::bigint AS seller_org_id
),

base AS (
    SELECT
        a.*
    FROM po_asn a
    JOIN params p
      ON a.seller_org_id = p.seller_org_id
)

SELECT
    seller_org_id,

    -- Avg actual delivery time (days)
    ROUND(
        AVG(EXTRACT(EPOCH FROM ("Actual_delivery_date" - created_date))) / 86400,
        0
    ) AS avg_actual_days,

    -- Promised delivery (SLA in days)
    ROUND(
        AVG(expected_delivery_date - created_date::date),
        0
    ) AS promised_delivery_days

FROM base
GROUP BY seller_org_id;