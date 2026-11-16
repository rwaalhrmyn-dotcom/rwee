-- Supplier payment settings ("إعدادات الدفع واستلام المستحقات"), gateway credentials,
-- sensitive-change approvals, contract consent at registration, and selling eligibility.
-- Gateway secret keys are encrypted by the Edge Function (AES-GCM, key held only in
-- the function environment) before they reach the database; the database never sees
-- plaintext keys and no API role can read the ciphertext.

alter table public.seller_applications add column if not exists entity_type text check (entity_type in ('factory','distributor','trader'));
alter table public.seller_applications add column if not exists account_holder_name text;
alter table public.seller_applications add column if not exists bank_name text;

create table if not exists public.supplier_payment_profiles (
  supplier_id uuid primary key references public.suppliers(id),
  entity_type text check (entity_type in ('factory','distributor','trader')),
  legal_name text check (legal_name is null or length(btrim(legal_name)) between 2 and 200),
  cr_number text check (cr_number is null or cr_number ~ '^[0-9]{10}$'),
  account_holder_name text check (account_holder_name is null or length(btrim(account_holder_name)) between 2 and 200),
  bank_name text check (bank_name is null or length(btrim(bank_name)) between 2 and 120),
  iban text check (iban is null or iban ~ '^SA[0-9]{22}$'),
  iban_valid boolean generated always as (private.is_valid_sa_iban(iban)) stored,
  iban_bank_detected text generated always as (private.sa_bank_from_iban(iban)) stored,
  vat_registered boolean not null default false,
  tax_number text check (tax_number is null or private.is_valid_sa_vat(tax_number)),
  vat_certificate_path text,
  gateway_provider text check (gateway_provider in ('tap')),
  gateway_mode text check (gateway_mode in ('test','live')),
  gateway_merchant_id text check (gateway_merchant_id is null or length(gateway_merchant_id) <= 120),
  gateway_key_hint text check (gateway_key_hint is null or gateway_key_hint ~ '^[A-Za-z0-9_]{0,12}$'),
  gateway_check_status text not null default 'unchecked' check (gateway_check_status in ('unchecked','valid','invalid','unreachable')),
  gateway_checked_at timestamptz,
  gateway_connected_at timestamptz,
  status text not null default 'incomplete' check (status in ('incomplete','pending','active','suspended')),
  status_reason text,
  submitted_at timestamptz,
  verified_by uuid,
  verified_at timestamptz,
  suspended_by uuid,
  suspended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.supplier_payment_profiles enable row level security;
revoke all on public.supplier_payment_profiles from public, anon, authenticated;
grant select on public.supplier_payment_profiles to authenticated;
create policy payment_profile_read on public.supplier_payment_profiles for select to authenticated
  using (private.owns_supplier(supplier_id) or (select private.is_platform_operator()));
create policy verified_account_access on public.supplier_payment_profiles as restrictive for all to authenticated
  using ((select private.has_verified_session())) with check ((select private.has_verified_session()));

create table if not exists private.supplier_gateway_secrets (
  supplier_id uuid primary key references public.suppliers(id),
  provider text not null check (provider in ('tap')),
  ciphertext text not null check (length(ciphertext) between 16 and 4096),
  iv text not null check (length(iv) between 8 and 64),
  key_version integer not null default 1,
  created_at timestamptz not null default now()
);
alter table private.supplier_gateway_secrets enable row level security;
revoke all on private.supplier_gateway_secrets from public, anon, authenticated;

create table if not exists private.payment_change_requests (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id),
  requested_by uuid not null,
  proposed jsonb not null default '{}'::jsonb,
  new_gateway jsonb,
  new_secret_ciphertext text,
  new_secret_iv text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','superseded')),
  created_at timestamptz not null default now(),
  decided_by uuid,
  decided_at timestamptz,
  decision_note text
);
create unique index if not exists one_pending_change_per_supplier on private.payment_change_requests(supplier_id) where status='pending';
alter table private.payment_change_requests enable row level security;
revoke all on private.payment_change_requests from public, anon, authenticated;

