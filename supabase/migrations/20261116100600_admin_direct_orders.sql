-- Admin view of supplier-direct orders + guard: direct orders can only become "paid" through a verified gateway webhook.
create or replace function public.admin_set_order_paid(p_order_id uuid, p_paid boolean)
returns void language plpgsql security definer set search_path to '' as $$
declare v_mode text;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select payment_mode into v_mode from public.orders where id=p_order_id;
  if not found then raise exception 'order not found'; end if;
  if v_mode = 'supplier_direct' then
    raise exception 'supplier-direct orders are marked paid only by a verified gateway webhook' using errcode='42501';
  end if;
  if p_paid then
    update public.orders set payment_status='paid', paid_at=coalesce(paid_at,now()) where id=p_order_id;
  else
    update public.orders set payment_status='unpaid', paid_at=null where id=p_order_id;
  end if;
end $$;

create or replace function public.admin_direct_orders(p_limit integer default 200) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select jsonb_build_object('id', o.id, 'created_at', o.created_at, 'status', o.status, 'payment_status', o.payment_status,
      'supplier_name', s.name, 'payable_halalas', o.payable_halalas, 'vat_halalas', o.vat_halalas, 'refunded_halalas', o.refunded_halalas,
      'refund_status', o.refund_status, 'payment_flag', o.payment_flag, 'delivered_at', o.delivered_at,
      'commission_halalas', (select coalesce(sum(oi.base_commission_halalas + oi.markup_commission_halalas),0) from public.order_items oi where oi.order_id=o.id),
      'open_dispute', exists(select 1 from public.payment_disputes d where d.order_id=o.id and d.status in ('open','under_review')))
    from public.orders o left join public.suppliers s on s.id=o.supplier_id
    where o.payment_mode='supplier_direct' order by o.created_at desc limit greatest(1, least(coalesce(p_limit,200), 1000));
end $$;
revoke all on function public.admin_direct_orders(integer) from public, anon;
grant execute on function public.admin_direct_orders(integer) to authenticated;
