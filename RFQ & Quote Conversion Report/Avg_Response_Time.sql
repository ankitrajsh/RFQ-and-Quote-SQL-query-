/* Avg. Response time*/
WITH params AS (
    SELECT 
        91 AS vendor_id,                         -- vendor_id to filter
        DATE '2025-01-01' AS start_date,         -- date window start
        DATE '2025-12-31' AS end_date            -- date window end
),

-- sent to supplier time (status 2)
sent AS (
    SELECT 
        al.rfq_id,
        al.rfq_product_id,
        MIN(CASE WHEN al.new_status = 2 THEN al.updated_date END) AS sent_to_supplier_time
    FROM bt_rfq_activity_logs al
    JOIN params p ON 1=1
    WHERE al.updated_date BETWEEN p.start_date AND p.end_date
    GROUP BY al.rfq_id, al.rfq_product_id
),

-- vendor quote submission time (status 9)
quotes AS (
    SELECT 
        al.rfq_id,
        al.rfq_product_id,
        al.quote_id,
        MIN(CASE WHEN al.new_status = 9 THEN al.updated_date END) AS quote_sent_time
    FROM bt_rfq_activity_logs al
    JOIN params p ON 1=1
    WHERE al.quote_id IS NOT NULL
      AND al.updated_date BETWEEN p.start_date AND p.end_date
    GROUP BY al.rfq_id, al.rfq_product_id, al.quote_id
),

-- Add seller_id and calculate response time per quote
response_times AS (
    SELECT 
        s.rfq_id,
        s.rfq_product_id,
        q.quote_id,
        rq.seller_id,
        s.sent_to_supplier_time,
        q.quote_sent_time,
        EXTRACT(EPOCH FROM (q.quote_sent_time - s.sent_to_supplier_time)) / 60
            AS response_mins
    FROM sent s
    JOIN quotes q 
        ON s.rfq_id = q.rfq_id
       AND s.rfq_product_id = q.rfq_product_id
    JOIN bt_rfq_quotes rq
        ON q.quote_id = rq.id
    JOIN params p 
        ON rq.seller_id = p.vendor_id
)

-- Final metric: average response time for this vendor
SELECT 
    seller_id,
    AVG(response_mins) AS avg_response_time_mins
FROM response_times
GROUP BY seller_id;
