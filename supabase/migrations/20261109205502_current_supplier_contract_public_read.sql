-- Applied to production via MCP apply_migration; exported from session history for repo parity.
create or replace function public.current_supplier_contract()
returns table(version_id text, body_ar text, body_sha256 text, published_at timestamptz)
language sql stable security definer set search_path to '' as $$
  select v.version_id, v.body_ar, v.body_sha256, v.published_at
  from public.supplier_contract_versions v
  where v.is_current = true and v.published = true
  order by v.published_at desc nulls last
  limit 1
$$;

revoke all on function public.current_supplier_contract() from public;
grant execute on function public.current_supplier_contract() to anon, authenticated;
