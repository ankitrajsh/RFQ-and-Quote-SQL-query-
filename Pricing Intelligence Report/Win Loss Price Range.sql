


-----Win-Loss Price Range: % of orders won at which price points.
WITH params AS (
    SELECT 
        517::bigint AS vendor_id        -- << put your vendor_id here
),

base AS (
    SELECT 
        r.id AS rfq_id,
        rq.id AS quote_id,
        rq.status,
        pd.total_amount,
        pd.total_qty,
        pd.seller_org_id
    FROM po_details pd
    JOIN po_quotes pq 
        ON pd.id = pq.po_id
    JOIN bt_rfq_quotes rq 
        ON pq.quote_id = rq.id
    JOIN bt_rfq r 
        ON rq.rfq_id = r.id
    JOIN params p 
        ON pd.seller_org_id = p.vendor_id   

agg AS (
    SELECT 
        rfq_id,
        MAX(CASE WHEN status = 6 THEN total_amount END) AS won_amount,
        MIN(CASE WHEN status <> 6 THEN total_amount END) AS min_competitor_amount
    FROM base
    GROUP BY rfq_id
)

SELECT 
    b.rfq_id,
    b.quote_id,
    b.status,
    b.total_amount,
    b.seller_org_id AS vendor_id,
    a.won_amount,
    a.min_competitor_amount,

    CASE 
        WHEN b.status = 6 THEN (a.won_amount - a.min_competitor_amount)
    END AS win_loss_percentage,

    CASE 
        WHEN b.status <> 6 THEN (b.total_amount - a.won_amount)
    END AS competitor_diff

FROM base b
LEFT JOIN agg a 
    ON b.rfq_id = a.rfq_id
ORDER BY b.rfq_id, b.quote_id;
