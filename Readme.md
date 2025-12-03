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

---

Each file contains a single query for reporting or analysis purposes. For details, refer to the SQL code in each file.
