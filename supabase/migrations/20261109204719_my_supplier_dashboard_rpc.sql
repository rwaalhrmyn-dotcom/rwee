-- Applied to production via MCP apply_migration; exported from session history for repo parity.
create or replace function private.my_supplier_dashboard()
returns table(
  id uuid, name text, approval_status text, cities text[],
  national_address text, warehouse_city text,
  warehouse_name text, warehouse_address text,
  products_count bigint, active_products bigint, low_stock bigint
)
language plpgsql stable security definer set search_path to '' as $$
begin
  perform private.assert_account_session();
  if auth.uid() is null then
    raise exception 'authenticated user required' using errcode='42501';
  end if;
  return query
  select s.id, s.name, s.approval_status, s.cities,
         s.national_address, s.warehouse_city,
         w.name, w.national_address,
         (select count(*) from public.products p where p.supplier_id=s.id and coalesce(p.archived,false)=false),
         (select count(*) from public.products p where p.supplier_id=s.id and coalesce(p.active,false)=true and coalesce(p.archived,false)=false),
         (select count(*) from public.products p where p.supplier_id=s.id and coalesce(p.archived,false)=false and coalesce(p.stock,0) <= 5)
  from public.suppliers s
  left join lateral (
    select wh.name, wh.national_address
    from public.warehouses wh where wh.supplier_id=s.id
    order by wh.created_at limit 1
  ) w on true
  where s.owner_id=auth.uid()
  order by s.created_at;
end $$;

create or replace function public.my_supplier_dashboard()
returns table(
  id uuid, name text, approval_status text, cities text[],
  national_address text, warehouse_city text,
  warehouse_name text, warehouse_address text,
  products_count bigint, active_products bigint, low_stock bigint
)
language sql stable set search_path to '' as $$
  select * from private.my_supplier_dashboard()
$$;

revoke all on function public.my_supplier_dashboard() from anon, public;
grant execute on function public.my_supplier_dashboard() to authenticated;
