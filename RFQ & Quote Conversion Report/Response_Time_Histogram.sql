---Additional: Response Time Histogram.
WITH params AS (
    SELECT 
        91 AS vendor_id,
        DATE '2025-01-01' AS start_date,
        DATE '2025-12-31' AS end_date
),

publish_times AS (
    SELECT 
        r.id AS rfq_id,
        r.publish_date
    FROM bt_rfq r
),

first_vendor_response AS (
    SELECT
        al.rfq_id,
        MIN(al.updated_date) AS first_response_time
    FROM bt_rfq_activity_logs al
    JOIN bt_rfq_quotes rq 
	ON rq.id = al.quote_id
    JOIN params p 
	ON rq.seller_id = p.vendor_id
    WHERE al.new_status = 9
      AND al.updated_date BETWEEN p.start_date AND p.end_date
    GROUP BY al.rfq_id
)

SELECT
    p.rfq_id,
    p.publish_date,
    f.first_response_time,
    EXTRACT(EPOCH FROM (f.first_response_time - p.publish_date)) / 60
        AS response_time_mins
FROM publish_times p
JOIN first_vendor_response f
    ON p.rfq_id = f.rfq_id
WHERE f.first_response_time IS NOT NULL;