-- ---------------------------------------------------------------- completeness / eligibility
create or replace function private.payment_profile_missing(p public.supplier_payment_profiles) returns text[]
language plpgsql stable security definer set search_path='' as $$
declare m text[] := '{}';
begin
  if p.entity_type is null then m := array_append(m, 'entity_type'); end if;
  if p.legal_name is null then m := array_append(m, 'legal_name'); end if;
  if p.cr_number is null then m := array_append(m, 'cr_number'); end if;
  if p.account_holder_name is null then m := array_append(m, 'account_holder_name'); end if;
  if p.bank_name is null then m := array_append(m, 'bank_name'); end if;
  if p.iban is null or not p.iban_valid then m := array_append(m, 'iban'); end if;
  if p.vat_registered and (p.tax_number is null or p.vat_certificate_path is null) then m := array_append(m, 'vat_certificate'); end if;
  if p.gateway_provider is null or not exists(select 1 from private.supplier_gateway_secrets s where s.supplier_id=p.supplier_id) then m := array_append(m, 'gateway'); end if;
  if p.gateway_check_status = 'invalid' then m := array_append(m, 'gateway_invalid'); end if;
  return m;
end $$;

create or replace function private.supplier_contract_ok(p_supplier uuid) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare v_owner uuid; c public.supplier_contract_versions; v_prev text; g integer;
begin
  select owner_id into v_owner from public.suppliers where id=p_supplier;
  select * into c from public.supplier_contract_versions where published and is_current;
  if v_owner is null or c.version_id is null then return false; end if;
  if exists(select 1 from private.supplier_contract_acceptances a where a.supplier_id=p_supplier and a.signer_id=v_owner and a.version_id=c.version_id) then return true; end if;
  -- grace period after a new version is published, if the previous version was accepted
  select contract_reaccept_grace_days into g from private.finance_settings where id;
  return exists(select 1 from private.supplier_contract_acceptances a
    join public.supplier_contract_versions v on v.version_id=a.version_id
    where a.supplier_id=p_supplier and a.signer_id=v_owner and v.published and v.published_at < c.published_at)
    and now() < c.published_at + make_interval(days => coalesce(g,0));
end $$;

create or replace function private.compute_supplier_blockers(p_supplier uuid) returns text[]
language plpgsql stable security definer set search_path='' as $$
declare s public.suppliers; p public.supplier_payment_profiles; b text[] := '{}';
begin
  select * into s from public.suppliers where id=p_supplier;
  if not found then return array['unknown_supplier']; end if;
  if s.approval_status <> 'approved' then b := array_append(b, 'not_approved'); end if;
  select * into p from public.supplier_payment_profiles where supplier_id=p_supplier;
  if p.supplier_id is null or p.status = 'incomplete' then b := array_append(b, 'payment_profile_incomplete');
  elsif p.status = 'pending' then b := array_append(b, 'payment_pending_review');
  elsif p.status = 'suspended' then b := array_append(b, 'payment_suspended'); end if;
  if not private.supplier_contract_ok(p_supplier) then b := array_append(b, 'contract_not_accepted'); end if;
  if s.orders_suspended then b := array_append(b, 'orders_suspended'); end if;
  return b;
end $$;

create or replace function private.refresh_supplier_selling(p_supplier uuid) returns void
language plpgsql security definer set search_path='' as $$
declare b text[] := private.compute_supplier_blockers(p_supplier); v_enabled boolean;
begin
  if private.direct_payments_enabled() then v_enabled := cardinality(b) = 0;
  else v_enabled := not ('not_approved' = any(b)) and not ('orders_suspended' = any(b)); end if;
  update public.suppliers set selling_enabled = v_enabled, selling_blockers = b
   where id = p_supplier and (selling_enabled is distinct from v_enabled or selling_blockers is distinct from b);
end $$;

create or replace function private.refresh_all_supplier_selling() returns void
language plpgsql security definer set search_path='' as $$
declare r record; begin for r in select id from public.suppliers loop perform private.refresh_supplier_selling(r.id); end loop; end $$;

create or replace function private.trg_refresh_selling_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.refresh_supplier_selling(new.supplier_id); return null; end $$;
create trigger payment_profile_refresh_selling after insert or update on public.supplier_payment_profiles
  for each row execute function private.trg_refresh_selling_profile();

create or replace function private.trg_refresh_selling_acceptance() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.refresh_supplier_selling(new.supplier_id); return null; end $$;
create trigger contract_acceptance_refresh_selling after insert on private.supplier_contract_acceptances
  for each row execute function private.trg_refresh_selling_acceptance();

create or replace function private.trg_refresh_selling_supplier() returns trigger language plpgsql security definer set search_path='' as $$
begin perform private.refresh_supplier_selling(new.id); return null; end $$;
create trigger supplier_refresh_selling after insert or update of approval_status, orders_suspended on public.suppliers
  for each row execute function private.trg_refresh_selling_supplier();

