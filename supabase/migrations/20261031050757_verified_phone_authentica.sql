-- Either a verified email or a verified phone may identify a signed-in account.
-- Role tables, ownership checks and revocation checks remain authoritative.
create or replace function private.has_verified_session() returns boolean
language sql stable security definer set search_path='' as $$
 select (select auth.uid()) is not null and exists(
  select 1 from auth.users u join auth.sessions s on s.user_id=u.id
  where u.id=(select auth.uid())
   and (u.email_confirmed_at is not null or (
     u.phone_confirmed_at is not null and u.phone ~ '^[+]?[1-9][0-9]{7,14}$'
   ))
   and not coalesce(u.is_anonymous,false) and u.deleted_at is null
   and (u.banned_until is null or u.banned_until<=now())
   and s.id=case when (auth.jwt()->>'session_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (auth.jwt()->>'session_id')::uuid else null end
 )
$$;
revoke all on function private.has_verified_session() from public,anon;
grant execute on function private.has_verified_session() to authenticated;
