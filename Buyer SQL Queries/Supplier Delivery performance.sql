------------------------------------------------------------
-- Card 1: Defect Rate
------------------------------------------------------------

-- SELECT
--     ROUND(
--         (
--             100.0 * 
--             SUM(
--                 CASE 
--                     WHEN bp.requested_qty IS NULL THEN 0
--                     ELSE GREATEST(bp.requested_qty - COALESCE(bqh.offered_qty, 0), 0)
--                 END
--             ) / NULLIF(SUM(bp.requested_qty), 0)
--         )::numeric,
--         2
--     ) AS defect_rate_percentage
-- FROM bt_rfq_products bp
-- LEFT JOIN bt_rfq_quotes_history bqh
--     ON bp.id = bqh.rfq_product_id
-- WHERE bp.requested_qty IS NOT NULL;

------------------------------------------------------------
-- Card 2: On-Time Supplies
------------------------------------------------------------
-- SELECT
--         ROUND(
--         100.0 * COUNT(*) FILTER (WHERE mdate::date <= delivery_date::date) / NULLIF(COUNT(*), 0),
--         2
--     ) AS on_time_supplies_percentage
-- FROM bt_rfq_quotes_history
-- WHERE delivery_date IS NOT NULL AND mdate IS NOT NULL;

------------------------------------------------------------
-- Card 3: Supplier Availability
------------------------------------------------------------

-- SELECT
--     ROUND(AVG(supplier_availability_percentage), 2) AS overall_supplier_availability_percentage
-- FROM (
--     SELECT
--         seller_id,
--         COUNT(*) FILTER (WHERE status IS NOT NULL) AS rfqs_responded,
--         COUNT(*) AS rfqs_received,
--         100.0 * COUNT(*) FILTER (WHERE status IS NOT NULL) / NULLIF(COUNT(*), 0) AS supplier_availability_percentage
--     FROM bt_rfq_quotes_history
--     GROUP BY seller_id
-- ) AS supplier_data;

------------------------------------------------------------
-- Card 4: Lead Time (days)
------------------------------------------------------------

-- SELECT 
--     ROUND(AVG(EXTRACT(DAY FROM rp.mdate - qh.cdate)), 2) AS overall_avg_lead_time_days
-- FROM bt_rfq_quotes_history qh
-- LEFT JOIN bt_rfq_products rp 
--     ON qh.rfq_product_id = rp.id
-- WHERE qh.cdate IS NOT NULL
--   AND rp.mdate IS NOT NULL
--   AND rp.mdate > qh.cdate;

------------------------------------------------------------
-- Card 5: Supplier Defect Rate
------------------------------------------------------------
-- WITH monthly_defect_rates AS (
--     SELECT
--         TO_CHAR(poi.updated_date, 'YYYY-MM') AS month,
--         ROUND(
--             100.0 * SUM(GREATEST(rp.requested_qty::numeric - poi.qty::numeric, 0)) /
--             NULLIF(SUM(rp.requested_qty::numeric), 0),
--             2
--         ) AS defect_rate_percentage
--     FROM bt_rfq_products rp
--     JOIN po_items poi 
--         ON rp.product_id = poi.product_id
--     WHERE poi.updated_date >= date_trunc('month', CURRENT_DATE) - INTERVAL '12 months'
--       AND poi.updated_date < date_trunc('month', CURRENT_DATE)
--       AND rp.requested_qty IS NOT NULL
--       AND poi.qty IS NOT NULL
--     GROUP BY TO_CHAR(poi.updated_date, 'YYYY-MM')
-- )
-- SELECT 
--     month,
--     defect_rate_percentage,
--     ROUND(AVG(defect_rate_percentage) OVER (), 2) AS overall_avg_defect_rate
-- FROM monthly_defect_rates
-- ORDER BY month;

--------------------------------------------------------------
-- Card 6: Supplier Availability
-- ------------------------------------------------------------

