WITH activity AS (
    SELECT 
        r.id AS rfq_id,
        ral.updated_by,
        ral.updated_date,
        ral.new_status,
        ral.old_status,
        ROW_NUMBER() OVER (PARTITION BY r.id ORDER BY ral.updated_date ASC) AS rn
    FROM public.bt_rfq r
    LEFT JOIN bt_rfq_activity_logs ral
        ON r.id = ral.rfq_id
    WHERE r.visibility = 'public'
      AND ral.updated_date IS NOT NULL
),

buyer_activity AS (
    SELECT 
        rfq_id,
        updated_by AS buyer_id,
        updated_date AS buyer_time
    FROM activity
    WHERE rn = 1
),

vendor_responses AS (
    SELECT 
        a.rfq_id,
        a.updated_by AS vendor_id,
        a.updated_date AS vendor_time,
        
        ROW_NUMBER() OVER (PARTITION BY a.rfq_id ORDER BY a.updated_date ASC) AS vendor_rank
    FROM activity a
    JOIN buyer_activity b
        ON a.rfq_id = b.rfq_id
    WHERE a.updated_by <> b.buyer_id
      AND a.new_status <> a.old_status  
),

first_vendor_response AS (
    SELECT 
        rfq_id,
        vendor_id,
        vendor_time
    FROM vendor_responses
    WHERE vendor_rank = 1
),

response_times AS (
    SELECT
        b.rfq_id,
        b.buyer_id,
        b.buyer_time,
        f.vendor_id,
        f.vendor_time,
        EXTRACT(EPOCH FROM (f.vendor_time - b.buyer_time)) / 3600 AS response_hours,
        EXTRACT(EPOCH FROM (f.vendor_time - b.buyer_time)) / 86400 AS response_days
    FROM buyer_activity b
    LEFT JOIN first_vendor_response f
        ON b.rfq_id = f.rfq_id
)


WITH activity AS (
    SELECT 
        r.id AS rfq_id,
        r.publish_date,
        ral.updated_by,
        ral.updated_date,
        ral.new_status,
        ral.old_status,
        ROW_NUMBER() OVER (PARTITION BY r.id ORDER BY ral.updated_date ASC) AS rn
    FROM public.bt_rfq r
    LEFT JOIN bt_rfq_activity_logs ral
        ON r.id = ral.rfq_id
    WHERE r.visibility = 'public'
      AND ral.updated_date IS NOT NULL
),

buyer_activity AS (
    SELECT 
        rfq_id,
        updated_by AS buyer_id,
        publish_date AS buyer_time
    FROM activity
    WHERE rn = 1
),

vendor_responses AS (
    SELECT 
        a.rfq_id,
        a.updated_by AS vendor_id,
        a.updated_date AS vendor_time,
        
        ROW_NUMBER() OVER (PARTITION BY a.rfq_id ORDER BY a.updated_date ASC) AS vendor_rank
    FROM activity a
    JOIN buyer_activity b
        ON a.rfq_id = b.rfq_id
    WHERE a.updated_by <> b.buyer_id
      AND a.new_status <> a.old_status  
),

first_vendor_response AS (
    SELECT 
        rfq_id,
        vendor_id,
        vendor_time
    FROM vendor_responses
    WHERE vendor_rank = 1
),

response_times AS (
    SELECT
        b.rfq_id,
        b.buyer_id,
        b.buyer_time,
        f.vendor_id,
        f.vendor_time,
        EXTRACT(EPOCH FROM (f.vendor_time - b.buyer_time)) / 3600 AS response_hours,
        EXTRACT(EPOCH FROM (f.vendor_time - b.buyer_time)) / 86400 AS response_days
    FROM buyer_activity b
    LEFT JOIN first_vendor_response f
        ON b.rfq_id = f.rfq_id
)

SELECT 
    AVG(response_hours) AS avg_response_hours,
    AVG(response_days) AS avg_response_days
FROM response_times
WHERE vendor_id IS NOT NULL
;
SELECT 
    AVG(response_hours) AS avg_response_hours,
    AVG(response_days) AS avg_response_days
FROM response_times
WHERE vendor_id IS NOT NULL;
