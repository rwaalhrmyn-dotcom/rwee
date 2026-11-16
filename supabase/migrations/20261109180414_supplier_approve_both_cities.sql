-- Applied to production via MCP apply_migration; exported from session history for repo parity.
-- When approving a supplier, grant full platform coverage (both Haramain cities)
-- so product entry and Excel imports are not blocked by a single registered city.
create or replace function public.admin_decide_application(p_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path to '' as $$
declare v_app public.seller_applications%rowtype;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into v_app from public.seller_applications where id=p_id for update;
  if not found then raise exception 'application not found'; end if;
  if p_approve then
    update public.seller_applications set status='approved' where id=p_id;
    if not exists(select 1 from public.suppliers s where s.owner_id=v_app.owner_id and s.name=v_app.business_name) then
      insert into public.suppliers(owner_id,name,cities,approval_status)
      values(v_app.owner_id, v_app.business_name, array['makkah','madinah'], 'approved');
    else
      update public.suppliers set approval_status='approved', cities=array['makkah','madinah']
        where owner_id=v_app.owner_id and name=v_app.business_name;
    end if;
  else
    update public.seller_applications set status='rejected' where id=p_id;
  end if;
end $$;