-- WITH rfq_data AS (
--     SELECT
--         DATE_TRUNC('month', rp.cdate) AS month,
--         rp.seller_id,
--         rp.product_id
--     FROM bt_rfq_products rp
--     WHERE rp.cdate >= NOW() - INTERVAL '12 months'
-- ),
-- po_data AS (
--     SELECT
--         DATE_TRUNC('month', poi.updated_date) AS month,
--         poi.product_id,
--         poi.source_id::INTEGER AS supplier_id
--     FROM po_items poi
--     WHERE poi.updated_date >= NOW() - INTERVAL '12 months'
-- ),
-- supplier_match AS (
--     SELECT DISTINCT
--         rfq.month,
--         rfq.seller_id,
--         rfq.product_id,
--         po.supplier_id
--     FROM rfq_data rfq
--     LEFT JOIN po_data po
--         ON rfq.product_id = po.product_id
--         AND rfq.seller_id = po.supplier_id
--         AND rfq.month = po.month
-- ),
-- availability AS (
--     SELECT
--         month,
--         COUNT(DISTINCT seller_id) AS total_suppliers_sent,
--         COUNT(DISTINCT supplier_id) AS total_suppliers_delivered,
--         ROUND(
--             100.0 * COUNT(DISTINCT supplier_id) / NULLIF(COUNT(DISTINCT seller_id), 0), 
--             2
--         ) AS supplier_availability_percentage
--     FROM supplier_match
--     GROUP BY month
-- ),
-- final AS (
--     SELECT
--         TO_CHAR(month, 'YYYY-MM') AS month,
--         supplier_availability_percentage
--     FROM availability
-- ),
-- six_month_avg AS (
--     SELECT 
--         ROUND(AVG(supplier_availability_percentage), 2) AS six_month_avg_availability
--     FROM final
--     WHERE month >= TO_CHAR(NOW() - INTERVAL '6 months', 'YYYY-MM')
-- )
-- SELECT 
--     f.month,
--     f.supplier_availability_percentage,
--     s.six_month_avg_availability
-- FROM final f
-- CROSS JOIN six_month_avg s
-- ORDER BY f.month;

--------------------------------------------------------------
-- Card 7: Lead Time (In Days)
-- ------------------------------------------------------------

-- WITH rfq_data AS (
--     SELECT
--         rp.rfq_id,
--         rp.product_id,
--         rp.cdate::DATE AS rfq_created_date
--     FROM bt_rfq_products rp
--     WHERE rp.cdate >= NOW() - INTERVAL '12 months'
-- ),
-- po_data AS (
--     SELECT
--         poi.po_id,
--         poi.product_id,
--         poi.updated_date::DATE AS delivery_date,
--         poi.source_id::INTEGER AS supplier_id
--     FROM po_items poi
--     WHERE poi.updated_date >= NOW() - INTERVAL '12 months'
-- ),
-- joined_data AS (
--     SELECT
--         DATE_TRUNC('month', po.delivery_date) AS month,
--         rfq.product_id,
--         po.supplier_id,
--         rfq.rfq_created_date,
--         po.delivery_date,
--         GREATEST(0, (po.delivery_date - rfq.rfq_created_date)) AS lead_time_days
--     FROM rfq_data rfq
--     JOIN po_data po
--         ON rfq.product_id = po.product_id
-- ),
-- monthly_lead_time AS (
--     SELECT
--         TO_CHAR(month, 'YYYY-MM') AS month,
--         ROUND(AVG(lead_time_days), 2) AS avg_lead_time
--     FROM joined_data
--     GROUP BY month
-- ),
-- six_month_avg AS (
--     SELECT 
--         ROUND(AVG(avg_lead_time), 2) AS avg_lead_time_last_6_months
--     FROM monthly_lead_time
--     WHERE month >= TO_CHAR(NOW() - INTERVAL '6 months', 'YYYY-MM')
-- )

-- SELECT 
--     mlt.month,
--     mlt.avg_lead_time,
--     sma.avg_lead_time_last_6_months
-- FROM monthly_lead_time mlt
-- CROSS JOIN six_month_avg sma
-- ORDER BY mlt.month;
---------------------------------------------------------------
-- Card 8: Supplier Defect Rate & Defect Type
-- ------------------------------------------------------------

