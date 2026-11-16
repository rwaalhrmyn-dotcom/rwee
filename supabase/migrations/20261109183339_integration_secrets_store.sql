-- Applied to production via MCP apply_migration; exported from session history for repo parity.
-- Server-side secret store for third-party integrations (OTO, ...).
-- Lives in the private schema (not exposed through the API; RLS denies all direct access).
create table if not exists private.integrations (
  name text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);
alter table private.integrations enable row level security;

-- Readable only by the service role (edge functions) or a platform operator.
create or replace function public.get_integration_secret(p_name text)
returns text language plpgsql stable security definer set search_path to '' as $$
begin
  if (select auth.role()) <> 'service_role' and not private.is_platform_operator() then
    raise exception 'forbidden' using errcode='42501';
  end if;
  return (select value from private.integrations where name = p_name);
end $$;
revoke execute on function public.get_integration_secret(text) from anon, public;
grant execute on function public.get_integration_secret(text) to service_role;
