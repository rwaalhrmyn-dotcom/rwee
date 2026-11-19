-- Finance foundation for supplier-direct payments, commissions and monthly invoices.
-- Additive only: no existing data is removed. Feature is gated by
-- private.finance_settings.direct_payments_enabled (default false in production).

-- ---------------------------------------------------------------- helpers
create or replace function private.ksa_today() returns date
language sql stable set search_path='' as $$ select (now() at time zone 'Asia/Riyadh')::date $$;

create or replace function private.ksa_month(p_ts timestamptz) returns date
language sql stable set search_path='' as $$ select date_trunc('month', p_ts at time zone 'Asia/Riyadh')::date $$;

-- Saudi IBAN: SA + 2 check digits + 2-digit bank code + 18 account chars, ISO 13616 MOD-97.
create or replace function private.normalize_iban(p text) returns text
language sql immutable set search_path='' as $$ select upper(regexp_replace(coalesce(p,''), '[^A-Za-z0-9]', '', 'g')) $$;

create or replace function private.is_valid_sa_iban(p text) returns boolean
language plpgsql immutable set search_path='' as $$
declare v text := private.normalize_iban(p); r text;
begin
  if v !~ '^SA[0-9]{22}$' then return false; end if;
  -- move country+check digits to the end; S=28, A=10
  r := substr(v, 5) || '2810' || substr(v, 3, 2);
  return (r::numeric % 97) = 1;
end $$;

create or replace function private.sa_bank_from_iban(p text) returns text
language sql immutable set search_path='' as $$
  select case substr(private.normalize_iban(p), 5, 2)
    when '05' then 'مصرف الإنماء' when '10' then 'البنك الأهلي السعودي' when '15' then 'بنك البلاد'
    when '20' then 'بنك الرياض' when '30' then 'البنك العربي الوطني' when '40' then 'البنك الأهلي السعودي'
    when '45' then 'البنك السعودي الأول' when '50' then 'البنك السعودي الأول' when '55' then 'البنك السعودي الفرنسي'
    when '60' then 'بنك الجزيرة' when '65' then 'البنك السعودي للاستثمار' when '80' then 'مصرف الراجحي'
    else null end $$;

-- KSA VAT registration number: 15 digits, starting and ending with 3.
create or replace function private.is_valid_sa_vat(p text) returns boolean
language sql immutable set search_path='' as $$ select coalesce(p,'') ~ '^3[0-9]{13}3$' $$;

create or replace function private.mask_iban(p text) returns text
language sql immutable set search_path='' as $$
  select case when p is null then null else left(private.normalize_iban(p),4)||repeat('•',greatest(length(private.normalize_iban(p))-8,0))||right(private.normalize_iban(p),4) end $$;

-- ---------------------------------------------------------------- settings
create table if not exists private.finance_settings (
  id boolean primary key default true check (id),
  direct_payments_enabled boolean not null default false,
  commission_rate_bp integer not null default 500 check (commission_rate_bp between 0 and 5000),
  commission_on_markup boolean not null default false,
  vat_rate_bp integer not null default 1500 check (vat_rate_bp between 0 and 5000),
  platform_vat_registered boolean not null default false,
  platform_vat_number text check (platform_vat_number is null or private.is_valid_sa_vat(platform_vat_number)),
  platform_legal_name text not null default 'رِواء الحرمين',
  platform_cr_number text not null default '7041122404',
  platform_address text,
  platform_bank_name text,
  platform_iban text check (platform_iban is null or private.is_valid_sa_iban(platform_iban)),
  platform_account_holder text,
  invoice_due_day integer not null default 5 check (invoice_due_day between 1 and 28),
  reminder_days_before integer not null default 2 check (reminder_days_before between 0 and 10),
  suspension_grace_days integer not null default 7 check (suspension_grace_days between 0 and 90),
  auto_issue_invoices boolean not null default true,
  contract_reaccept_grace_days integer not null default 14 check (contract_reaccept_grace_days between 0 and 90),
  tap_live_contract_confirmed boolean not null default false,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
insert into private.finance_settings(id) values (true) on conflict do nothing;
alter table private.finance_settings enable row level security;
revoke all on private.finance_settings from public, anon, authenticated;

create or replace function private.fin() returns private.finance_settings
language sql stable security definer set search_path='' as $$ select * from private.finance_settings where id $$;

create or replace function private.direct_payments_enabled() returns boolean
language sql stable security definer set search_path='' as $$ select coalesce((select direct_payments_enabled from private.finance_settings where id), false) $$;

-- ---------------------------------------------------------------- audit (pricing + finance, append-only, old/new values)
create table if not exists public.pricing_audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid,
  entity_type text not null check (entity_type in ('pricing_rule','finance_setting','product_price','supplier_price','commission','invoice','payment','credit_note','payment_profile','contract','supplier')),
  entity_id text,
  action text not null,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default now()
);
create index if not exists pricing_audit_entity_idx on public.pricing_audit_log(entity_type, entity_id, created_at desc);
alter table public.pricing_audit_log enable row level security;
revoke all on public.pricing_audit_log from public, anon, authenticated;
grant select on public.pricing_audit_log to authenticated;
create policy pricing_audit_operator_read on public.pricing_audit_log for select to authenticated using ((select private.is_platform_operator()));

