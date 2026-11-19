-- Applied to production via MCP apply_migration; exported from session history for repo parity.
-- propagate accepts_delivery from application → supplier on approval
create or replace function public.admin_decide_application(p_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path to '' as $$
declare v_app public.seller_applications%rowtype; v_sup_id uuid;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into v_app from public.seller_applications where id=p_id for update;
  if not found then raise exception 'application not found'; end if;
  if p_approve then
    update public.seller_applications set status='approved' where id=p_id;
    select id into v_sup_id from public.suppliers where owner_id=v_app.owner_id and name=v_app.business_name limit 1;
    if v_sup_id is null then
      insert into public.suppliers(owner_id,name,cities,approval_status,national_address,tax_number,warehouse_city,accepts_delivery)
      values(v_app.owner_id, v_app.business_name, array['makkah','madinah'], 'approved', v_app.national_address, v_app.tax_number, v_app.city, coalesce(v_app.accepts_delivery,false))
      returning id into v_sup_id;
    else
      update public.suppliers set approval_status='approved', cities=array['makkah','madinah'],
        national_address=coalesce(v_app.national_address,national_address), tax_number=coalesce(v_app.tax_number,tax_number),
        warehouse_city=coalesce(v_app.city,warehouse_city), accepts_delivery=coalesce(v_app.accepts_delivery,accepts_delivery)
      where id=v_sup_id;
    end if;
    if not exists(select 1 from public.warehouses w where w.supplier_id=v_sup_id) then
      insert into public.warehouses(supplier_id, name, national_address, city)
      values (v_sup_id, 'المستودع الرئيسي', v_app.national_address, v_app.city);
    end if;
  else
    update public.seller_applications set status='rejected' where id=p_id;
  end if;
end $$;

-- dashboard: add accepts_delivery
drop function if exists public.my_supplier_dashboard();
drop function if exists private.my_supplier_dashboard();
create function private.my_supplier_dashboard()
returns table(
  id uuid, name text, approval_status text, cities text[],
  national_address text, warehouse_city text,
  warehouse_name text, warehouse_address text,
  products_count bigint, active_products bigint, low_stock bigint,
  accepts_delivery boolean
)
language plpgsql stable security definer set search_path to '' as $$
begin
  perform private.assert_account_session();
  if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
  return query
  select s.id, s.name, s.approval_status, s.cities,
         s.national_address, s.warehouse_city,
         w.name, w.national_address,
         (select count(*) from public.products p where p.supplier_id=s.id and coalesce(p.archived,false)=false),
         (select count(*) from public.products p where p.supplier_id=s.id and coalesce(p.active,false)=true and coalesce(p.archived,false)=false),
         (select count(*) from public.products p where p.supplier_id=s.id and coalesce(p.archived,false)=false and coalesce(p.stock,0) <= 5),
         coalesce(s.accepts_delivery,false)
  from public.suppliers s
  left join lateral (
    select wh.name, wh.national_address from public.warehouses wh
    where wh.supplier_id=s.id order by wh.created_at limit 1
  ) w on true
  where s.owner_id=auth.uid()
  order by s.created_at;
end $$;
create function public.my_supplier_dashboard()
returns table(
  id uuid, name text, approval_status text, cities text[],
  national_address text, warehouse_city text,
  warehouse_name text, warehouse_address text,
  products_count bigint, active_products bigint, low_stock bigint,
  accepts_delivery boolean
)
language sql stable set search_path to '' as $$ select * from private.my_supplier_dashboard() $$;
revoke all on function public.my_supplier_dashboard() from anon, public;
grant execute on function public.my_supplier_dashboard() to authenticated;
