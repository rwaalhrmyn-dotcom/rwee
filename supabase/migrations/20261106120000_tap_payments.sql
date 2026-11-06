-- Tap Payments gateway integration: allow automated (webhook) payment recording.
-- The existing record_verified_payment requires a human operator; card/Apple Pay
-- payments are confirmed server-side by the Tap webhook running as service_role.

-- 1) order_payments: allow gateway-verified rows (no human verifier) + track gateway
alter table private.order_payments alter column verified_by drop not null;
alter table private.order_payments add column if not exists gateway text;

-- 2) service-role-only function to record a gateway-verified payment
create or replace function private.record_gateway_payment(p_order_id uuid, p_reference text, p_gateway text)
returns void language plpgsql security definer set search_path='' as $$
declare v_order public.orders%rowtype; v_reference text:=btrim(p_reference); v_time timestamptz:=now(); v_existing text;
begin
  if v_reference is null or length(v_reference) not between 6 and 160 then raise exception 'invalid payment reference'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found or v_order.status='cancelled' then raise exception 'order unavailable for payment confirmation'; end if;
  select reference into v_existing from private.order_payments where order_id=p_order_id;
  if v_existing is not null then
    if v_existing=v_reference then return; end if;
    raise exception 'payment already recorded';
  end if;
  insert into private.order_payments(order_id,reference,amount_halalas,verified_by,verified_at,gateway)
  values(p_order_id,v_reference,
         coalesce(v_order.subtotal_halalas,0)+coalesce(v_order.delivery_halalas,0),
         null,v_time,coalesce(p_gateway,'tap'));
  update public.orders set payment_status='paid',paid_at=v_time where id=p_order_id;
end $$;

-- 3) public wrapper callable only by service_role (used by the tap-webhook edge function)
create or replace function public.record_gateway_payment(p_order_id uuid, p_reference text, p_gateway text)
returns void language sql security invoker set search_path='' as $$
  select private.record_gateway_payment(p_order_id,p_reference,p_gateway) $$;

revoke all on function private.record_gateway_payment(uuid,text,text),public.record_gateway_payment(uuid,text,text) from public,anon,authenticated;
grant execute on function public.record_gateway_payment(uuid,text,text) to service_role;
