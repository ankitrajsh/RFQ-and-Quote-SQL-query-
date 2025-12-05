
SELECT * FROM public.po_proforma_invoice
select 
pd.seller_user_id,
count(distinct ppi.invoice_due_days) as overdue_invoice 
from po_proforma_invoice ppi
left join po_details pd
on ppi.po_id = pd.id
where pd.seller_user_id = 517
group by pd.seller_user_id;