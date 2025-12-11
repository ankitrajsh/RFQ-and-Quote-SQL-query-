

-----Win-Loss Price Range: % of orders won at which price points.
-- ====== FILTER PARAMS ======
WITH params AS (
    SELECT 
        517 AS vendor_id   -- << put your seller_user_id here
),

-- ====== WINNING QUOTES ======
rfq_winners AS (
    SELECT 
        rfq.rfq_id,
        pd.seller_user_id AS winner_vendor_id,
        rfq."unitPrice" AS winning_price
    FROM po_details pd
    LEFT JOIN po_quotes pq ON pd.id = pq.po_id
    LEFT JOIN bt_rfq_quotes rfq ON pq.quote_id = rfq.id
    WHERE rfq.status = 6
),

-- ====== ALL QUOTES + OUTCOME ======
vendor_quotes_with_outcome AS (
    SELECT 
        pd.seller_user_id,
        rfq.rfq_id,
        rfq."unitPrice" AS vendor_price,
        rfq.status,
        CASE WHEN rfq.status = 6 THEN 'Won' ELSE 'Lost' END AS outcome,
        rw.winning_price,
        CASE 
            WHEN rfq.status = 6 THEN rfq."unitPrice"
            ELSE rw.winning_price
        END AS reference_price
    FROM po_details pd
    CROSS JOIN params p
    LEFT JOIN po_quotes pq ON pd.id = pq.po_id
    LEFT JOIN bt_rfq_quotes rfq ON pq.quote_id = rfq.id
    LEFT JOIN rfq_winners rw ON rfq.rfq_id = rw.rfq_id
    WHERE rfq."unitPrice" IS NOT NULL
      AND pd.seller_user_id = p.vendor_id   -- <<< FILTER APPLIED HERE
)

-- ====== FINAL RESULT ======
SELECT 
    seller_user_id,
    COUNT(*) AS total_quotes,
    SUM(CASE WHEN outcome = 'Won' THEN 1 ELSE 0 END) AS won_quotes,
    SUM(CASE WHEN outcome = 'Lost' THEN 1 ELSE 0 END) AS lost_quotes,
    CASE 
        WHEN SUM(CASE WHEN outcome = 'Won' THEN 1 ELSE 0 END) > 0 
        THEN ROUND(CAST((SUM(CASE WHEN outcome = 'Won' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS numeric), 2)
        ELSE ROUND(CAST(AVG(CASE WHEN outcome = 'Lost' THEN 
            ((vendor_price - winning_price) * 100.0 / NULLIF(winning_price, 0)) 
        END) AS numeric), 2)
    END AS win_loss_percentage
FROM vendor_quotes_with_outcome
GROUP BY seller_user_id
ORDER BY total_quotes DESC;
