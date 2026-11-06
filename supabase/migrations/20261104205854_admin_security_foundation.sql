-- Additive administration foundation. No account, password or privilege is seeded.
-- A populated legacy operator registry requires an explicit migration/review first.
do $$begin
 if exists(select 1 from private.platform_operators) then
  raise exception 'review existing platform operators before enabling mandatory admin MFA';
 end if;
end $$;

create table public.admin_profiles (
 user_id uuid primary key references auth.users(id),
 role text not null check(role in ('super_admin','staff')),
 status text not null default 'active' check(status in ('active','suspended')),
 permissions text[] not null default '{}' check(permissions <@ array[
  'dashboard.read','suppliers.manage','buyers.manage','catalog.manage','orders.manage',
  'finance.read','contracts.read','support.manage','notifications.manage','reports.read','audit.read']::text[]),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
-- Suspension does not silently allow the creation of a second principal owner.
create unique index one_super_admin on public.admin_profiles((role)) where role='super_admin';
create table public.admin_audit_logs (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references auth.users(id),
 action text not null check(length(action) between 1 and 100),
 entity_type text not null check(length(entity_type) between 1 and 100),
 entity_id text,
 changed_fields text[] not null default '{}',
 created_at timestamptz not null default now()
);
create index admin_audit_logs_created on public.admin_audit_logs(created_at desc,id);
create index admin_audit_logs_actor on public.admin_audit_logs(actor_id,created_at desc);
alter table public.admin_profiles enable row level security;
alter table public.admin_audit_logs enable row level security;
revoke all on public.admin_profiles,public.admin_audit_logs from public,anon,authenticated,service_role;
grant select on public.admin_profiles,public.admin_audit_logs to authenticated;

-- Auth owns these facts. Display metadata and caller-supplied phone numbers grant nothing.
create function private.admin_identity_verified(p_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users u where u.id=p_user
  and nullif(btrim(u.email),'') is not null and u.email_confirmed_at is not null
  and u.phone ~ '^[+]?[1-9][0-9]{7,14}$' and u.phone_confirmed_at is not null
  and nullif(u.encrypted_password,'') is not null
  and not coalesce(u.is_anonymous,false) and u.deleted_at is null
  and (u.banned_until is null or u.banned_until<=now()))
$$;
create function private.admin_mfa_session() returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(private.has_verified_session() and private.admin_identity_verified((select auth.uid()))
  and (select auth.jwt()->>'aal')='aal2'
  and (select auth.jwt()->'amr') @> '[{"method":"password"}]'::jsonb
  and exists(select 1 from auth.sessions s join auth.mfa_factors f on f.id=s.factor_id and f.user_id=s.user_id
   where s.user_id=(select auth.uid()) and s.id::text=(select auth.jwt()->>'session_id')
    and s.aal::text='aal2' and (s.not_after is null or s.not_after>now())
    and f.status::text='verified' and f.factor_type::text='totp'
    and exists(select 1 from auth.mfa_amr_claims m where m.session_id=s.id and m.authentication_method='password')),false)
$$;
create function private.admin_has_permission(p_permission text) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce(private.admin_mfa_session() and exists(select 1 from public.admin_profiles p
  where p.user_id=(select auth.uid()) and p.status='active'
   and (p.role='super_admin' or p_permission=any(p.permissions))),false)
$$;
-- Old broad administration RPCs remain principal-owner-only. A staff permission
-- cannot accidentally inherit every legacy finance/order/security operation.
create or replace function private.is_platform_operator() returns boolean
language sql stable security definer set search_path='' as $$
 select private.admin_has_permission('legacy.full') and exists(
  select 1 from private.platform_operators o join public.admin_profiles p on p.user_id=o.user_id
  where o.user_id=(select auth.uid()) and p.role='super_admin' and p.status='active')
$$;
create policy admin_profiles_read on public.admin_profiles for select to authenticated
 using ((user_id=(select auth.uid()) and (select private.admin_mfa_session()))
  or (select private.is_platform_operator()));
create policy admin_audit_read on public.admin_audit_logs for select to authenticated
 using ((select private.admin_has_permission('audit.read')));

create function private.admin_audit_immutable() returns trigger
language plpgsql set search_path='' as $$begin
 raise exception 'admin audit is append only' using errcode='42501';
end $$;
create trigger admin_audit_immutable before update or delete on public.admin_audit_logs
 for each row execute function private.admin_audit_immutable();
create function private.audit_admin_change() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_old jsonb;v_new jsonb;v_fields text[];v_actor uuid:=auth.uid();begin
 if not private.admin_mfa_session() or not exists(select 1 from public.admin_profiles where user_id=v_actor and status='active') then
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
do $$declare v_table text;begin
 foreach v_table in array array['admin_profiles','suppliers','seller_applications','products','orders','checkout_services','loyalty_settings','shipments','supplier_contract_versions'] loop
  execute format('create trigger audit_admin_change after insert or update or delete on public.%I for each row execute function private.audit_admin_change()',v_table);
 end loop;
end $$;

create function private.my_admin_session() returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce((select jsonb_build_object('authorized',true,'role',p.role,'permissions',p.permissions)
  from public.admin_profiles p where p.user_id=(select auth.uid()) and p.status='active' and private.admin_mfa_session()),
  '{"authorized":false}'::jsonb)
$$;
create function private.admin_staff_profiles() returns setof public.admin_profiles
language plpgsql stable security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501';end if;
 return query select * from public.admin_profiles order by created_at,user_id;
end $$;
create function private.set_admin_staff(p_user_id uuid,p_status text,p_permissions text[]) returns void
language plpgsql security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501';end if;
 if p_user_id=auth.uid() then raise exception 'principal owner cannot self-reassign through staff API' using errcode='42501';end if;
 if p_user_id is null or p_status is null or p_status not in ('active','suspended')
  or p_permissions is null then raise exception 'invalid staff assignment';end if;
 perform pg_advisory_xact_lock(hashtextextended('admin-profile:'||p_user_id::text,0));
 if exists(select 1 from public.admin_profiles where user_id=p_user_id and role='super_admin') then
  raise exception 'principal owner cannot be changed by staff assignment' using errcode='42501';end if;
 if p_status='active' and (not private.admin_identity_verified(p_user_id) or not exists(
  select 1 from auth.mfa_factors where user_id=p_user_id and status::text='verified' and factor_type::text='totp')) then
  raise exception 'verified staff identity and TOTP required' using errcode='42501';end if;
 insert into public.admin_profiles(user_id,role,status,permissions) values(p_user_id,'staff',p_status,p_permissions)
 on conflict(user_id) do update set status=excluded.status,permissions=excluded.permissions,updated_at=now();
end $$;
create function private.admin_audit_page(p_before timestamptz default null) returns setof public.admin_audit_logs
language plpgsql stable security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if not private.admin_has_permission('audit.read') then raise exception 'permission denied' using errcode='42501';end if;
 return query select * from public.admin_audit_logs where p_before is null or created_at<p_before order by created_at desc,id limit 100;
end $$;
create function private.my_admin_sessions() returns table(id uuid,created_at timestamptz,is_current boolean)
language plpgsql stable security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if not private.admin_has_permission('dashboard.read') then raise exception 'permission denied' using errcode='42501';end if;
 return query select s.id,s.created_at,s.id::text=(auth.jwt()->>'session_id') from auth.sessions s where s.user_id=auth.uid() order by s.created_at desc;
end $$;
create function private.revoke_my_admin_session(p_session_id uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if not private.admin_has_permission('dashboard.read') then raise exception 'permission denied' using errcode='42501';end if;
 delete from auth.sessions where id=p_session_id and user_id=auth.uid();
 if found then insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id)
  values(auth.uid(),'session.revoked','auth.sessions',p_session_id::text);end if;
end $$;

-- Operator-only bootstrap; deliberately unavailable to anon/authenticated/service_role.
-- Call only through the authorized control plane after owner-approved contact match
-- and an actual verified password + TOTP session. No data is seeded by this migration.
create function private.provision_verified_super_admin(p_user_id uuid,p_expected_email text,p_expected_phone text,p_session_id uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 perform pg_advisory_xact_lock(hashtextextended('riwa-single-super-admin',0));
 if p_expected_email is null or p_expected_phone is null or not private.admin_identity_verified(p_user_id)
  or not exists(select 1 from auth.users where id=p_user_id and lower(email)=lower(btrim(p_expected_email)) and ltrim(phone,'+')=ltrim(p_expected_phone,'+'))
  or not exists(select 1 from auth.sessions s join auth.mfa_factors f on f.id=s.factor_id and f.user_id=s.user_id
   where s.id=p_session_id and s.user_id=p_user_id and s.aal::text='aal2' and (s.not_after is null or s.not_after>now())
    and f.status::text='verified' and f.factor_type::text='totp'
    and exists(select 1 from auth.mfa_amr_claims m where m.session_id=s.id and m.authentication_method='password')) then
  raise exception 'verified owner identity, contact match and TOTP session required' using errcode='42501';end if;
 if exists(select 1 from public.admin_profiles where role='super_admin') then raise exception 'principal owner already provisioned';end if;
 insert into public.admin_profiles(user_id,role) values(p_user_id,'super_admin');
 insert into private.platform_operators(user_id) values(p_user_id);
 insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id)
  values(p_user_id,'super_admin.provisioned','admin_profiles',p_user_id::text);
end $$;

create function public.my_admin_session() returns jsonb language sql security invoker set search_path='' as $$select private.my_admin_session()$$;
create function public.admin_staff_profiles() returns setof public.admin_profiles language sql security invoker set search_path='' as $$select * from private.admin_staff_profiles()$$;
create function public.set_admin_staff(p_user_id uuid,p_status text,p_permissions text[]) returns void language sql security invoker set search_path='' as $$select private.set_admin_staff(p_user_id,p_status,p_permissions)$$;
create function public.admin_audit_page(p_before timestamptz default null) returns setof public.admin_audit_logs language sql security invoker set search_path='' as $$select * from private.admin_audit_page(p_before)$$;
create function public.my_admin_sessions() returns table(id uuid,created_at timestamptz,is_current boolean) language sql security invoker set search_path='' as $$select * from private.my_admin_sessions()$$;
create function public.revoke_my_admin_session(p_session_id uuid) returns void language sql security invoker set search_path='' as $$select private.revoke_my_admin_session(p_session_id)$$;

revoke all on function private.admin_identity_verified(uuid),private.admin_mfa_session(),private.admin_has_permission(text),private.audit_admin_change(),private.admin_audit_immutable(),private.provision_verified_super_admin(uuid,text,text,uuid) from public,anon,authenticated,service_role;
grant execute on function private.admin_mfa_session(),private.admin_has_permission(text) to authenticated;
revoke all on function private.my_admin_session(),private.admin_staff_profiles(),private.set_admin_staff(uuid,text,text[]),private.admin_audit_page(timestamptz),private.my_admin_sessions(),private.revoke_my_admin_session(uuid) from public,anon,authenticated,service_role;
revoke all on function public.my_admin_session(),public.admin_staff_profiles(),public.set_admin_staff(uuid,text,text[]),public.admin_audit_page(timestamptz),public.my_admin_sessions(),public.revoke_my_admin_session(uuid) from public,anon,authenticated,service_role;
grant execute on function private.my_admin_session(),private.admin_staff_profiles(),private.set_admin_staff(uuid,text,text[]),private.admin_audit_page(timestamptz),private.my_admin_sessions(),private.revoke_my_admin_session(uuid) to authenticated;
grant execute on function public.my_admin_session(),public.admin_staff_profiles(),public.set_admin_staff(uuid,text,text[]),public.admin_audit_page(timestamptz),public.my_admin_sessions(),public.revoke_my_admin_session(uuid) to authenticated;
