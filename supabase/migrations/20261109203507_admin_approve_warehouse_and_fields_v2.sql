-- Applied to production via MCP apply_migration; exported from session history for repo parity.
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
      insert into public.suppliers(owner_id,name,cities,approval_status,national_address,tax_number,warehouse_city)
      values(v_app.owner_id, v_app.business_name, array['makkah','madinah'], 'approved', v_app.national_address, v_app.tax_number, v_app.city)
      returning id into v_sup_id;
    else
      update public.suppliers set approval_status='approved', cities=array['makkah','madinah'],
        national_address=coalesce(v_app.national_address,national_address), tax_number=coalesce(v_app.tax_number,tax_number), warehouse_city=coalesce(v_app.city,warehouse_city)
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

drop function if exists public.admin_applications();
create function public.admin_applications()
returns table(id uuid, created_at timestamptz, status text, business_name text,
  commercial_registration text, phone text, email text, city text, category text, iban text,
  manager_name text, manager_title text, national_address text, tax_number text,
  document_path text, authorization_doc_path text, license_doc_path text, owner_email text)
language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select a.id,a.created_at,a.status,a.business_name,a.commercial_registration,a.phone,a.email,a.city,a.category,a.iban,
      a.manager_name,a.manager_title,a.national_address,a.tax_number,
      a.document_path,a.authorization_doc_path,a.license_doc_path,
      (select u.email::text from auth.users u where u.id=a.owner_id)
    from public.seller_applications a order by (a.status='pending') desc, a.created_at desc limit 500;
end $$;
grant execute on function public.admin_applications() to authenticated;
revoke execute on function public.admin_applications() from anon, public;
