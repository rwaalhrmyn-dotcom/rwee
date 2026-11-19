-- Applied to production via MCP apply_migration; exported from session history for repo parity.
create or replace function public.admin_customers()
returns table(id uuid, full_name text, phone text, city text, email text, orders bigint, created_at timestamptz)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select p.id, p.full_name, p.phone, p.city,
      (select u.email::text from auth.users u where u.id=p.id),
      (select count(*) from public.orders o where o.customer_id=p.id),
      p.created_at
    from public.profiles p order by p.created_at desc limit 1000;
end $$;

create or replace function public.admin_staff()
returns table(user_id uuid, email text, role text, status text, login_mode text, is_operator boolean, created_at timestamptz)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select a.user_id, (select u.email::text from auth.users u where u.id=a.user_id), a.role, a.status, a.login_mode,
      exists(select 1 from private.platform_operators o where o.user_id=a.user_id), a.created_at
    from public.admin_profiles a order by a.created_at;
end $$;

create or replace function public.admin_audit(p_limit integer default 100)
returns table(action text, entity_type text, entity_id text, actor_email text, created_at timestamptz)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select l.action, l.entity_type, l.entity_id,
      (select u.email::text from auth.users u where u.id=l.actor_id), l.created_at
    from public.admin_audit_logs l order by l.created_at desc limit least(coalesce(p_limit,100),500);
end $$;

create or replace function public.admin_applications()
returns table(id uuid, created_at timestamptz, status text, business_name text,
  commercial_registration text, phone text, city text, category text, iban text,
  document_path text, owner_email text)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select a.id,a.created_at,a.status,a.business_name,a.commercial_registration,a.phone,a.city,a.category,a.iban,a.document_path,
      (select u.email::text from auth.users u where u.id=a.owner_id)
    from public.seller_applications a order by (a.status='pending') desc, a.created_at desc limit 500;
end $$;

create or replace function public.admin_suppliers()
returns table(id uuid, name text, cities text[], approval_status text, created_at timestamptz, owner_email text, products bigint)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select s.id,s.name,s.cities,s.approval_status,s.created_at,
      (select u.email::text from auth.users u where u.id=s.owner_id),
      (select count(*) from public.products p where p.supplier_id=s.id and not p.archived)
    from public.suppliers s order by s.created_at desc limit 500;
end $$;
