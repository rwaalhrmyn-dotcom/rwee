-- Applied to production via MCP apply_migration; exported from session history for repo parity.
-- Options for a cart: is supplier-delivery available (all suppliers opted in), parcel count, fees
create or replace function public.delivery_options(p_product_ids uuid[])
returns table(supplier_delivery_available boolean, parcels int, supplier_delivery_halalas int, oto_waybill_halalas int)
language plpgsql stable security definer set search_path to '' as $$
declare v_parcels int; v_all boolean;
begin
  select ds.supplier_delivery_halalas, ds.oto_waybill_halalas
    into supplier_delivery_halalas, oto_waybill_halalas
    from private.delivery_settings ds limit 1;
  select count(distinct p.supplier_id), bool_and(coalesce(s.accepts_delivery,false))
    into v_parcels, v_all
    from public.products p
    join public.suppliers s on s.id=p.supplier_id
    where p.id = any(p_product_ids);
  parcels := coalesce(v_parcels,0);
  supplier_delivery_available := coalesce(v_all,false) and parcels > 0;
  return next;
end $$;
revoke all on function public.delivery_options(uuid[]) from public;
grant execute on function public.delivery_options(uuid[]) to anon, authenticated;

-- Set the chosen delivery method on an unpaid order; fee computed server-side from settings.
create or replace function public.set_order_delivery(p_order_id uuid, p_method text)
returns void language plpgsql security definer set search_path to '' as $$
declare v_user uuid:=auth.uid(); v_parcels int; v_all boolean; v_sup int; v_oto int; v_fee int; v_paid text;
begin
  perform private.assert_account_session();
  if v_user is null then raise exception 'authenticated user required' using errcode='42501'; end if;
  if p_method is null or p_method not in ('supplier','oto') then raise exception 'invalid delivery method'; end if;
  select payment_status into v_paid from public.orders where id=p_order_id and customer_id=v_user for update;
  if not found then raise exception 'order not found' using errcode='42501'; end if;
  if v_paid = 'paid' then raise exception 'order already paid'; end if;
  select ds.supplier_delivery_halalas, ds.oto_waybill_halalas into v_sup, v_oto
    from private.delivery_settings ds limit 1;
  select count(distinct p.supplier_id), bool_and(coalesce(s.accepts_delivery,false))
    into v_parcels, v_all
    from public.order_items oi
    join public.products p on p.id=oi.product_id
    join public.suppliers s on s.id=p.supplier_id
    where oi.order_id=p_order_id;
  v_parcels := greatest(coalesce(v_parcels,1),1);
  if p_method='supplier' then
    if not coalesce(v_all,false) then raise exception 'supplier delivery unavailable'; end if;
    v_fee := coalesce(v_sup,25) * v_parcels;
  else
    v_fee := coalesce(v_oto,800) * v_parcels;
  end if;
  update public.orders set delivery_method=p_method, delivery_halalas=v_fee where id=p_order_id;
end $$;
revoke all on function public.set_order_delivery(uuid,text) from public, anon;
grant execute on function public.set_order_delivery(uuid,text) to authenticated;

-- Supplier toggles whether they deliver with their own couriers.
create or replace function public.supplier_set_accepts_delivery(p_supplier uuid, p_accepts boolean)
returns void language plpgsql security definer set search_path to '' as $$
declare v_user uuid:=auth.uid();
begin
  perform private.assert_account_session();
  if v_user is null then raise exception 'authenticated user required' using errcode='42501'; end if;
  update public.suppliers set accepts_delivery=coalesce(p_accepts,false)
   where id=p_supplier and owner_id=v_user and approval_status='approved';
  if not found then raise exception 'supplier not found' using errcode='42501'; end if;
end $$;
revoke all on function public.supplier_set_accepts_delivery(uuid,boolean) from public, anon;
grant execute on function public.supplier_set_accepts_delivery(uuid,boolean) to authenticated;
