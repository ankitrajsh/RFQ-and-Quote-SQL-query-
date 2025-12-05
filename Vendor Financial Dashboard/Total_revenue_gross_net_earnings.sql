select 
pd.seller_user_id,
sum(pi.total_amount) as Total_revenue,
sum(pi.gross_amount) as Total_Gross_revenue,
sum(pi.net_total) as Net_earning
from po_items pi
left join po_details pd
on pi.po_id = pd.id
where pd.seller_user_id =517
group by pd.seller_user_id
;
