-- Applied to production via MCP apply_migration; exported from session history for repo parity.
-- Admin control-panel RPCs. All SECURITY DEFINER, guarded by is_platform_operator().

-- Dashboard metrics
create or replace function public.admin_metrics()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare r jsonb;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select jsonb_build_object(
    'orders_total', (select count(*) from public.orders),
    'orders_pending', (select count(*) from public.orders where status='pending'),
    'orders_paid', (select count(*) from public.orders where payment_status='paid'),
    'revenue_halalas', (select coalesce(sum(total_halalas),0) from public.orders where payment_status='paid'),
    'applications_pending', (select count(*) from public.seller_applications where status='pending'),
    'suppliers_approved', (select count(*) from public.suppliers where approval_status='approved'),
    'products_active', (select count(*) from public.products where active and not archived),
    'inquiries_open',
      (select count(*) from public.quote_requests where status='pending')
      + (select count(*) from public.subscription_requests where status='requested')
      + (select count(*) from public.facility_needs where status='open')
  ) into r;
  return r;
end $$;

-- Orders
create or replace function public.admin_orders(p_status text default null)
returns table(id uuid, created_at timestamptz, status text, payment_status text,
  recipient_name text, phone text, city text, address text, total_halalas bigint, items bigint)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select o.id,o.created_at,o.status,o.payment_status,o.recipient_name,o.phone,o.city,o.address,o.total_halalas,
      (select count(*) from public.order_items oi where oi.order_id=o.id)
    from public.orders o
    where p_status is null or o.status=p_status
    order by o.created_at desc limit 500;
end $$;

create or replace function public.admin_order_items(p_order_id uuid)
returns table(product_name text, quantity integer, unit_price_halalas integer)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select oi.product_name, oi.quantity, oi.unit_price_halalas
    from public.order_items oi where oi.order_id=p_order_id;
end $$;

create or replace function public.admin_set_order_status(p_order_id uuid, p_status text)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_status not in ('pending','confirmed','preparing','out_for_delivery','delivered','cancelled')
    then raise exception 'invalid status'; end if;
  update public.orders set status=p_status where id=p_order_id;
  if not found then raise exception 'order not found'; end if;
end $$;

