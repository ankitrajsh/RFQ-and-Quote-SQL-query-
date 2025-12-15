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
    WHERE a."Actual_delivery_date" IS NOT NULL
)

SELECT
    seller_org_id,

    ROUND(
        100.0 * AVG(
            CASE
                WHEN "Actual_delivery_date"::date <= expected_delivery_date
                THEN 1
                ELSE 0
            END
        ),
        2
    ) AS on_time_delivery_rate_pct

FROM base
GROUP BY seller_org_id;





