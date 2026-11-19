-- Applied to production via MCP apply_migration; exported from session history for repo parity.
-- Admin RPCs are already guarded by private.is_platform_operator(), but there is
-- no reason for the anonymous role to reach them at all. Revoke anon EXECUTE on
-- every public.admin_* function (authenticated keeps it; the guard still blocks
-- non-operators). Reduces attack surface and clears the security advisor warning.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure::text as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'admin\_%'
  loop
    execute format('revoke execute on function %s from anon', r.sig);
    execute format('revoke execute on function %s from public', r.sig);
  end loop;
end $$;
