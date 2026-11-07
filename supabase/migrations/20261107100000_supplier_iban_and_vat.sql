-- Supplier bank account (IBAN) for payouts + VAT note.
alter table public.seller_applications
  add column if not exists iban text
  check (iban is null or iban ~ '^SA[0-9]{22}$');
grant insert(iban) on public.seller_applications to authenticated;

-- Record VAT-inclusive amount for gateway payments (15% KSA VAT).
create or replace function private.record_gateway_payment(p_order_id uuid, p_reference text, p_gateway text)
returns void language plpgsql security definer set search_path='' as $$
declare v_order public.orders%rowtype; v_reference text:=btrim(p_reference); v_time timestamptz:=now(); v_existing text; v_base bigint;
begin
  if v_reference is null or length(v_reference) not between 6 and 160 then raise exception 'invalid payment reference'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found or v_order.status='cancelled' then raise exception 'order unavailable for payment confirmation'; end if;
  select reference into v_existing from private.order_payments where order_id=p_order_id;
  if v_existing is not null then
    if v_existing=v_reference then return; end if;
    raise exception 'payment already recorded';
  end if;
  v_base := coalesce(v_order.subtotal_halalas,0)+coalesce(v_order.delivery_halalas,0);
  insert into private.order_payments(order_id,reference,amount_halalas,verified_by,verified_at,gateway)
  values(p_order_id,v_reference, round(v_base*1.15), null,v_time,coalesce(p_gateway,'tap'));
  update public.orders set payment_status='paid',paid_at=v_time where id=p_order_id;
end $$;
