WITH activity AS (
    SELECT 
        r.id AS rfq_id,
        ral.updated_by,
        ral.new_status,
        ral.old_status,
        ral.updated_date,
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
        updated_by AS buyer_id
    FROM activity
    WHERE rn = 1
),

vendor_actions AS (
    SELECT
        a.rfq_id,
        a.updated_by AS vendor_id
    FROM activity a
    JOIN buyer_activity b
        ON a.rfq_id = b.rfq_id
    WHERE a.updated_by <> b.buyer_id        
      AND a.new_status <> a.old_status      
),

vendor_count AS (
    SELECT
        rfq_id,
        COUNT(DISTINCT vendor_id) AS total_vendors
    FROM vendor_actions
    GROUP BY rfq_id
)

SELECT 
    rfq_id,
    total_vendors
FROM vendor_count
ORDER BY total_vendors DESC
LIMIT 20;