create or replace function public.admin_set_order_paid(p_order_id uuid, p_paid boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_paid then
    update public.orders set payment_status='paid', paid_at=coalesce(paid_at,now()) where id=p_order_id;
  else
    update public.orders set payment_status='unpaid', paid_at=null where id=p_order_id;
  end if;
  if not found then raise exception 'order not found'; end if;
end $$;

-- Supplier applications
create or replace function public.admin_applications()
returns table(id uuid, created_at timestamptz, status text, business_name text,
  commercial_registration text, phone text, city text, category text, iban text,
  document_path text, owner_email text)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select a.id,a.created_at,a.status,a.business_name,a.commercial_registration,a.phone,a.city,a.category,a.iban,a.document_path,
      (select u.email from auth.users u where u.id=a.owner_id)
    from public.seller_applications a order by (a.status='pending') desc, a.created_at desc limit 500;
end $$;

create or replace function public.admin_decide_application(p_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path to '' as $$
declare v_app public.seller_applications%rowtype;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into v_app from public.seller_applications where id=p_id for update;
  if not found then raise exception 'application not found'; end if;
  if p_approve then
    update public.seller_applications set status='approved' where id=p_id;
    -- create an approved supplier for the owner if they do not already have one by this name
    if not exists(select 1 from public.suppliers s where s.owner_id=v_app.owner_id and s.name=v_app.business_name) then
      insert into public.suppliers(owner_id,name,cities,approval_status)
      values(v_app.owner_id, v_app.business_name, array[v_app.city], 'approved');
    else
      update public.suppliers set approval_status='approved'
        where owner_id=v_app.owner_id and name=v_app.business_name;
    end if;
  else
    update public.seller_applications set status='rejected' where id=p_id;
  end if;
end $$;

-- Suppliers
create or replace function public.admin_suppliers()
returns table(id uuid, name text, cities text[], approval_status text, created_at timestamptz, owner_email text, products bigint)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select s.id,s.name,s.cities,s.approval_status,s.created_at,
      (select u.email from auth.users u where u.id=s.owner_id),
      (select count(*) from public.products p where p.supplier_id=s.id and not p.archived)
    from public.suppliers s order by s.created_at desc limit 500;
end $$;

create or replace function public.admin_set_supplier_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_status not in ('pending','approved','blocked') then raise exception 'invalid status'; end if;
  update public.suppliers set approval_status=p_status where id=p_id;
  if not found then raise exception 'supplier not found'; end if;
end $$;

-- Products (full control incl. price)
create or replace function public.admin_products()
returns table(id uuid, name text, category text, price_halalas integer, supplier_price_halalas integer,
  stock integer, unit text, active boolean, featured boolean, archived boolean, supplier_name text)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select p.id,p.name,p.category,p.price_halalas,p.supplier_price_halalas,p.stock,p.unit,p.active,p.featured,p.archived,
      (select s.name from public.suppliers s where s.id=p.supplier_id)
    from public.products p order by p.created_at desc limit 1000;
end $$;

create or replace function public.admin_update_product(
  p_id uuid, p_price_halalas integer, p_stock integer, p_active boolean, p_featured boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_price_halalas is not null and (p_price_halalas < 1 or p_price_halalas > 100000000) then raise exception 'invalid price'; end if;
  if p_stock is not null and (p_stock < 0 or p_stock > 1000000) then raise exception 'invalid stock'; end if;
  update public.products set
    price_halalas = coalesce(p_price_halalas, price_halalas),
    stock = coalesce(p_stock, stock),
    active = coalesce(p_active, active),
    featured = coalesce(p_featured, featured),
    inventory_version = inventory_version + 1
  where id=p_id;
  if not found then raise exception 'product not found'; end if;
end $$;

create or replace function public.admin_set_product_archived(p_id uuid, p_archived boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  update public.products set archived=p_archived, active = case when p_archived then false else active end,
    inventory_version = inventory_version + 1 where id=p_id;
  if not found then raise exception 'product not found'; end if;
end $$;

-- Inquiries (quotes + subscriptions + facility needs)
create or replace function public.admin_inquiries()
returns table(kind text, id uuid, created_at timestamptz, status text, title text, detail text, city text, phone text)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select 'quote'::text, q.id, q.created_at, q.status, q.organization_name, q.details, q.city, q.contact_phone
      from public.quote_requests q
    union all
    select 'subscription'::text, s.id, s.created_at, s.status, ('توريد دوري: '||coalesce(s.frequency,'')), s.details, s.city, null::text
      from public.subscription_requests s
    union all
    select 'need'::text, n.id, n.created_at, n.status, n.facility_name, n.description, n.city, null::text
      from public.facility_needs n
    order by created_at desc limit 500;
end $$;

create or replace function public.admin_set_inquiry_status(p_kind text, p_id uuid, p_status text)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_kind='quote' then
    if p_status not in ('pending','contacted','closed') then raise exception 'invalid status'; end if;
    update public.quote_requests set status=p_status where id=p_id;
  elsif p_kind='subscription' then
    if p_status not in ('requested','contacted','closed') then raise exception 'invalid status'; end if;
    update public.subscription_requests set status=p_status where id=p_id;
  elsif p_kind='need' then
    if p_status not in ('open','fulfilled') then raise exception 'invalid status'; end if;
    update public.facility_needs set status=p_status where id=p_id;
  else
    raise exception 'invalid kind';
  end if;
  if not found then raise exception 'inquiry not found'; end if;
end $$;

-- Settings (loyalty + delivery fee)
create or replace function public.admin_settings()
returns jsonb language plpgsql security definer set search_path to '' as $$
declare r jsonb;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select jsonb_build_object(
    'loyalty_enabled', (select enabled from public.loyalty_settings limit 1),
    'delivery_halalas', (select price_halalas from public.checkout_services where code='delivery' limit 1),
    'services', (select coalesce(jsonb_agg(jsonb_build_object('code',code,'price_halalas',price_halalas,'active',active) order by code),'[]'::jsonb) from public.checkout_services)
  ) into r;
  return r;
end $$;

create or replace function public.admin_update_settings(p_loyalty_enabled boolean, p_delivery_halalas integer)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_loyalty_enabled is not null then
    update public.loyalty_settings set enabled=p_loyalty_enabled;
  end if;
  if p_delivery_halalas is not null then
    if p_delivery_halalas < 0 or p_delivery_halalas > 100000000 then raise exception 'invalid delivery fee'; end if;
    update public.checkout_services set price_halalas=p_delivery_halalas where code='delivery';
  end if;
end $$;

grant execute on function public.admin_metrics() to authenticated;
grant execute on function public.admin_orders(text) to authenticated;
grant execute on function public.admin_order_items(uuid) to authenticated;
grant execute on function public.admin_set_order_status(uuid,text) to authenticated;
grant execute on function public.admin_set_order_paid(uuid,boolean) to authenticated;
grant execute on function public.admin_applications() to authenticated;
grant execute on function public.admin_decide_application(uuid,boolean) to authenticated;
grant execute on function public.admin_suppliers() to authenticated;
grant execute on function public.admin_set_supplier_status(uuid,text) to authenticated;
grant execute on function public.admin_products() to authenticated;
grant execute on function public.admin_update_product(uuid,integer,integer,boolean,boolean) to authenticated;
grant execute on function public.admin_set_product_archived(uuid,boolean) to authenticated;
grant execute on function public.admin_inquiries() to authenticated;
grant execute on function public.admin_set_inquiry_status(text,uuid,text) to authenticated;
grant execute on function public.admin_settings() to authenticated;
grant execute on function public.admin_update_settings(boolean,integer) to authenticated;