-- ---------------------------------------------------------------- supplier: save payment settings
create or replace function private.require_supplier_owner(p_supplier uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
  perform private.assert_account_session();
  if not exists(select 1 from public.suppliers where id=p_supplier and owner_id=auth.uid() and approval_status='approved') then
    raise exception 'permission denied' using errcode='42501';
  end if;
end $$;

create or replace function public.supplier_save_payment_profile(p_supplier uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cur public.supplier_payment_profiles; v jsonb; v_iban text; v_tax text; v_vat boolean; miss text[]; v_req uuid;
begin
  perform private.require_supplier_owner(p_supplier);
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'invalid payment settings'; end if;
  v_iban := nullif(private.normalize_iban(p->>'iban'), '');
  if v_iban is not null and not private.is_valid_sa_iban(v_iban) then raise exception 'invalid IBAN: must be a valid Saudi IBAN (SA + 22 digits, checksum)'; end if;
  if p ? 'cr_number' and coalesce(p->>'cr_number','') !~ '^[0-9]{10}$' then raise exception 'commercial registration must be 10 digits'; end if;
  v_vat := coalesce((p->>'vat_registered')::boolean, false);
  v_tax := nullif(regexp_replace(coalesce(p->>'tax_number',''),'\D','','g'),'');
  if v_vat and (v_tax is null or not private.is_valid_sa_vat(v_tax)) then raise exception 'valid 15-digit VAT number (starts and ends with 3) required when VAT registered'; end if;
  if p ? 'entity_type' and p->>'entity_type' not in ('factory','distributor','trader') then raise exception 'invalid entity type'; end if;
  if p ? 'vat_certificate_path' and nullif(p->>'vat_certificate_path','') is not null
     and (storage.foldername(p->>'vat_certificate_path'))[1] is distinct from auth.uid()::text then
    raise exception 'certificate must be uploaded from your own account';
  end if;
  v := jsonb_build_object(
    'entity_type', p->>'entity_type', 'legal_name', nullif(btrim(p->>'legal_name'),''), 'cr_number', p->>'cr_number',
    'account_holder_name', nullif(btrim(p->>'account_holder_name'),''), 'bank_name', nullif(btrim(p->>'bank_name'),''),
    'iban', v_iban, 'vat_registered', v_vat, 'tax_number', case when v_vat then v_tax else null end,
    'vat_certificate_path', case when v_vat then nullif(p->>'vat_certificate_path','') else null end);

  insert into public.supplier_payment_profiles(supplier_id) values (p_supplier) on conflict do nothing;
  select * into cur from public.supplier_payment_profiles where supplier_id=p_supplier for update;

  if cur.status = 'active' then
    -- Sensitive change on a verified account: keep the verified details active and
    -- queue the change for administrative re-verification.
    update private.payment_change_requests set status='superseded', decided_at=now() where supplier_id=p_supplier and status='pending';
    insert into private.payment_change_requests(supplier_id, requested_by, proposed) values (p_supplier, auth.uid(), v) returning id into v_req;
    perform private.fin_audit('payment_profile', p_supplier::text, 'change_requested', null,
      v - 'iban' || jsonb_build_object('iban', private.mask_iban(v_iban)));
    perform private.raise_finance_alert('payment_change_request','info',p_supplier,null,null,'طلب تعديل بيانات الدفع بانتظار المراجعة',jsonb_build_object('request_id',v_req),'pcr:'||v_req);
    return jsonb_build_object('status', cur.status, 'change_request', v_req);
  end if;

  update public.supplier_payment_profiles set
    entity_type = coalesce(v->>'entity_type', entity_type), legal_name = coalesce(v->>'legal_name', legal_name),
    cr_number = coalesce(v->>'cr_number', cr_number), account_holder_name = coalesce(v->>'account_holder_name', account_holder_name),
    bank_name = coalesce(v->>'bank_name', bank_name), iban = coalesce(v->>'iban', iban),
    vat_registered = v_vat, tax_number = v->>'tax_number',
    vat_certificate_path = case when v_vat then coalesce(v->>'vat_certificate_path', vat_certificate_path) else null end,
    updated_at = now()
  where supplier_id=p_supplier returning * into cur;
  miss := private.payment_profile_missing(cur);
  update public.supplier_payment_profiles set
    status = case when status='suspended' then 'suspended' when cardinality(miss)=0 then 'pending' else 'incomplete' end,
    submitted_at = case when cardinality(miss)=0 then now() else submitted_at end, updated_at = now()
  where supplier_id=p_supplier returning * into cur;
  update public.suppliers set entity_type = cur.entity_type where id = p_supplier and entity_type is distinct from cur.entity_type;
  perform private.fin_audit('payment_profile', p_supplier::text, 'saved', null, v - 'iban' || jsonb_build_object('iban', private.mask_iban(v_iban), 'status', cur.status));
  if cur.status='pending' then
    perform private.raise_finance_alert('payment_profile_review','info',p_supplier,null,null,'ملف دفع بانتظار التحقق',null,'ppr:'||p_supplier||':'||extract(epoch from cur.submitted_at)::bigint);
  end if;
  return jsonb_build_object('status', cur.status, 'missing', miss);
end $$;

-- ---------------------------------------------------------------- service role: store encrypted gateway credentials
-- Called only by the supplier-gateway Edge Function after it verified the key with
-- the provider and encrypted it. p_user is the authenticated caller resolved by the function.
create or replace function private.svc_store_gateway_credentials(p_supplier uuid, p_user uuid, p_provider text, p_mode text,
  p_hint text, p_merchant text, p_check_status text, p_ciphertext text, p_iv text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cur public.supplier_payment_profiles; miss text[]; v_req uuid; g jsonb;
begin
  if not exists(select 1 from public.suppliers where id=p_supplier and owner_id=p_user and approval_status='approved') then
    raise exception 'permission denied' using errcode='42501'; end if;
  if p_provider not in ('tap') or p_mode not in ('test','live') or p_check_status not in ('valid','invalid','unreachable') then
    raise exception 'invalid gateway data'; end if;
  insert into public.supplier_payment_profiles(supplier_id) values (p_supplier) on conflict do nothing;
  select * into cur from public.supplier_payment_profiles where supplier_id=p_supplier for update;
  g := jsonb_build_object('provider',p_provider,'mode',p_mode,'hint',p_hint,'merchant_id',nullif(btrim(p_merchant),''),'check_status',p_check_status);
  if cur.status = 'active' then
    update private.payment_change_requests set status='superseded', decided_at=now() where supplier_id=p_supplier and status='pending';
    insert into private.payment_change_requests(supplier_id, requested_by, new_gateway, new_secret_ciphertext, new_secret_iv)
    values (p_supplier, p_user, g, p_ciphertext, p_iv) returning id into v_req;
    insert into public.pricing_audit_log(actor_id, entity_type, entity_id, action, new_value)
    values (p_user, 'payment_profile', p_supplier::text, 'gateway_change_requested', g);
    perform private.raise_finance_alert('payment_change_request','warning',p_supplier,null,null,'طلب تغيير بوابة الدفع بانتظار المراجعة',g,'pcr:'||v_req);
    return jsonb_build_object('status','active','change_request',v_req);
  end if;
  insert into private.supplier_gateway_secrets(supplier_id, provider, ciphertext, iv) values (p_supplier, p_provider, p_ciphertext, p_iv)
  on conflict (supplier_id) do update set provider=excluded.provider, ciphertext=excluded.ciphertext, iv=excluded.iv, created_at=now();
  update public.supplier_payment_profiles set gateway_provider=p_provider, gateway_mode=p_mode, gateway_key_hint=p_hint,
    gateway_merchant_id=nullif(btrim(p_merchant),''), gateway_check_status=p_check_status, gateway_checked_at=now(),
    gateway_connected_at=now(), updated_at=now() where supplier_id=p_supplier returning * into cur;
  miss := private.payment_profile_missing(cur);
  update public.supplier_payment_profiles set
    status = case when status='suspended' then 'suspended' when cardinality(miss)=0 then 'pending' else 'incomplete' end,
    submitted_at = case when cardinality(miss)=0 then now() else submitted_at end
  where supplier_id=p_supplier returning * into cur;
  insert into public.pricing_audit_log(actor_id, entity_type, entity_id, action, new_value)
  values (p_user, 'payment_profile', p_supplier::text, 'gateway_connected', g || jsonb_build_object('status',cur.status));
  return jsonb_build_object('status', cur.status, 'missing', miss);
end $$;
create or replace function public.svc_store_gateway_credentials(p_supplier uuid, p_user uuid, p_provider text, p_mode text,
  p_hint text, p_merchant text, p_check_status text, p_ciphertext text, p_iv text) returns jsonb
language sql security definer set search_path='' as $$
  select private.svc_store_gateway_credentials(p_supplier,p_user,p_provider,p_mode,p_hint,p_merchant,p_check_status,p_ciphertext,p_iv) $$;
revoke all on function private.svc_store_gateway_credentials(uuid,uuid,text,text,text,text,text,text,text),
  public.svc_store_gateway_credentials(uuid,uuid,text,text,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.svc_store_gateway_credentials(uuid,uuid,text,text,text,text,text,text,text) to service_role;

-- Ownership check for the Edge Function (runs with the caller's JWT).
create or replace function public.my_supplier_ids() returns setof uuid
language plpgsql stable security definer set search_path='' as $$
begin perform private.assert_account_session();
  return query select id from public.suppliers where owner_id=auth.uid() and approval_status='approved'; end $$;
revoke all on function public.my_supplier_ids() from public, anon; grant execute on function public.my_supplier_ids() to authenticated;

-- ---------------------------------------------------------------- admin review
create or replace function public.admin_review_payment_profile(p_supplier uuid, p_action text, p_note text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cur public.supplier_payment_profiles; miss text[]; s private.finance_settings; v_new text;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into cur from public.supplier_payment_profiles where supplier_id=p_supplier for update;
  if not found then raise exception 'payment profile not found'; end if;
  s := private.fin(); miss := private.payment_profile_missing(cur);
  if p_action in ('approve','reactivate') then
    if cardinality(miss) > 0 then raise exception 'payment profile incomplete: %', array_to_string(miss, ', '); end if;
    if cur.gateway_check_status <> 'valid' then raise exception 'gateway credentials not verified with the provider'; end if;
    if cur.gateway_mode = 'live' and cur.gateway_provider = 'tap' and not s.tap_live_contract_confirmed then
      raise exception 'live Tap keys cannot be activated until direct-settlement terms (no unapproved monthly fees) are confirmed in finance settings';
    end if;
    v_new := 'active';
    update public.supplier_payment_profiles set status='active', status_reason=null, verified_by=auth.uid(), verified_at=now(), updated_at=now() where supplier_id=p_supplier;
  elsif p_action = 'reject' then
    v_new := 'incomplete';
    update public.supplier_payment_profiles set status='incomplete', status_reason=coalesce(nullif(btrim(p_note),''),'يلزم تصحيح بيانات الدفع'), updated_at=now() where supplier_id=p_supplier;
  elsif p_action = 'suspend' then
    if nullif(btrim(p_note),'') is null then raise exception 'suspension reason required'; end if;
    v_new := 'suspended';
    update public.supplier_payment_profiles set status='suspended', status_reason=btrim(p_note), suspended_by=auth.uid(), suspended_at=now(), updated_at=now() where supplier_id=p_supplier;
  else raise exception 'invalid action'; end if;
  perform private.fin_audit('payment_profile', p_supplier::text, 'admin_'||p_action, jsonb_build_object('status',cur.status), jsonb_build_object('status',v_new,'note',p_note));
  perform private.admin_log('payment_profile_'||p_action, 'supplier', p_supplier::text);
  perform private.notify_supplier(p_supplier, 'payment_status',
    case v_new when 'active' then 'تم تفعيل وسيلة الدفع' when 'suspended' then 'تم إيقاف وسيلة الدفع' else 'يلزم تحديث بيانات الدفع' end,
    coalesce(p_note, case v_new when 'active' then 'تم التحقق من بيانات الدفع وبوابة الدفع.' else 'راجع إعدادات الدفع في لوحة المورد.' end),
    'payment_profile', p_supplier::text, null);
  update private.finance_alerts set resolved_at=now(), resolved_by=auth.uid(), resolution_note=p_action
   where supplier_id=p_supplier and kind='payment_profile_review' and resolved_at is null;
  return jsonb_build_object('status', v_new);
end $$;

create or replace function public.admin_decide_payment_change(p_request uuid, p_approve boolean, p_note text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r private.payment_change_requests; cur public.supplier_payment_profiles; v jsonb; g jsonb; s private.finance_settings;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into r from private.payment_change_requests where id=p_request for update;
  if not found or r.status <> 'pending' then raise exception 'change request not pending'; end if;
  if p_approve then
    v := r.proposed; g := r.new_gateway; s := private.fin();
    if g is not null and g->>'check_status' <> 'valid' then raise exception 'new gateway credentials were not verified with the provider'; end if;
    if g is not null and g->>'mode' = 'live' and not s.tap_live_contract_confirmed then
      raise exception 'live Tap keys cannot be activated until direct-settlement terms are confirmed in finance settings'; end if;
    select * into cur from public.supplier_payment_profiles where supplier_id=r.supplier_id for update;
    if v <> '{}'::jsonb then
      update public.supplier_payment_profiles set
        entity_type=coalesce(v->>'entity_type',entity_type), legal_name=coalesce(v->>'legal_name',legal_name),
        cr_number=coalesce(v->>'cr_number',cr_number), account_holder_name=coalesce(v->>'account_holder_name',account_holder_name),
        bank_name=coalesce(v->>'bank_name',bank_name), iban=coalesce(v->>'iban',iban),
        vat_registered=coalesce((v->>'vat_registered')::boolean,vat_registered), tax_number=v->>'tax_number',
        vat_certificate_path=case when coalesce((v->>'vat_registered')::boolean,vat_registered) then coalesce(v->>'vat_certificate_path',vat_certificate_path) else null end,
        updated_at=now() where supplier_id=r.supplier_id returning * into cur;
      if cardinality(private.payment_profile_missing(cur)) > 0 then raise exception 'approved change would leave the payment profile incomplete'; end if;
    end if;
    if g is not null then
      insert into private.supplier_gateway_secrets(supplier_id, provider, ciphertext, iv) values (r.supplier_id, g->>'provider', r.new_secret_ciphertext, r.new_secret_iv)
      on conflict (supplier_id) do update set provider=excluded.provider, ciphertext=excluded.ciphertext, iv=excluded.iv, created_at=now();
      update public.supplier_payment_profiles set gateway_provider=g->>'provider', gateway_mode=g->>'mode', gateway_key_hint=g->>'hint',
        gateway_merchant_id=g->>'merchant_id', gateway_check_status=g->>'check_status', gateway_checked_at=now(), gateway_connected_at=now(), updated_at=now()
      where supplier_id=r.supplier_id;
    end if;
    update public.supplier_payment_profiles set verified_by=auth.uid(), verified_at=now() where supplier_id=r.supplier_id;
  end if;
  update private.payment_change_requests set status=case when p_approve then 'approved' else 'rejected' end,
    decided_by=auth.uid(), decided_at=now(), decision_note=p_note, new_secret_ciphertext=null, new_secret_iv=null where id=p_request;
  perform private.fin_audit('payment_profile', r.supplier_id::text, case when p_approve then 'change_approved' else 'change_rejected' end,
    null, jsonb_build_object('request', p_request, 'note', p_note));
  perform private.notify_supplier(r.supplier_id, 'payment_change', case when p_approve then 'تم اعتماد تعديل بيانات الدفع' else 'تم رفض تعديل بيانات الدفع' end,
    coalesce(p_note,''), 'payment_change', p_request::text, null);
  update private.finance_alerts set resolved_at=now(), resolved_by=auth.uid() where dedupe_key='pcr:'||p_request;
  return jsonb_build_object('approved', p_approve);
end $$;

-- ---------------------------------------------------------------- read RPCs
create or replace function public.my_payment_profile(p_supplier uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare cur public.supplier_payment_profiles; r private.payment_change_requests;
begin
  perform private.require_supplier_owner(p_supplier);
  select * into cur from public.supplier_payment_profiles where supplier_id=p_supplier;
  select * into r from private.payment_change_requests where supplier_id=p_supplier and status='pending';
  return jsonb_build_object('profile', to_jsonb(cur), 'missing', case when cur.supplier_id is null then null else private.payment_profile_missing(cur) end,
    'pending_change', case when r.id is null then null else jsonb_build_object('id',r.id,'created_at',r.created_at,'fields',(select coalesce(jsonb_agg(k),'[]'::jsonb) from jsonb_object_keys(r.proposed) k),'gateway',r.new_gateway is not null) end,
    'blockers', (select selling_blockers from public.suppliers where id=p_supplier),
    'selling_enabled', (select selling_enabled from public.suppliers where id=p_supplier));
end $$;

create or replace function public.admin_payment_profiles() returns table(supplier_id uuid, supplier_name text, owner_email text, profile jsonb, missing text[],
  selling_enabled boolean, blockers text[], pending_change jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select s.id, s.name, (select u.email::text from auth.users u where u.id=s.owner_id), to_jsonb(p),
    case when p.supplier_id is null then array['no_profile'] else private.payment_profile_missing(p) end,
    s.selling_enabled, s.selling_blockers,
    (select jsonb_build_object('id',r.id,'created_at',r.created_at,'proposed',r.proposed,'gateway',r.new_gateway)
       from private.payment_change_requests r where r.supplier_id=s.id and r.status='pending')
  from public.suppliers s left join public.supplier_payment_profiles p on p.supplier_id=s.id
  where s.approval_status='approved' order by s.created_at;
end $$;

revoke all on function public.supplier_save_payment_profile(uuid,jsonb), public.admin_review_payment_profile(uuid,text,text),
  public.admin_decide_payment_change(uuid,boolean,text), public.my_payment_profile(uuid), public.admin_payment_profiles() from public, anon;
grant execute on function public.supplier_save_payment_profile(uuid,jsonb), public.admin_review_payment_profile(uuid,text,text),
  public.admin_decide_payment_change(uuid,boolean,text), public.my_payment_profile(uuid), public.admin_payment_profiles() to authenticated;

-- ---------------------------------------------------------------- explicit contract consent at registration
create table if not exists private.application_contract_acceptances (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null unique references public.seller_applications(id),
  version_id text not null,
  body_sha256 text not null,
  signer_id uuid not null references auth.users(id),
  signer_full_name text not null check (length(btrim(signer_full_name)) between 3 and 160 and signer_full_name !~ '[[:cntrl:]]'),
  session_id uuid not null,
  request_id uuid not null,
  user_agent text,
  ip text,
  accepted_at timestamptz not null default now(),
  unique (signer_id, request_id),
  foreign key (version_id, body_sha256) references public.supplier_contract_versions(version_id, body_sha256)
);
alter table private.application_contract_acceptances enable row level security;
revoke all on private.application_contract_acceptances from public, anon, authenticated;
create trigger application_acceptance_append_only before update or delete on private.application_contract_acceptances
  for each row execute function private.block_mutation();

create or replace function private.request_header(p_name text) returns text
language sql stable set search_path='' as $$
  select nullif(current_setting('request.headers', true), '')::jsonb ->> p_name $$;

-- Single entry point for supplier registration: the application and the explicit,
-- hash-verified consent to the current contract are recorded atomically.
create or replace function public.submit_seller_application(p jsonb, p_contract_version text, p_contract_hash text,
  p_signer_name text, p_agreed boolean, p_request uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid := auth.uid(); c public.supplier_contract_versions; v_id uuid; v_name text := btrim(p_signer_name); v_iban text; v_tax text;
begin
  perform private.assert_account_session();
  if p_agreed is distinct from true or p_request is null or v_name is null or length(v_name) not between 3 and 160 then
    raise exception 'explicit contract consent and signer name required'; end if;
  select * into c from public.supplier_contract_versions where version_id=p_contract_version and published and is_current;
  if not found or p_contract_hash is distinct from c.body_sha256 then raise exception 'contract version changed; reload before accepting' using errcode='40001'; end if;
  perform pg_advisory_xact_lock(hashtextextended('seller-app:'||v_user::text||':'||p_request::text,0));
  select application_id into v_id from private.application_contract_acceptances where signer_id=v_user and request_id=p_request;
  if v_id is not null then return v_id; end if;
  if length(btrim(coalesce(p->>'business_name',''))) < 2 then raise exception 'business name required'; end if;
  if coalesce(p->>'commercial_registration','') !~ '^[0-9]{10}$' then raise exception 'commercial registration must be 10 digits'; end if;
  if coalesce(p->>'entity_type','') not in ('factory','distributor','trader') then raise exception 'entity type required'; end if;
  v_iban := private.normalize_iban(p->>'iban');
  if not private.is_valid_sa_iban(v_iban) then raise exception 'invalid IBAN'; end if;
  v_tax := nullif(regexp_replace(coalesce(p->>'tax_number',''),'\D','','g'),'');
  if v_tax is not null and not private.is_valid_sa_vat(v_tax) then raise exception 'invalid VAT number'; end if;
  if coalesce(p->>'document_path','') = '' or (storage.foldername(p->>'document_path'))[1] is distinct from v_user::text then
    raise exception 'commercial registration document required'; end if;
  insert into public.seller_applications(owner_id, business_name, commercial_registration, phone, email, city, category, document_path, iban,
    manager_name, manager_title, national_address, tax_number, authorization_doc_path, license_doc_path, accepts_delivery,
    entity_type, account_holder_name, bank_name)
  values (v_user, btrim(p->>'business_name'), p->>'commercial_registration', p->>'phone', nullif(btrim(p->>'email'),''),
    coalesce(p->>'city','makkah'), coalesce(p->>'category','water'), p->>'document_path', v_iban,
    nullif(btrim(p->>'manager_name'),''), nullif(btrim(p->>'manager_title'),''), nullif(btrim(p->>'national_address'),''), v_tax,
    nullif(p->>'authorization_doc_path',''), nullif(p->>'license_doc_path',''), coalesce((p->>'accepts_delivery')::boolean,false),
    p->>'entity_type', nullif(btrim(p->>'account_holder_name'),''), nullif(btrim(p->>'bank_name'),''))
  returning id into v_id;
  insert into private.application_contract_acceptances(application_id, version_id, body_sha256, signer_id, signer_full_name, session_id, request_id, user_agent, ip)
  values (v_id, c.version_id, c.body_sha256, v_user, v_name, (auth.jwt()->>'session_id')::uuid, p_request,
    left(private.request_header('user-agent'), 400), left(split_part(coalesce(private.request_header('x-forwarded-for'),''), ',', 1), 64));
  return v_id;
end $$;
revoke all on function public.submit_seller_application(jsonb,text,text,text,boolean,uuid) from public, anon;
grant execute on function public.submit_seller_application(jsonb,text,text,text,boolean,uuid) to authenticated;

-- Approval now requires the applicant's recorded consent, carries it into the supplier
-- contract ledger, and opens the payment profile prefilled from the application.
create or replace function public.admin_decide_application(p_id uuid, p_approve boolean)
returns void language plpgsql security definer set search_path to '' as $$
declare v_app public.seller_applications%rowtype; v_sup_id uuid; v_acc private.application_contract_acceptances; v_tax text;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into v_app from public.seller_applications where id=p_id for update;
  if not found then raise exception 'application not found'; end if;
  if p_approve then
    select * into v_acc from private.application_contract_acceptances where application_id=p_id;
    if v_acc.id is null then raise exception 'cannot approve: applicant has not explicitly accepted the supplier contract'; end if;
    update public.seller_applications set status='approved' where id=p_id;
    select id into v_sup_id from public.suppliers where owner_id=v_app.owner_id and name=v_app.business_name limit 1;
    if v_sup_id is null then
      insert into public.suppliers(owner_id,name,cities,approval_status,national_address,tax_number,warehouse_city,accepts_delivery,entity_type)
      values(v_app.owner_id, v_app.business_name, array['makkah','madinah'], 'approved', v_app.national_address, v_app.tax_number, v_app.city,
        coalesce(v_app.accepts_delivery,false), v_app.entity_type)
      returning id into v_sup_id;
    else
      update public.suppliers set approval_status='approved', cities=array['makkah','madinah'],
        national_address=coalesce(v_app.national_address,national_address), tax_number=coalesce(v_app.tax_number,tax_number),
        warehouse_city=coalesce(v_app.city,warehouse_city), accepts_delivery=coalesce(v_app.accepts_delivery,accepts_delivery),
        entity_type=coalesce(v_app.entity_type, entity_type)
      where id=v_sup_id;
    end if;
    if not exists(select 1 from public.warehouses w where w.supplier_id=v_sup_id) then
      insert into public.warehouses(supplier_id, name, national_address, city) values (v_sup_id, 'المستودع الرئيسي', v_app.national_address, v_app.city);
    end if;
    insert into private.supplier_contract_acceptances(supplier_id,version_id,body_sha256,signer_id,signer_full_name,session_id,request_id,accepted_at)
    select v_sup_id, v_acc.version_id, v_acc.body_sha256, v_acc.signer_id, v_acc.signer_full_name, v_acc.session_id, v_acc.request_id, v_acc.accepted_at
    where not exists(select 1 from private.supplier_contract_acceptances a where a.supplier_id=v_sup_id and a.version_id=v_acc.version_id and a.signer_id=v_acc.signer_id);
    v_tax := case when private.is_valid_sa_vat(v_app.tax_number) then v_app.tax_number else null end;
    insert into public.supplier_payment_profiles(supplier_id, entity_type, legal_name, cr_number, account_holder_name, bank_name, iban, vat_registered, tax_number)
    values (v_sup_id, v_app.entity_type, v_app.business_name, case when v_app.commercial_registration ~ '^[0-9]{10}$' then v_app.commercial_registration end,
      v_app.account_holder_name, coalesce(v_app.bank_name, private.sa_bank_from_iban(v_app.iban)),
      case when private.is_valid_sa_iban(v_app.iban) then private.normalize_iban(v_app.iban) end, v_tax is not null, v_tax)
    on conflict (supplier_id) do nothing;
    perform private.refresh_supplier_selling(v_sup_id);
    perform private.notify_supplier(v_sup_id, 'approved', 'تم اعتماد منشأتك',
      'أكمل «إعدادات الدفع واستلام المستحقات» واربط بوابة الدفع الخاصة بك لتفعيل البيع.', 'supplier', v_sup_id::text, 'approved:'||v_sup_id);
  else
    update public.seller_applications set status='rejected' where id=p_id;
  end if;
  perform private.admin_log(case when p_approve then 'application_approve' else 'application_reject' end, 'seller_application', p_id::text);
end $$;

-- backfill: existing approved suppliers get a payment profile shell and a computed selling state
insert into public.supplier_payment_profiles(supplier_id, legal_name, tax_number, vat_registered)
select s.id, s.name, case when private.is_valid_sa_vat(s.tax_number) then s.tax_number end, private.is_valid_sa_vat(s.tax_number)
from public.suppliers s where s.approval_status='approved' on conflict do nothing;
select private.refresh_all_supplier_selling();