create or replace function private.block_mutation() returns trigger language plpgsql set search_path='' as $$
begin raise exception '% is append-only', tg_table_name; end $$;
create trigger pricing_audit_append_only before update or delete on public.pricing_audit_log for each row execute function private.block_mutation();

create or replace function private.fin_audit(p_entity text, p_id text, p_action text, p_old jsonb, p_new jsonb) returns void
language sql security definer set search_path='' as $$
  insert into public.pricing_audit_log(actor_id, entity_type, entity_id, action, old_value, new_value)
  values (auth.uid(), p_entity, p_id, p_action, p_old, p_new) $$;

-- ---------------------------------------------------------------- supplier selling state columns
alter table public.suppliers add column if not exists entity_type text check (entity_type in ('factory','distributor','trader'));
alter table public.suppliers add column if not exists selling_enabled boolean not null default false;
alter table public.suppliers add column if not exists selling_blockers text[] not null default '{}';
alter table public.suppliers add column if not exists orders_suspended boolean not null default false;
alter table public.suppliers add column if not exists orders_suspended_reason text;
alter table public.suppliers add column if not exists orders_suspended_at timestamptz;

-- ---------------------------------------------------------------- notifications (supplier) and alerts (admin)
create table if not exists public.supplier_notifications (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id),
  kind text not null,
  title text not null,
  body text not null,
  ref_type text,
  ref_id text,
  dedupe_key text unique,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
create index if not exists supplier_notifications_supplier_idx on public.supplier_notifications(supplier_id, created_at desc);
alter table public.supplier_notifications enable row level security;
revoke all on public.supplier_notifications from public, anon, authenticated;
grant select on public.supplier_notifications to authenticated;
create policy supplier_notifications_read on public.supplier_notifications for select to authenticated
  using (private.owns_supplier(supplier_id) or (select private.is_platform_operator()));

create or replace function private.notify_supplier(p_supplier uuid, p_kind text, p_title text, p_body text, p_ref_type text, p_ref_id text, p_dedupe text default null)
returns void language sql security definer set search_path='' as $$
  insert into public.supplier_notifications(supplier_id, kind, title, body, ref_type, ref_id, dedupe_key)
  values (p_supplier, p_kind, p_title, p_body, p_ref_type, p_ref_id, p_dedupe)
  on conflict (dedupe_key) do nothing $$;

create table if not exists private.finance_alerts (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  severity text not null default 'warning' check (severity in ('info','warning','critical')),
  supplier_id uuid references public.suppliers(id),
  order_id uuid references public.orders(id),
  invoice_id uuid,
  message text not null,
  details jsonb,
  dedupe_key text unique,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid,
  resolution_note text
);
alter table private.finance_alerts enable row level security;
revoke all on private.finance_alerts from public, anon, authenticated;

create or replace function private.raise_finance_alert(p_kind text, p_severity text, p_supplier uuid, p_order uuid, p_invoice uuid, p_message text, p_details jsonb, p_dedupe text default null)
returns void language sql security definer set search_path='' as $$
  insert into private.finance_alerts(kind, severity, supplier_id, order_id, invoice_id, message, details, dedupe_key)
  values (p_kind, p_severity, p_supplier, p_order, p_invoice, p_message, p_details, p_dedupe)
  on conflict (dedupe_key) do nothing $$;

revoke all on function private.ksa_today(), private.ksa_month(timestamptz), private.normalize_iban(text), private.is_valid_sa_iban(text),
  private.sa_bank_from_iban(text), private.is_valid_sa_vat(text), private.mask_iban(text), private.fin(), private.direct_payments_enabled(),
  private.fin_audit(text,text,text,jsonb,jsonb), private.notify_supplier(uuid,text,text,text,text,text,text),
  private.raise_finance_alert(text,text,uuid,uuid,uuid,text,jsonb,text) from public, anon;
grant execute on function private.ksa_today(), private.ksa_month(timestamptz), private.normalize_iban(text), private.is_valid_sa_iban(text),
  private.sa_bank_from_iban(text), private.is_valid_sa_vat(text), private.mask_iban(text), private.direct_payments_enabled() to authenticated, service_role;

