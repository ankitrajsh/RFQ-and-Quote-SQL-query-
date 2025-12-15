
-----Return/RTO Rate: Returns and undelivered shipments.
WITH params AS (
    SELECT
        509::bigint AS seller_org_id

),

base AS (
    SELECT
        a.id,
        a.seller_org_id,
        a.status
    FROM po_asn a
    JOIN params p
      ON a.seller_org_id = p.seller_org_id)

SELECT
    seller_org_id,

    COUNT(*) AS total_shipments,

    COUNT(*) FILTER (WHERE status = '19')
        AS undelivered_shipments,

    COUNT(*) FILTER (WHERE status = '20')
        AS returns,

    ROUND(
        100.0 *
        COUNT(*) FILTER (WHERE status IN ('19', '20'))
        / NULLIF(COUNT(*), 0),
        2
    ) AS return_rto_rate_pct

FROM base
GROUP BY seller_org_id;

