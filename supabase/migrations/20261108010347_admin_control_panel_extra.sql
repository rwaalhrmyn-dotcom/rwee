-- Applied to production via MCP apply_migration; exported from session history for repo parity.
-- audit helper
create or replace function private.admin_log(p_action text, p_entity text, p_entity_id text)
returns void language sql security definer set search_path to '' as $$
  insert into public.admin_audit_logs(actor_id, action, entity_type, entity_id)
  values (auth.uid(), p_action, p_entity, p_entity_id);
$$;

-- Customers
create or replace function public.admin_customers()
returns table(id uuid, full_name text, phone text, city text, email text, orders bigint, created_at timestamptz)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select p.id, p.full_name, p.phone, p.city,
      (select u.email from auth.users u where u.id=p.id),
      (select count(*) from public.orders o where o.customer_id=p.id),
      p.created_at
    from public.profiles p order by p.created_at desc limit 1000;
end $$;

-- Deliveries
create or replace function public.admin_deliveries()
returns table(id uuid, order_id uuid, status text, recipient_name text, city text, created_at timestamptz, reviewed_at timestamptz)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select d.id, d.order_id, d.status,
      (select o.recipient_name from public.orders o where o.id=d.order_id),
      (select o.city from public.orders o where o.id=d.order_id),
      d.created_at, d.reviewed_at
    from public.deliveries d order by d.created_at desc limit 500;
end $$;

create or replace function public.admin_set_delivery_status(p_id uuid, p_status text)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_status not in ('scheduled','submitted','approved','changes_requested') then raise exception 'invalid status'; end if;
  update public.deliveries set status=p_status,
    reviewed_at = case when p_status in ('approved','changes_requested') then now() else reviewed_at end,
    reviewer_id = case when p_status in ('approved','changes_requested') then auth.uid() else reviewer_id end
  where id=p_id;
  if not found then raise exception 'delivery not found'; end if;
  perform private.admin_log('delivery_status:'||p_status,'delivery',p_id::text);
end $$;

-- Staff / admins
create or replace function public.admin_staff()
returns table(user_id uuid, email text, role text, status text, login_mode text, is_operator boolean, created_at timestamptz)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select a.user_id, (select u.email from auth.users u where u.id=a.user_id), a.role, a.status, a.login_mode,
      exists(select 1 from private.platform_operators o where o.user_id=a.user_id), a.created_at
    from public.admin_profiles a order by a.created_at;
end $$;

create or replace function public.admin_add_staff(p_email text)
returns text language plpgsql security definer set search_path to '' as $$
declare v_uid uuid; v_has_pw boolean; v_conf boolean;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select id, nullif(btrim(encrypted_password),'') is not null, email_confirmed_at is not null
    into v_uid, v_has_pw, v_conf
    from auth.users where lower(email)=lower(btrim(p_email)) limit 1;
  if v_uid is null then raise exception 'لا يوجد حساب بهذا البريد. يسجّل صاحبه الدخول أولاً بكلمة مرور.'; end if;
  if not v_has_pw or not v_conf then raise exception 'الحساب يحتاج بريداً مؤكداً وكلمة مرور قبل منحه صلاحية الإدارة.'; end if;
  insert into public.admin_profiles(user_id, role, status, permissions, login_mode)
  values (v_uid,'super_admin','active','{}'::text[],'password')
  on conflict (user_id) do update set role='super_admin', status='active', login_mode='password', updated_at=now();
  insert into private.platform_operators(user_id) values (v_uid) on conflict do nothing;
  perform private.admin_log('staff_add','admin',v_uid::text);
  return v_uid::text;
end $$;

create or replace function public.admin_remove_staff(p_user_id uuid)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_user_id = auth.uid() then raise exception 'لا يمكنك إزالة نفسك.'; end if;
  delete from private.platform_operators where user_id=p_user_id;
  update public.admin_profiles set status='suspended', updated_at=now() where user_id=p_user_id;
  perform private.admin_log('staff_remove','admin',p_user_id::text);
end $$;

-- Audit log
create or replace function public.admin_audit(p_limit integer default 100)
returns table(action text, entity_type text, entity_id text, actor_email text, created_at timestamptz)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select l.action, l.entity_type, l.entity_id,
      (select u.email from auth.users u where u.id=l.actor_id), l.created_at
    from public.admin_audit_logs l order by l.created_at desc limit least(coalesce(p_limit,100),500);
end $$;

-- Create product (attached to the platform supplier)
create or replace function public.admin_create_product(
  p_name text, p_category text, p_unit text, p_price_halalas integer, p_stock integer, p_description text default '')
returns uuid language plpgsql security definer set search_path to '' as $$
declare v_id uuid; v_sup uuid;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if length(btrim(coalesce(p_name,'')))<2 then raise exception 'اسم غير صالح'; end if;
  if p_category not in ('water','quran','supplies','food','equipment') then raise exception 'فئة غير صالحة'; end if;
  if p_price_halalas is null or p_price_halalas<1 or p_price_halalas>100000000 then raise exception 'سعر غير صالح'; end if;
  if p_stock is null or p_stock<0 or p_stock>1000000 then raise exception 'مخزون غير صالح'; end if;
  select id into v_sup from public.suppliers where approval_status='approved' order by created_at limit 1;
  insert into public.products(name,description,category,price_halalas,stock,unit,cities,active,supplier_id)
  values (btrim(p_name), coalesce(nullif(btrim(p_description),''),'-'), p_category, p_price_halalas, p_stock,
    coalesce(nullif(btrim(p_unit),''),'حبة'), array['makkah','madinah'], true, v_sup)
  returning id into v_id;
  perform private.admin_log('product_create','product',v_id::text);
  return v_id;
end $$;

-- Checkout services (name printing, delivery, ...)
create or replace function public.admin_set_service(p_code text, p_price_halalas integer, p_active boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_price_halalas is not null and (p_price_halalas<0 or p_price_halalas>100000000) then raise exception 'سعر غير صالح'; end if;
  update public.checkout_services set
    price_halalas=coalesce(p_price_halalas,price_halalas),
    active=coalesce(p_active,active)
  where code=p_code;
  if not found then raise exception 'service not found'; end if;
  perform private.admin_log('service_update','service',p_code);
end $$;

grant execute on function public.admin_customers() to authenticated;
grant execute on function public.admin_deliveries() to authenticated;
grant execute on function public.admin_set_delivery_status(uuid,text) to authenticated;
grant execute on function public.admin_staff() to authenticated;
grant execute on function public.admin_add_staff(text) to authenticated;
grant execute on function public.admin_remove_staff(uuid) to authenticated;
grant execute on function public.admin_audit(integer) to authenticated;
grant execute on function public.admin_create_product(text,text,text,integer,integer,text) to authenticated;
grant execute on function public.admin_set_service(text,integer,boolean) to authenticated;
