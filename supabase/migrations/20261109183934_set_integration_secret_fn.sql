-- Applied to production via MCP apply_migration; exported from session history for repo parity.
create or replace function public.set_integration_secret(p_name text, p_value text)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if (select auth.role()) <> 'service_role' then
    raise exception 'forbidden' using errcode='42501';
  end if;
  insert into private.integrations(name, value) values (p_name, p_value)
  on conflict (name) do update set value = excluded.value, updated_at = now();
end $$;
revoke execute on function public.set_integration_secret(text,text) from anon, public, authenticated;
grant execute on function public.set_integration_secret(text,text) to service_role;
