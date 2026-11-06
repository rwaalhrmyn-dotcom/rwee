-- The owner now requests password login without OTP. Keep legacy/staff MFA as
-- the default; only a trusted control-plane action can select password-only
-- for the single verified principal. This migration provisions no account.
alter table public.admin_profiles add column login_mode text not null default 'password_totp'
 check(login_mode in ('password','password_totp'));
alter table public.admin_profiles add constraint password_login_principal_only
 check(login_mode<>'password' or role='super_admin');

-- The requested password principal uses verified email as the username. A
-- mobile contact is not an authentication factor or an ownership substitute.
create function private.admin_password_identity_verified(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u where u.id=p_user
  and nullif(btrim(u.email),'') is not null and u.email_confirmed_at is not null
  and nullif(u.encrypted_password,'') is not null and not coalesce(u.is_anonymous,false)
  and u.deleted_at is null and (u.banned_until is null or u.banned_until<=now()))
$$;
create function private.admin_password_session() returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(private.has_verified_session() and private.admin_password_identity_verified((select auth.uid()))
  and (select auth.jwt()->'amr') @> '[{"method":"password"}]'::jsonb
  and exists(select 1 from auth.sessions s where s.user_id=(select auth.uid())
   and s.id::text=(select auth.jwt()->>'session_id') and (s.not_after is null or s.not_after>now())
   and exists(select 1 from auth.mfa_amr_claims m where m.session_id=s.id and m.authentication_method='password')),false)
$$;
create function private.admin_authorized_session() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.admin_profiles p where p.user_id=(select auth.uid()) and p.status='active'
  and case when p.login_mode='password' and p.role='super_admin'
   then private.admin_password_session() else private.admin_mfa_session() end)
$$;
create or replace function private.admin_has_permission(p_permission text) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(private.admin_authorized_session() and exists(select 1 from public.admin_profiles p
  where p.user_id=(select auth.uid()) and p.status='active'
   and (p.role='super_admin' or p_permission=any(p.permissions))),false)
$$;
alter policy admin_profiles_read on public.admin_profiles using (
 (user_id=(select auth.uid()) and (select private.admin_authorized_session()))
 or (select private.is_platform_operator()));

create or replace function private.my_admin_session() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce((select case when private.admin_authorized_session() then
  jsonb_build_object('authorized',true,'role',p.role,'permissions',p.permissions,'login_mode',p.login_mode,'mfa_required',p.login_mode='password_totp')
  else jsonb_build_object('authorized',false,'mfa_required',p.login_mode='password_totp' and private.admin_password_session()) end
  from public.admin_profiles p where p.user_id=(select auth.uid()) and p.status='active'),
  '{"authorized":false,"mfa_required":false}'::jsonb)
$$;

create or replace function private.audit_admin_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_old jsonb;v_new jsonb;v_fields text[];v_actor uuid:=auth.uid();begin
 if not private.admin_authorized_session() then
  if TG_OP='DELETE' then return old;else return new;end if;
 end if;
 if TG_OP<>'INSERT' then v_old:=to_jsonb(old);end if;
 if TG_OP<>'DELETE' then v_new:=to_jsonb(new);end if;
 select coalesce(array_agg(key order by key),'{}') into v_fields from jsonb_object_keys(coalesce(v_new,v_old)) key
  where (v_old->key) is distinct from (v_new->key);
 insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,changed_fields)
 values(v_actor,lower(TG_OP),TG_TABLE_NAME,coalesce(v_new->>'id',v_old->>'id',v_new->>'user_id',v_old->>'user_id',v_new->>'code',v_old->>'code'),v_fields);
 if TG_OP='DELETE' then return old;else return new;end if;
end $$;

-- No public endpoint can create or downgrade an admin. The control plane must
-- independently verify the owner's selected Auth identity and email ownership.
-- Password verification is performed by Auth, proved by its live session and
-- password AMR record, never by comparing a password inside this function.
create function private.provision_verified_password_admin(p_user_id uuid,p_expected_email text,p_session_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_owner public.admin_profiles%rowtype;v_new boolean;begin
 perform pg_advisory_xact_lock(hashtextextended('riwa-single-super-admin',0));
 if p_expected_email is null or not private.admin_password_identity_verified(p_user_id)
  or not exists(select 1 from auth.users where id=p_user_id and lower(email)=lower(btrim(p_expected_email)))
  or not exists(select 1 from auth.sessions s where s.id=p_session_id and s.user_id=p_user_id
   and (s.not_after is null or s.not_after>now()) and exists(select 1 from auth.mfa_amr_claims m
    where m.session_id=s.id and m.authentication_method='password')) then
  raise exception 'verified owner identity, matching email and password session required' using errcode='42501';end if;
 select * into v_owner from public.admin_profiles where role='super_admin' for update;
 v_new:=not found;
 if not v_new and (v_owner.user_id<>p_user_id or v_owner.status<>'active') then
  raise exception 'existing principal identity and status require review' using errcode='42501';end if;
 if v_new then
  if exists(select 1 from public.admin_profiles where user_id=p_user_id) or exists(select 1 from private.platform_operators) then
   raise exception 'review existing administrative registry before provisioning' using errcode='42501';end if;
  insert into public.admin_profiles(user_id,role,login_mode) values(p_user_id,'super_admin','password');
 else
  update public.admin_profiles set login_mode='password',updated_at=now() where user_id=p_user_id;
 end if;
 insert into private.platform_operators(user_id) values(p_user_id) on conflict(user_id) do nothing;
 insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,changed_fields)
 values(p_user_id,case when v_new then 'super_admin.password_login_provisioned' else 'super_admin.login_policy_reviewed' end,'admin_profiles',p_user_id::text,array['login_mode']);
end $$;

revoke all on function private.admin_password_identity_verified(uuid),private.admin_password_session(),private.admin_authorized_session(),private.provision_verified_password_admin(uuid,text,uuid) from public,anon,authenticated,service_role;
grant execute on function private.admin_authorized_session() to authenticated;