-- WITH base_data AS (
--     SELECT
--         bp.seller_id AS supplier_id,
--         bp.requested_qty,
--         COALESCE(bqh.offered_qty, 0) AS offered_qty,
--         TRIM(LOWER(bqh.remarks)) AS defect_remark
--     FROM bt_rfq_products bp
--     LEFT JOIN bt_rfq_quotes_history bqh
--         ON bp.id = bqh.rfq_product_id
--     WHERE bp.requested_qty IS NOT NULL
-- ),
-- classified_defects AS (
--     SELECT
--         supplier_id,
--         requested_qty,
--         offered_qty,
--         GREATEST(requested_qty - offered_qty, 0) AS defect_qty,
--         CASE
--             WHEN defect_remark = 'rejected' THEN 'Rejected'
--             WHEN defect_remark = 'impact' THEN 'Impact'
--             WHEN defect_remark = 'no impact' THEN 'No Impact'
--             ELSE 'Uncategorized'
--         END AS defect_type
--     FROM base_data
-- ),
-- supplier_stats AS (
--     SELECT
--         supplier_id,
--         SUM(defect_qty) AS total_defect_qty,
--         SUM(requested_qty) AS total_requested_qty,
--         ROUND(
--             (100.0 * SUM(defect_qty) / NULLIF(SUM(requested_qty), 0))::numeric, 
--             2
--         ) AS defect_rate_pct,
--         SUM(CASE WHEN defect_type = 'Rejected' THEN defect_qty ELSE 0 END) AS rejected_qty,
--         SUM(CASE WHEN defect_type = 'Impact' THEN defect_qty ELSE 0 END) AS impact_qty,
--         SUM(CASE WHEN defect_type = 'No Impact' THEN defect_qty ELSE 0 END) AS no_impact_qty,
--         SUM(CASE WHEN defect_type = 'Uncategorized' THEN defect_qty ELSE 0 END) AS uncategorized_qty
--     FROM classified_defects
--     GROUP BY supplier_id
-- )
-- SELECT
--     supplier_id,
--     ROUND((100.0 * rejected_qty / NULLIF(total_defect_qty, 0))::numeric, 2) AS rejected_pct,
--     ROUND((100.0 * impact_qty / NULLIF(total_defect_qty, 0))::numeric, 2) AS impact_pct,
--     ROUND((100.0 * no_impact_qty / NULLIF(total_defect_qty, 0))::numeric, 2) AS no_impact_pct,
--     ROUND((100.0 * uncategorized_qty / NULLIF(total_defect_qty, 0))::numeric, 2) AS uncategorized_pct,
--     defect_rate_pct
-- FROM supplier_stats
-- ORDER BY supplier_id;

---------------------------------------------------------------
-- Card 9: Delivery Time
-- ------------------------------------------------------------

WITH delivery_status AS (
    SELECT
        seller_id AS supplier_id,
        CASE
            WHEN mdate < delivery_date THEN 'Early'
            WHEN mdate = delivery_date THEN 'On Time'
            WHEN mdate > delivery_date THEN 'Late'
            ELSE 'Unknown'
        END AS delivery_category
    FROM bt_rfq_quotes_history
    WHERE mdate IS NOT NULL AND delivery_date IS NOT NULL
),
status_counts AS (
    SELECT
        supplier_id,
        COUNT(*) FILTER (WHERE delivery_category = 'Early') AS early_count,
        COUNT(*) FILTER (WHERE delivery_category = 'On Time') AS on_time_count,
        COUNT(*) FILTER (WHERE delivery_category = 'Late') AS late_count,
        COUNT(*) AS total_deliveries
    FROM delivery_status
    GROUP BY supplier_id
)
SELECT
    supplier_id,
    ROUND((100.0 * early_count / NULLIF(total_deliveries, 0))::numeric, 2) AS early_pct,
    ROUND((100.0 * on_time_count / NULLIF(total_deliveries, 0))::numeric, 2) AS on_time_pct,
    ROUND((100.0 * late_count / NULLIF(total_deliveries, 0))::numeric, 2) AS late_pct
FROM status_counts
ORDER BY supplier_id;
