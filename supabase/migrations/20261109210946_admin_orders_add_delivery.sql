-- Applied to production via MCP apply_migration; exported from session history for repo parity.
drop function if exists public.admin_orders(text);
create function public.admin_orders(p_status text default null)
 returns table(id uuid, created_at timestamptz, status text, payment_status text, recipient_name text, phone text, city text, address text, subtotal_halalas bigint, delivery_halalas integer, delivery_method text, total_halalas bigint, items bigint)
 language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select o.id,o.created_at,o.status,o.payment_status,o.recipient_name,o.phone,o.city,o.address,
      o.subtotal_halalas, o.delivery_halalas, o.delivery_method, o.total_halalas,
      (select count(*) from public.order_items oi where oi.order_id=o.id)
    from public.orders o
    where p_status is null or o.status=p_status
    order by o.created_at desc limit 500;
end $$;
revoke all on function public.admin_orders(text) from anon, public;
grant execute on function public.admin_orders(text) to authenticated;
