-- Applied to production via MCP apply_migration; exported from session history for repo parity.
drop function if exists public.admin_applications();
create function public.admin_applications()
 returns table(id uuid, created_at timestamptz, status text, business_name text, commercial_registration text, phone text, email text, city text, category text, iban text, manager_name text, manager_title text, national_address text, tax_number text, document_path text, authorization_doc_path text, license_doc_path text, accepts_delivery boolean, owner_email text)
 language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query
    select a.id,a.created_at,a.status,a.business_name,a.commercial_registration,a.phone,a.email,a.city,a.category,a.iban,
      a.manager_name,a.manager_title,a.national_address,a.tax_number,
      a.document_path,a.authorization_doc_path,a.license_doc_path, coalesce(a.accepts_delivery,false),
      (select u.email::text from auth.users u where u.id=a.owner_id)
    from public.seller_applications a order by (a.status='pending') desc, a.created_at desc limit 500;
end $$;
revoke all on function public.admin_applications() from anon, public;
grant execute on function public.admin_applications() to authenticated;
