# Workspace SQL Files Overview

This document lists all SQL files in the workspace and their purpose.

## Top-level Files

- **Price Competitiveness.sql**: SQL queries related to price competitiveness analysis.
- **RFQ_receive_Responded_won_poGenerated_Conversionrate.sql**: SQL queries for RFQ lifecycle and conversion rate calculations.
- **Sales_Dashboard_final .sql**: Final version of sales dashboard queries.

## Sales Performance Report Folder

- **CompleteTable.sql**: Query for the complete RFQ and quote table.
- **Conversion_rate_private.sql**: Calculates conversion rate for private RFQs.
- **Conversion_rate_public.sql**: Calculates conversion rate for public RFQs.
- **Conversion_rate_total.sql**: Calculates overall conversion rate for all RFQs.
- **PO_Generated_private.sql**: Counts private RFQs with PO generated status.
- **PO_Generated_public.sql**: Counts public RFQs with PO generated status.
- **PO_Generated_total.sql**: Counts all RFQs with PO generated status.
- **Quote_submitted_private.sql**: Counts private RFQs with submitted quotes.
- **Quote_submitted_public.sql**: Counts public RFQs with submitted quotes.
- **Quote_submitted_total.sql**: Counts all RFQs with submitted quotes.
- **Quote_won_private.sql**: Counts private RFQs with quote won status.
- **Quote_won_public.sql**: Counts public RFQs with quote won status.
- **Quote_won_total.sql**: Counts all RFQs with quote won status.
- **average_response_time.sql**: Calculates average vendor response time for RFQs.
- **most_response_from_vendor.sql**: Lists RFQ IDs with the most vendor responses.
- **rfq_recieved_private.sql**: Counts private RFQs received.
- **rfq_recieved_public.sql**: Counts public RFQs received.
- **rfq_recieved_total.sql**: Counts all RFQs received.

## RFQ & Quote Conversion Report Folder

- **RFQs_Received_Quotes_Submitted_Conversion_Rate.sql**: Calculates RFQs received, quotes submitted, quotes converted, and conversion rate percentage.
- **Price_Competitiveness.sql**: Analyzes price competitiveness by comparing vendor quotes with winning quotes.
- **Avg_Response_Time.sql**: Calculates average vendor response time from RFQ publication to quote submission.
- **Funnel_Chart.sql**: Provides funnel chart data showing RFQ to conversion flow.
- **Heatmap_RFQs_by_Region_Product.sql**: Generates heatmap data for RFQs by region and product.
- **Box_Plot_Price_Variance.sql**: Analyzes price variance across RFQs for box plot visualization.
- **Response_Time_Histogram.sql**: Provides histogram data for vendor response times.

## Customer Engagement Behaviour Report Folder

- **Add-to-Quote Rate.sql**: Calculates the rate at which products are added to quotes.
- **Buyer Intent Score.sql**: Computes buyer intent scores based on engagement metrics.
- **Clickstream Treemap-chart.sql**: Generates clickstream data for treemap visualization.
- **Drop-off Points in Conversion Flow.sql**: Identifies drop-off points in the customer conversion funnel.
- **Engagement Duration.sql**: Measures customer engagement duration metrics.
- **Engagement Frequency Segmentation.sql**: Segments customers by engagement frequency.
- **Engagement Funnel-chart.sql**: Provides data for engagement funnel visualization.
- **Heatmap-Chart.sql**: Generates heatmap data for customer engagement analysis.
- **Message Initiation.sql**: Tracks message initiation patterns between buyers and vendors.
- **Sankey-chart.sql**: Provides data for Sankey diagram visualization of customer flow.
- **Views per Product.sql**: Counts product views by category or product.
- **Wishlist Activity.sql**: Analyzes wishlist activity by product category.

## Logistics Fulfillment Report Folder

- **Delivery Time vs. SLA.sql**: Compares actual delivery times against SLA targets.
- **Fulfillment Cost.sql**: Analyzes fulfillment costs across orders.
- **On-Time Delivery Rate.sql**: Calculates on-time delivery performance rate.
- **Return RTO Rate.sql**: Measures return to origin (RTO) rate for shipments.

## Pricing Intelligence Report Folder

- **Median Price Gap.sql**: Calculates median price gap between vendor quotes and market prices.
- **Win Loss Price Range.sql**: Analyzes price ranges for won vs. lost quotes.

## Vendor Financial Dashboard Folder

- **Overdue_invoices.sql**: Tracks overdue invoices for vendors.
- **Total_revenue_gross_net_earnings.sql**: Calculates total revenue, gross earnings, and net earnings for vendors.

---

Each file contains a single query for reporting or analysis purposes. For details, refer to the SQL code in each file.