-- ---------------------------------------------------------------- settings RPCs
create or replace function public.finance_public_settings() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('direct_payments_enabled', s.direct_payments_enabled, 'vat_rate_bp', s.vat_rate_bp,
    'commission_rate_bp', s.commission_rate_bp, 'commission_on_markup', s.commission_on_markup, 'invoice_due_day', s.invoice_due_day)
  from private.finance_settings s where s.id $$;
grant execute on function public.finance_public_settings() to anon, authenticated;

create or replace function public.admin_finance_settings() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return (select to_jsonb(s) from private.finance_settings s where s.id);
end $$;

create or replace function public.admin_update_finance_settings(p jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_old private.finance_settings; v_new private.finance_settings; k text;
  allowed text[] := array['direct_payments_enabled','commission_rate_bp','commission_on_markup','vat_rate_bp','platform_vat_registered',
    'platform_vat_number','platform_legal_name','platform_cr_number','platform_address','platform_bank_name','platform_iban',
    'platform_account_holder','invoice_due_day','reminder_days_before','suspension_grace_days','auto_issue_invoices',
    'contract_reaccept_grace_days','tap_live_contract_confirmed'];
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p is null or jsonb_typeof(p) <> 'object' then raise exception 'invalid settings'; end if;
  for k in select jsonb_object_keys(p) loop
    if not k = any(allowed) then raise exception 'unknown setting: %', k; end if;
  end loop;
  select * into v_old from private.finance_settings where id for update;
  update private.finance_settings set
    direct_payments_enabled = coalesce((p->>'direct_payments_enabled')::boolean, direct_payments_enabled),
    commission_rate_bp = coalesce((p->>'commission_rate_bp')::integer, commission_rate_bp),
    commission_on_markup = coalesce((p->>'commission_on_markup')::boolean, commission_on_markup),
    vat_rate_bp = coalesce((p->>'vat_rate_bp')::integer, vat_rate_bp),
    platform_vat_registered = coalesce((p->>'platform_vat_registered')::boolean, platform_vat_registered),
    platform_vat_number = case when p ? 'platform_vat_number' then nullif(btrim(p->>'platform_vat_number'),'') else platform_vat_number end,
    platform_legal_name = coalesce(nullif(btrim(p->>'platform_legal_name'),''), platform_legal_name),
    platform_cr_number = coalesce(nullif(btrim(p->>'platform_cr_number'),''), platform_cr_number),
    platform_address = case when p ? 'platform_address' then nullif(btrim(p->>'platform_address'),'') else platform_address end,
    platform_bank_name = case when p ? 'platform_bank_name' then nullif(btrim(p->>'platform_bank_name'),'') else platform_bank_name end,
    platform_iban = case when p ? 'platform_iban' then nullif(private.normalize_iban(p->>'platform_iban'),'') else platform_iban end,
    platform_account_holder = case when p ? 'platform_account_holder' then nullif(btrim(p->>'platform_account_holder'),'') else platform_account_holder end,
    invoice_due_day = coalesce((p->>'invoice_due_day')::integer, invoice_due_day),
    reminder_days_before = coalesce((p->>'reminder_days_before')::integer, reminder_days_before),
    suspension_grace_days = coalesce((p->>'suspension_grace_days')::integer, suspension_grace_days),
    auto_issue_invoices = coalesce((p->>'auto_issue_invoices')::boolean, auto_issue_invoices),
    contract_reaccept_grace_days = coalesce((p->>'contract_reaccept_grace_days')::integer, contract_reaccept_grace_days),
    tap_live_contract_confirmed = coalesce((p->>'tap_live_contract_confirmed')::boolean, tap_live_contract_confirmed),
    updated_at = now(), updated_by = auth.uid()
  where id returning * into v_new;
  if v_new.platform_vat_registered and v_new.platform_vat_number is null then
    raise exception 'platform VAT number required when the platform is VAT registered';
  end if;
  perform private.fin_audit('finance_setting', 'finance_settings', 'update', to_jsonb(v_old), to_jsonb(v_new));
  -- commission/VAT changes never touch past orders (snapshots); refresh current shelf prices only.
  if v_old.vat_rate_bp is distinct from v_new.vat_rate_bp then perform private.reprice_products(null, null, null, null); end if;
  if v_old.direct_payments_enabled is distinct from v_new.direct_payments_enabled then perform private.refresh_all_supplier_selling(); end if;
  return to_jsonb(v_new);
end $$;
revoke all on function public.admin_finance_settings(), public.admin_update_finance_settings(jsonb) from public, anon;
grant execute on function public.admin_finance_settings(), public.admin_update_finance_settings(jsonb) to authenticated;
