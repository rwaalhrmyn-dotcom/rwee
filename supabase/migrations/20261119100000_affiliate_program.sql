-- Affiliate (commission marketer) program.
-- * Marketers register with a verified e-mail and sign an electronic agreement (versioned, hashed, append-only).
-- * Two commission sides, both set by Rawaa when approving the marketer:
--     - sales_rate_bp: on orders placed through the marketer's referral link;
--     - supplier_rate_bp: on the sales of suppliers the marketer brought to the platform.
-- * Rawaa approves -> one-month trial -> Rawaa continues (active) or terminates.
-- * Each marketer has a referral link (?ref=CODE); orders placed through it are attributed.
-- * The marketer earns a share of Rawaa's NET realised commission on completed, paid, non-voided
--   orders, and it becomes payable only after Rawaa has actually collected that commission from
--   the supplier (the commission invoice is paid). No profit -> nothing is owed.

-- ---------------------------------------------------------------- contract versions
create table if not exists public.affiliate_contract_versions (
  version_id text primary key check (version_id ~ '^[a-z0-9-]{6,80}$'),
  title text not null,
  body_ar text not null check (length(body_ar) between 100 and 30000),
  body_sha256 text not null check (body_sha256 = encode(sha256(convert_to(body_ar,'UTF8')),'hex')),
  published boolean not null default false,
  is_current boolean not null default false,
  published_at timestamptz,
  legal_review_status text not null default 'pending' check (legal_review_status in ('pending','approved')),
  legal_reviewer text, legal_reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (not is_current or published)
);
create unique index if not exists affiliate_contract_one_current on public.affiliate_contract_versions(is_current) where is_current;
alter table public.affiliate_contract_versions enable row level security;
revoke all on public.affiliate_contract_versions from public, anon, authenticated;

-- ---------------------------------------------------------------- settings
alter table private.finance_settings add column if not exists affiliate_default_rate_bp integer not null default 2000 check (affiliate_default_rate_bp between 0 and 5000);
alter table private.finance_settings add column if not exists affiliate_default_supplier_rate_bp integer not null default 1000 check (affiliate_default_supplier_rate_bp between 0 and 5000);
alter table private.finance_settings add column if not exists affiliate_trial_days integer not null default 30 check (affiliate_trial_days between 7 and 180);
alter table private.finance_settings add column if not exists affiliate_cookie_days integer not null default 30 check (affiliate_cookie_days between 1 and 90);
alter table private.finance_settings add column if not exists affiliate_min_payout_halalas integer not null default 10000 check (affiliate_min_payout_halalas between 0 and 1000000);

-- ---------------------------------------------------------------- marketers
create table if not exists public.affiliates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id),
  email text not null,
  code text not null unique check (code ~ '^[A-Z0-9]{6,12}$'),
  full_name text not null check (length(btrim(full_name)) between 3 and 120),
  phone text check (phone is null or phone ~ '^05[0-9]{8}$'),
  city text,
  channels text check (channels is null or length(channels) <= 500),
  bank_name text check (bank_name is null or length(btrim(bank_name)) between 2 and 120),
  iban text check (iban is null or iban ~ '^SA[0-9]{22}$'),
  iban_valid boolean generated always as (private.is_valid_sa_iban(iban)) stored,
  account_holder_name text check (account_holder_name is null or length(btrim(account_holder_name)) between 3 and 120),
  status text not null default 'pending' check (status in ('pending','trial','active','suspended','terminated','rejected')),
  status_reason text,
  sales_rate_bp integer not null check (sales_rate_bp between 0 and 5000),
  supplier_rate_bp integer not null check (supplier_rate_bp between 0 and 5000),
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  activated_at timestamptz,
  terminated_at timestamptz,
  decided_by uuid,
  contract_version text references public.affiliate_contract_versions(version_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.affiliates enable row level security;
revoke all on public.affiliates from public, anon, authenticated;

create table if not exists private.affiliate_contract_acceptances (
  id bigint generated always as identity primary key,
  affiliate_id uuid not null references public.affiliates(id),
  user_id uuid not null,
  version_id text not null references public.affiliate_contract_versions(version_id),
  body_sha256 text not null,
  signer_full_name text not null,
  session_id uuid,
  user_agent text,
  ip text,
  accepted_at timestamptz not null default now()
);
alter table private.affiliate_contract_acceptances enable row level security;
revoke all on private.affiliate_contract_acceptances from public, anon, authenticated;
create trigger affiliate_acceptances_append_only before update or delete on private.affiliate_contract_acceptances
  for each row execute function private.block_mutation();

create table if not exists private.affiliate_clicks (
  affiliate_id uuid not null references public.affiliates(id),
  day date not null,
  clicks integer not null default 0,
  primary key (affiliate_id, day)
);
alter table private.affiliate_clicks enable row level security;
revoke all on private.affiliate_clicks from public, anon, authenticated;

-- attribution on the order (snapshot of the marketer's rate at the time of the order)
alter table public.orders add column if not exists affiliate_id uuid references public.affiliates(id);
alter table public.orders add column if not exists affiliate_rate_bp integer;
alter table public.orders add column if not exists affiliate_attributed_at timestamptz;
alter table public.orders add column if not exists affiliate_void_reason text;
create index if not exists orders_affiliate_idx on public.orders(affiliate_id) where affiliate_id is not null;

-- supplier referral: the marketer's code is captured on the seller application and copied to the
-- supplier when it is created (rate snapshot); Rawaa can also set/clear it manually.
alter table public.seller_applications add column if not exists affiliate_id uuid references public.affiliates(id);
alter table public.suppliers add column if not exists referred_by_affiliate uuid references public.affiliates(id);
alter table public.suppliers add column if not exists affiliate_rate_bp integer;
alter table public.suppliers add column if not exists affiliate_referred_at timestamptz;

create or replace function private.trg_supplier_affiliate() returns trigger language plpgsql security definer set search_path='' as $$
declare v_aff uuid;
begin
  if new.referred_by_affiliate is null then
    select sa.affiliate_id into v_aff from public.seller_applications sa
     where sa.owner_id = new.owner_id and sa.affiliate_id is not null order by sa.created_at desc limit 1;
    if v_aff is not null and not exists(select 1 from public.affiliates a where a.id=v_aff and a.user_id=new.owner_id) then
      new.referred_by_affiliate := v_aff;
      new.affiliate_rate_bp := (select a.supplier_rate_bp from public.affiliates a where a.id=v_aff);
      new.affiliate_referred_at := now();
    end if;
  end if;
  return new;
end $$;
drop trigger if exists supplier_affiliate on public.suppliers;
create trigger supplier_affiliate before insert on public.suppliers for each row execute function private.trg_supplier_affiliate();

create table if not exists public.affiliate_payouts (
  id uuid primary key default gen_random_uuid(),
  affiliate_id uuid not null references public.affiliates(id),
  amount_halalas bigint not null check (amount_halalas > 0),
  reference text not null check (length(btrim(reference)) between 3 and 120),
  note text,
  paid_by uuid,
  paid_at timestamptz not null default now()
);
alter table public.affiliate_payouts enable row level security;
revoke all on public.affiliate_payouts from public, anon, authenticated;
create trigger affiliate_payouts_append_only before update or delete on public.affiliate_payouts
  for each row execute function private.block_mutation();

-- ---------------------------------------------------------------- helpers
-- Effective status: a trial whose end date passed without an admin decision stops earning.
create or replace function private.affiliate_effective_status(a public.affiliates) returns text
language sql stable set search_path='' as $$
  select case when a.status = 'trial' and a.trial_ends_at is not null and now() > a.trial_ends_at then 'trial_ended' else a.status end $$;

-- Was the marketer allowed to earn when this order was placed? (trial, or after being continued,
-- and before termination.) Orders in an undecided gap after the trial earn nothing.
create or replace function private.affiliate_window_ok(a public.affiliates, p_at timestamptz) returns boolean
language sql stable set search_path='' as $$
  select a.trial_started_at is not null and p_at >= a.trial_started_at
    and (p_at <= a.trial_ends_at or (a.activated_at is not null and p_at >= a.activated_at))
    and (a.terminated_at is null or p_at < a.terminated_at) $$;

-- Per-order earning lines for both sides: 'sales' (order came through the link) and 'supplier'
-- (order belongs to a supplier the marketer referred). Earning = share of Rawaa's NET commission
-- (accruals minus refund reversals). state: void | pending (order not completed/paid) |
-- awaiting_collection (supplier has not paid Rawaa's invoice yet) | payable.
create or replace function private.affiliate_order_lines(p_affiliate uuid) returns table(order_id uuid, side text, created_at timestamptz,
  order_status text, payment_status text, payable_halalas bigint, rawaa_commission_halalas bigint, rate_bp integer,
  earning_halalas bigint, state text, void_reason text)
language sql stable security definer set search_path='' as $$
  with a as (select * from public.affiliates where id = p_affiliate),
  src as (
    select o.*, 'sales'::text as side, o.affiliate_rate_bp as rate from public.orders o where o.affiliate_id = p_affiliate
    union all
    select o.*, 'supplier'::text, s.affiliate_rate_bp from public.orders o join public.suppliers s on s.id = o.supplier_id
     where s.referred_by_affiliate = p_affiliate and o.payment_mode = 'supplier_direct')
  select o.id, o.side, o.created_at, o.status, o.payment_status, o.payable_halalas,
    coalesce(c.net,0), coalesce(o.rate,0),
    case when o.affiliate_void_reason is not null or not private.affiliate_window_ok(a, o.created_at) then 0
         else greatest(round(coalesce(c.net,0)::numeric * coalesce(o.rate,0) / 10000),0)::bigint end,
    case when o.affiliate_void_reason is not null or o.status = 'cancelled' or not private.affiliate_window_ok(a, o.created_at) then 'void'
         when coalesce(c.accruals,0) = 0 then 'pending'
         when c.unpaid_invoices > 0 then 'awaiting_collection'
         else 'payable' end,
    coalesce(o.affiliate_void_reason, case when not private.affiliate_window_ok(a, o.created_at) then 'خارج مدة سريان الاتفاقية' end)
  from src o cross join a
  left join lateral (
    select sum(e.total_commission_halalas) as net, count(*) filter (where e.kind='accrual') as accruals,
      count(*) filter (where e.kind='accrual' and (e.invoice_id is null or not exists(
        select 1 from public.commission_invoices i where i.id=e.invoice_id and i.status='paid'))) as unpaid_invoices
    from public.commission_entries e where e.order_id=o.id) c on true $$;

create or replace function private.affiliate_summary(p_affiliate uuid) returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object(
    'clicks', (select coalesce(sum(clicks),0) from private.affiliate_clicks where affiliate_id=p_affiliate),
    'clicks_30d', (select coalesce(sum(clicks),0) from private.affiliate_clicks where affiliate_id=p_affiliate and day > private.ksa_today() - 30),
    'orders', count(*) filter (where l.side='sales'),
    'supplier_orders', count(*) filter (where l.side='supplier'),
    'referred_suppliers', (select count(*) from public.suppliers where referred_by_affiliate=p_affiliate),
    'completed_orders', count(*) filter (where l.state in ('awaiting_collection','payable')),
    'sales_side_halalas', coalesce(sum(l.earning_halalas) filter (where l.side='sales' and l.state <> 'void'),0),
    'supplier_side_halalas', coalesce(sum(l.earning_halalas) filter (where l.side='supplier' and l.state <> 'void'),0),
    'sales_halalas', coalesce(sum(l.payable_halalas) filter (where l.state <> 'void'),0),
    'pending_halalas', coalesce(sum(l.earning_halalas) filter (where l.state = 'pending'),0),
    'awaiting_collection_halalas', coalesce(sum(l.earning_halalas) filter (where l.state = 'awaiting_collection'),0),
    'payable_total_halalas', coalesce(sum(l.earning_halalas) filter (where l.state = 'payable'),0),
    'paid_halalas', (select coalesce(sum(amount_halalas),0) from public.affiliate_payouts where affiliate_id=p_affiliate),
    'balance_halalas', coalesce(sum(l.earning_halalas) filter (where l.state = 'payable'),0)
                        - (select coalesce(sum(amount_halalas),0) from public.affiliate_payouts where affiliate_id=p_affiliate))
  from private.affiliate_order_lines(p_affiliate) l $$;

create or replace function private.new_affiliate_code() returns text
language plpgsql volatile set search_path='' as $$
declare c text;
begin
  loop
    c := 'RW' || upper(substr(translate(encode(extensions.gen_random_bytes(8),'base64'),'+/=0O1Il','ABCDEFGH'),1,6));
    exit when not exists(select 1 from public.affiliates where code=c);
  end loop;
  return c;
end $$;

-- ---------------------------------------------------------------- public / marketer RPCs
create or replace function public.current_affiliate_contract() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('version_id', version_id, 'title', title, 'body_ar', body_ar, 'body_sha256', body_sha256)
  from public.affiliate_contract_versions where is_current $$;

create or replace function public.affiliate_terms_public() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('rate_bp', affiliate_default_rate_bp, 'supplier_rate_bp', affiliate_default_supplier_rate_bp, 'trial_days', affiliate_trial_days, 'cookie_days', affiliate_cookie_days,
    'min_payout_halalas', affiliate_min_payout_halalas) from private.finance_settings where id $$;

create or replace function public.affiliate_register(p jsonb, p_contract_version text, p_contract_hash text, p_signer_name text, p_agreed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.affiliate_contract_versions; a public.affiliates; s private.finance_settings := private.fin();
  v_iban text := nullif(private.normalize_iban(p->>'iban'),''); v_phone text := nullif(regexp_replace(coalesce(p->>'phone',''), '\D', '', 'g'),'');
  v_email text;
begin
  if auth.uid() is null or not private.has_verified_session() then raise exception 'login required' using errcode='42501'; end if;
  select u.email::text into v_email from auth.users u where u.id=auth.uid() and u.email is not null and u.email_confirmed_at is not null;
  if v_email is null then raise exception 'a verified e-mail address is required to register as a marketer'; end if;
  if coalesce(p_agreed,false) is not true then raise exception 'explicit agreement to the marketer contract is required'; end if;
  select * into v from public.affiliate_contract_versions where is_current;
  if v.version_id is null or v.version_id <> p_contract_version or v.body_sha256 <> p_contract_hash then
    raise exception 'contract version changed; reload and read the current contract';
  end if;
  if length(btrim(coalesce(p_signer_name,''))) < 3 or btrim(p_signer_name) <> btrim(coalesce(p->>'full_name','')) then
    raise exception 'signer name must match the full name';
  end if;
  if v_phone ~ '^9665[0-9]{8}$' then v_phone := '0' || substr(v_phone, 4); end if;
  if v_iban is not null and not private.is_valid_sa_iban(v_iban) then raise exception 'invalid IBAN'; end if;
  if exists(select 1 from public.affiliates where user_id=auth.uid()) then raise exception 'already registered as a marketer'; end if;
  if v_phone is not null and v_phone !~ '^05[0-9]{8}$' then raise exception 'invalid mobile number'; end if;
  insert into public.affiliates(user_id, email, code, full_name, phone, city, channels, bank_name, iban, account_holder_name, sales_rate_bp, supplier_rate_bp, contract_version)
  values (auth.uid(), lower(v_email), private.new_affiliate_code(), btrim(p->>'full_name'), v_phone, nullif(btrim(coalesce(p->>'city','')),''),
    nullif(btrim(coalesce(p->>'channels','')),''), nullif(btrim(coalesce(p->>'bank_name','')),''), v_iban,
    nullif(btrim(coalesce(p->>'account_holder_name','')),''), s.affiliate_default_rate_bp, s.affiliate_default_supplier_rate_bp, v.version_id)
  returning * into a;
  insert into private.affiliate_contract_acceptances(affiliate_id, user_id, version_id, body_sha256, signer_full_name, session_id, user_agent, ip)
  values (a.id, auth.uid(), v.version_id, v.body_sha256, btrim(p_signer_name), nullif(auth.jwt()->>'session_id','')::uuid,
    left(private.request_header('user-agent'), 300), left(split_part(coalesce(private.request_header('x-forwarded-for'),''), ',', 1), 64));
  perform private.raise_finance_alert('affiliate_application','info',null,null,null,'طلب انضمام مسوّق بالعمولة: '||a.full_name, jsonb_build_object('affiliate_id',a.id), 'affapp:'||a.id);
  return jsonb_build_object('id', a.id, 'status', a.status, 'code', a.code);
end $$;

create or replace function public.affiliate_update_payout_details(p_bank text, p_iban text, p_holder text) returns void
language plpgsql security definer set search_path='' as $$
declare v_iban text := nullif(private.normalize_iban(p_iban),'');
begin
  if v_iban is not null and not private.is_valid_sa_iban(v_iban) then raise exception 'invalid IBAN'; end if;
  update public.affiliates set bank_name=nullif(btrim(coalesce(p_bank,'')),''), iban=v_iban, account_holder_name=nullif(btrim(coalesce(p_holder,'')),''), updated_at=now()
  where user_id=auth.uid() and private.has_verified_session();
  if not found then raise exception 'marketer not found'; end if;
  perform private.fin_audit('supplier', (select id::text from public.affiliates where user_id=auth.uid()), 'affiliate_payout_details', null,
    jsonb_build_object('iban', private.mask_iban(v_iban)));
end $$;

create or replace function public.my_affiliate() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a public.affiliates;
begin
  if auth.uid() is null then return null; end if;
  select * into a from public.affiliates where user_id=auth.uid();
  if not found then return null; end if;
  return jsonb_build_object(
    'profile', jsonb_build_object('id', a.id, 'code', a.code, 'full_name', a.full_name, 'phone', a.phone, 'city', a.city, 'status', a.status,
       'effective_status', private.affiliate_effective_status(a), 'status_reason', a.status_reason, 'email', a.email,
       'sales_rate_bp', a.sales_rate_bp, 'supplier_rate_bp', a.supplier_rate_bp, 'trial_started_at', a.trial_started_at, 'trial_ends_at', a.trial_ends_at, 'activated_at', a.activated_at, 'terminated_at', a.terminated_at,
       'bank_name', a.bank_name, 'iban_masked', private.mask_iban(a.iban), 'account_holder_name', a.account_holder_name, 'created_at', a.created_at),
    'summary', private.affiliate_summary(a.id),
    'terms', public.affiliate_terms_public(),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('ref', left(l.order_id::text,8), 'side', l.side, 'created_at', l.created_at, 'order_status', l.order_status,
        'payable_halalas', l.payable_halalas, 'earning_halalas', l.earning_halalas, 'state', l.state, 'void_reason', l.void_reason) order by l.created_at desc),'[]'::jsonb)
       from private.affiliate_order_lines(a.id) l),
    'suppliers', (select coalesce(jsonb_agg(jsonb_build_object('name', s.name, 'referred_at', s.affiliate_referred_at, 'rate_bp', s.affiliate_rate_bp,
        'selling', s.selling_enabled) order by s.affiliate_referred_at desc),'[]'::jsonb) from public.suppliers s where s.referred_by_affiliate=a.id),
    'payouts', (select coalesce(jsonb_agg(jsonb_build_object('amount_halalas', amount_halalas, 'reference', reference, 'paid_at', paid_at) order by paid_at desc),'[]'::jsonb)
       from public.affiliate_payouts where affiliate_id=a.id),
    'contract', (select jsonb_build_object('version_id', c.version_id, 'title', v.title, 'body_ar', v.body_ar, 'body_sha256', c.body_sha256,
        'signer', c.signer_full_name, 'accepted_at', c.accepted_at)
       from private.affiliate_contract_acceptances c join public.affiliate_contract_versions v on v.version_id=c.version_id
       where c.affiliate_id=a.id order by c.accepted_at desc limit 1));
end $$;

-- Anonymous visit through a referral link (informational only; earnings come from orders).
create or replace function public.track_affiliate_click(p_code text) returns boolean
language plpgsql security definer set search_path='' as $$
declare a public.affiliates;
begin
  select * into a from public.affiliates where code=upper(btrim(coalesce(p_code,'')));
  if not found or private.affiliate_effective_status(a) not in ('trial','active') then return false; end if;
  insert into private.affiliate_clicks(affiliate_id, day, clicks) values (a.id, private.ksa_today(), 1)
  on conflict (affiliate_id, day) do update set clicks = least(private.affiliate_clicks.clicks + 1, 1000000);
  return true;
end $$;

-- Attach a referral to the customer's own fresh order. Anti-fraud: no self-referral (same account
-- or same phone), only unpaid non-cancelled orders, first attribution wins, marketer must be in
-- an earning status, and the supplier cannot refer its own sales.
create or replace function public.attach_order_affiliate(p_order uuid, p_code text) returns text
language plpgsql security definer set search_path='' as $$
declare o public.orders; a public.affiliates;
begin
  select * into o from public.orders where id=p_order for update;
  if not found or o.customer_id is distinct from auth.uid() or not private.has_verified_session() then raise exception 'forbidden' using errcode='42501'; end if;
  if o.affiliate_id is not null then return 'already_attributed'; end if;
  if o.payment_status='paid' or o.status='cancelled' or o.created_at < now() - interval '1 hour' then return 'not_eligible'; end if;
  select * into a from public.affiliates where code=upper(btrim(coalesce(p_code,'')));
  if not found or private.affiliate_effective_status(a) not in ('trial','active') then return 'invalid_code'; end if;
  if a.user_id = auth.uid() or a.phone = regexp_replace(coalesce(o.phone,''),'\D','','g') then
    perform private.raise_finance_alert('affiliate_self_referral','warning',null,o.id,null,'محاولة إحالة ذاتية من مسوّق',
      jsonb_build_object('affiliate_id',a.id), 'selfref:'||o.id);
    return 'self_referral_blocked';
  end if;
  if exists(select 1 from public.suppliers s where s.id=o.supplier_id and s.owner_id=a.user_id) then return 'own_supplier_blocked'; end if;
  update public.orders set affiliate_id=a.id, affiliate_rate_bp=a.sales_rate_bp, affiliate_attributed_at=now() where id=o.id;
  return 'attributed';
end $$;

-- Supplier referral: the applicant's own pending application records the marketer's code.
create or replace function public.attach_application_affiliate(p_code text) returns text
language plpgsql security definer set search_path='' as $$
declare a public.affiliates; v_app uuid;
begin
  if auth.uid() is null or not private.has_verified_session() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into a from public.affiliates where code=upper(btrim(coalesce(p_code,'')));
  if not found or private.affiliate_effective_status(a) not in ('trial','active') then return 'invalid_code'; end if;
  if a.user_id = auth.uid() then return 'self_referral_blocked'; end if;
  select id into v_app from public.seller_applications where owner_id=auth.uid() and status='pending' and affiliate_id is null
   order by created_at desc limit 1 for update;
  if v_app is null then return 'no_pending_application'; end if;
  update public.seller_applications set affiliate_id=a.id where id=v_app;
  return 'attributed';
end $$;

-- ---------------------------------------------------------------- admin RPCs
create or replace function public.admin_affiliates() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select jsonb_build_object('id', a.id, 'code', a.code, 'full_name', a.full_name, 'phone', a.phone, 'city', a.city, 'channels', a.channels,
      'email', a.email,
      'suppliers', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'rate_bp', s.affiliate_rate_bp)),'[]'::jsonb) from public.suppliers s where s.referred_by_affiliate=a.id), 'status', a.status, 'effective_status', private.affiliate_effective_status(a),
      'status_reason', a.status_reason, 'sales_rate_bp', a.sales_rate_bp, 'supplier_rate_bp', a.supplier_rate_bp, 'trial_started_at', a.trial_started_at, 'trial_ends_at', a.trial_ends_at,
      'activated_at', a.activated_at, 'terminated_at', a.terminated_at, 'bank_name', a.bank_name, 'iban', a.iban, 'iban_valid', a.iban_valid,
      'account_holder_name', a.account_holder_name, 'contract_version', a.contract_version, 'created_at', a.created_at,
      'signed_at', (select max(c.accepted_at) from private.affiliate_contract_acceptances c where c.affiliate_id=a.id),
      'summary', private.affiliate_summary(a.id))
    from public.affiliates a order by (private.affiliate_effective_status(a) in ('pending','trial_ended')) desc, a.created_at desc;
end $$;

create or replace function public.admin_affiliate_orders(p_affiliate uuid) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select to_jsonb(l) || jsonb_build_object('supplier', (select s.name from public.suppliers s join public.orders o on o.supplier_id=s.id where o.id=l.order_id),
      'customer_phone', (select o.phone from public.orders o where o.id=l.order_id))
    from private.affiliate_order_lines(p_affiliate) l order by l.created_at desc;
end $$;

-- approve (starts the trial; both rates required) | continue (-> active) | suspend | reactivate |
-- terminate | reject | set_rate. Rate changes apply to future orders / newly referred suppliers only.
create or replace function public.admin_affiliate_decide(p_affiliate uuid, p_action text, p_note text default null,
  p_sales_rate_bp integer default null, p_supplier_rate_bp integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.affiliates; s private.finance_settings := private.fin(); v_new text;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if (p_sales_rate_bp is not null and p_sales_rate_bp not between 0 and 5000) or (p_supplier_rate_bp is not null and p_supplier_rate_bp not between 0 and 5000) then
    raise exception 'rates must be between 0%% and 50%%'; end if;
  select * into a from public.affiliates where id=p_affiliate for update;
  if not found then raise exception 'marketer not found'; end if;
  if p_action = 'approve' then
    if a.status <> 'pending' then raise exception 'only pending applications can be approved'; end if;
    if p_sales_rate_bp is null or p_supplier_rate_bp is null then raise exception 'set both commission rates (sales and supplier referral) to approve'; end if;
    update public.affiliates set status='trial', trial_started_at=now(), trial_ends_at=now() + make_interval(days => s.affiliate_trial_days),
      sales_rate_bp=p_sales_rate_bp, supplier_rate_bp=p_supplier_rate_bp, status_reason=null, decided_by=auth.uid(), updated_at=now() where id=a.id;
    v_new := 'trial';
  elsif p_action = 'reject' then
    if a.status <> 'pending' then raise exception 'only pending applications can be rejected'; end if;
    update public.affiliates set status='rejected', status_reason=coalesce(nullif(btrim(p_note),''),'لم يُقبل الطلب'), decided_by=auth.uid(), updated_at=now() where id=a.id;
    v_new := 'rejected';
  elsif p_action = 'continue' then
    if a.status not in ('trial','suspended') then raise exception 'only trial or suspended marketers can be continued'; end if;
    update public.affiliates set status='active', activated_at=coalesce(activated_at, now()), status_reason=null,
      sales_rate_bp=coalesce(p_sales_rate_bp, sales_rate_bp), supplier_rate_bp=coalesce(p_supplier_rate_bp, supplier_rate_bp),
      decided_by=auth.uid(), updated_at=now() where id=a.id;
    v_new := 'active';
  elsif p_action = 'suspend' then
    if a.status not in ('trial','active') then raise exception 'only trial or active marketers can be suspended'; end if;
    if nullif(btrim(p_note),'') is null then raise exception 'reason required'; end if;
    update public.affiliates set status='suspended', status_reason=btrim(p_note), decided_by=auth.uid(), updated_at=now() where id=a.id;
    v_new := 'suspended';
  elsif p_action = 'reactivate' then
    if a.status <> 'suspended' then raise exception 'only suspended marketers can be reactivated'; end if;
    update public.affiliates set status=case when a.activated_at is null and a.trial_ends_at > now() then 'trial' else 'active' end,
      activated_at=case when a.activated_at is null and a.trial_ends_at > now() then null else coalesce(a.activated_at, now()) end,
      status_reason=null, decided_by=auth.uid(), updated_at=now() where id=a.id returning status into v_new;
  elsif p_action = 'terminate' then
    if a.status in ('terminated','rejected') then raise exception 'already closed'; end if;
    if nullif(btrim(p_note),'') is null then raise exception 'reason required'; end if;
    update public.affiliates set status='terminated', status_reason=btrim(p_note), terminated_at=now(), decided_by=auth.uid(), updated_at=now() where id=a.id;
    v_new := 'terminated';
  elsif p_action = 'set_rate' then
    if p_sales_rate_bp is null and p_supplier_rate_bp is null then raise exception 'no rate given'; end if;
    update public.affiliates set sales_rate_bp=coalesce(p_sales_rate_bp, sales_rate_bp), supplier_rate_bp=coalesce(p_supplier_rate_bp, supplier_rate_bp), updated_at=now() where id=a.id;
    v_new := a.status;
  else raise exception 'invalid action'; end if;
  perform private.fin_audit('supplier', a.id::text, 'affiliate_'||p_action,
    jsonb_build_object('status',a.status,'sales_rate_bp',a.sales_rate_bp,'supplier_rate_bp',a.supplier_rate_bp),
    jsonb_build_object('status',v_new,'sales_rate_bp',coalesce(p_sales_rate_bp,a.sales_rate_bp),'supplier_rate_bp',coalesce(p_supplier_rate_bp,a.supplier_rate_bp),'note',p_note));
  perform private.admin_log('affiliate_'||p_action, 'affiliate', a.id::text);
  update private.finance_alerts set resolved_at=now(), resolved_by=auth.uid(), resolution_note=p_action
   where kind='affiliate_application' and details->>'affiliate_id' = a.id::text and resolved_at is null;
  return jsonb_build_object('status', v_new);
end $$;

-- Link (or unlink with null) a supplier to the marketer who brought it; snapshots the marketer's supplier rate.
create or replace function public.admin_set_supplier_affiliate(p_supplier uuid, p_affiliate uuid) returns void
language plpgsql security definer set search_path='' as $$
declare s public.suppliers; a public.affiliates;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into s from public.suppliers where id=p_supplier for update;
  if not found then raise exception 'supplier not found'; end if;
  if p_affiliate is not null then
    select * into a from public.affiliates where id=p_affiliate;
    if not found then raise exception 'marketer not found'; end if;
    if a.user_id = s.owner_id then raise exception 'a marketer cannot refer their own supplier account'; end if;
  end if;
  update public.suppliers set referred_by_affiliate=p_affiliate, affiliate_rate_bp=case when p_affiliate is null then null else a.supplier_rate_bp end,
    affiliate_referred_at=case when p_affiliate is null then null else now() end where id=p_supplier;
  perform private.fin_audit('supplier', p_supplier::text, 'supplier_affiliate_set', jsonb_build_object('affiliate', s.referred_by_affiliate),
    jsonb_build_object('affiliate', p_affiliate));
end $$;

-- Void (fraud / policy breach) or restore one attributed order's earning.
create or replace function public.admin_void_affiliate_order(p_order uuid, p_reason text) returns void
language plpgsql security definer set search_path='' as $$
declare o public.orders;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into o from public.orders where id=p_order for update;
  if not found or o.affiliate_id is null then raise exception 'order has no marketer'; end if;
  update public.orders set affiliate_void_reason=nullif(btrim(coalesce(p_reason,'')),'') where id=o.id;
  perform private.fin_audit('commission', o.id::text, case when nullif(btrim(coalesce(p_reason,'')),'') is null then 'affiliate_order_restored' else 'affiliate_order_voided' end,
    jsonb_build_object('void_reason', o.affiliate_void_reason), jsonb_build_object('void_reason', p_reason));
end $$;

-- Record a payout transferred to the marketer; never more than the payable balance.
create or replace function public.admin_record_affiliate_payout(p_affiliate uuid, p_amount_halalas bigint, p_reference text, p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_bal bigint; r public.affiliate_payouts;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  perform 1 from public.affiliates where id=p_affiliate for update;
  if not found then raise exception 'marketer not found'; end if;
  v_bal := (private.affiliate_summary(p_affiliate)->>'balance_halalas')::bigint;
  if p_amount_halalas is null or p_amount_halalas <= 0 or p_amount_halalas > v_bal then
    raise exception 'payout exceeds the payable balance (% halalas)', v_bal; end if;
  insert into public.affiliate_payouts(affiliate_id, amount_halalas, reference, note, paid_by)
  values (p_affiliate, p_amount_halalas, btrim(p_reference), p_note, auth.uid()) returning * into r;
  perform private.fin_audit('payment', p_affiliate::text, 'affiliate_payout', null, to_jsonb(r));
  return to_jsonb(r);
end $$;

grant execute on function public.current_affiliate_contract(), public.affiliate_terms_public(), public.track_affiliate_click(text) to anon, authenticated;
revoke all on function public.affiliate_register(jsonb,text,text,text,boolean), public.affiliate_update_payout_details(text,text,text), public.my_affiliate(),
  public.attach_order_affiliate(uuid,text), public.attach_application_affiliate(text), public.admin_affiliates(), public.admin_affiliate_orders(uuid),
  public.admin_affiliate_decide(uuid,text,text,integer,integer), public.admin_set_supplier_affiliate(uuid,uuid), public.admin_void_affiliate_order(uuid,text),
  public.admin_record_affiliate_payout(uuid,bigint,text,text) from public, anon;
grant execute on function public.affiliate_register(jsonb,text,text,text,boolean), public.affiliate_update_payout_details(text,text,text), public.my_affiliate(),
  public.attach_order_affiliate(uuid,text), public.attach_application_affiliate(text), public.admin_affiliates(), public.admin_affiliate_orders(uuid),
  public.admin_affiliate_decide(uuid,text,text,integer,integer), public.admin_set_supplier_affiliate(uuid,uuid), public.admin_void_affiliate_order(uuid,text),
  public.admin_record_affiliate_payout(uuid,bigint,text,text) to authenticated;
revoke all on function private.affiliate_order_lines(uuid), private.affiliate_summary(uuid), private.new_affiliate_code(),
  private.affiliate_effective_status(public.affiliates), private.affiliate_window_ok(public.affiliates, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------- agreement v1 (electronic signature)
insert into public.affiliate_contract_versions(version_id, title, body_ar, body_sha256, published, is_current, published_at)
select 'rw-aff-v1-2026-11', t.title, t.body, encode(sha256(convert_to(t.body,'UTF8')),'hex'), true, true, now()
from (select 'اتفاقية التسويق بالعمولة عبر منصة رواء الحرمين'::text as title, $c$اتفاقية التسويق بالعمولة عبر منصة رواء الحرمين

أُبرمت هذه الاتفاقية إلكترونياً بين: منصة رِواء الحرمين (سجل تجاري رقم 7041122404) ويُشار إليها بـ«المنصة»، وبين الشخص المسجّل في نموذج الانضمام ويُشار إليه بـ«المسوّق». ويقرّ الطرفان بأهليتهما للتعاقد، وبأن قبول المسوّق الإلكتروني لهذه الاتفاقية توقيعٌ ملزمٌ له وفق نظام التعاملات الإلكترونية في المملكة العربية السعودية.

البند الأول: الغرض
يقوم المسوّق بالترويج لمنتجات المنصة وباستقطاب الموردين إليها عبر رابط إحالة خاص به، مقابل عمولة تُحتسب حصراً على الأرباح المتحققة فعلياً للمنصة من الطلبات الواردة عن طريق رابطه وفق أحكام هذه الاتفاقية. ولا تنشئ هذه الاتفاقية علاقة عمل أو وكالة أو شراكة بين الطرفين، ولا يحق للمسوّق التعاقد أو الالتزام باسم المنصة.

البند الثاني: فترة التجربة
1. تبدأ فترة تجربة مدتها شهر واحد (30 يوماً) من تاريخ اعتماد المنصة لطلب الانضمام.
2. يستحق المسوّق خلال فترة التجربة العمولة على الطلبات المؤهلة وفق البند الرابع.
3. بانتهاء فترة التجربة تُقرر المنصة استمرار الاتفاقية أو إنهاءها، ويُبلَّغ المسوّق بالقرار عبر لوحته. ولا تُحتسب أي عمولة على طلبات تُنشأ بعد انتهاء فترة التجربة ما لم تقرر المنصة الاستمرار.
4. إنهاء الاتفاقية بعد فترة التجربة أو خلالها لا يُسقط حق المسوّق في عمولات الطلبات المؤهلة التي تمت قبل الإنهاء، ما لم يثبت تحايل وفق البند السادس.

البند الثالث: رابط الإحالة والتتبع
1. تمنح المنصة المسوّق رمزاً ورابط إحالة فريداً، ولوحة تحكم يتابع فيها الزيارات والطلبات والأرباح والمدفوعات.
2. يُنسب المورد للمسوّق إذا قدّم طلب انضمامه عبر رابط المسوّق واعتمدته المنصة، ويُنسب الطلب للمسوّق إذا وصل العميل عبر رابطه وأتم الطلب خلال 30 يوماً من آخر زيارة عبر الرابط، ما لم تُنسب الزيارة لاحقاً لمسوّق آخر (العبرة بآخر رابط).
3. سجلات المنصة الإلكترونية هي المرجع المعتمد في احتساب الزيارات والطلبات والعمولات، ويحق للمسوّق الاعتراض عليها كتابياً خلال 15 يوماً من ظهورها في لوحته.

البند الرابع: العمولة وشروط استحقاقها
1. للمسوّق عمولة من جانبين تحدد المنصة نسبة كل منهما عند اعتماد انضمامه وتظهر في لوحته، وتسري أي نسبة جديدة على الطلبات أو الموردين اللاحقين فقط:
   أ. عمولة المبيعات: نسبة من صافي عمولة المنصة المتحققة من الطلبات الواردة عبر رابطه.
   ب. عمولة جذب الموردين: نسبة من صافي عمولة المنصة المتحققة من مبيعات المورد الذي انضم للمنصة عبر رابطه واعتمدته المنصة، طوال مدة سريان هذه الاتفاقية.
   وصافي عمولة المنصة هو ما تحصل عليه المنصة من المورد بعد خصم أي استرجاع أو تسوية، ولا تُحتسب العمولة على قيمة الطلب أو الضريبة أو التوصيل.
2. لا تستحق العمولة إلا باجتماع الشروط الآتية: أن يكتمل الطلب ويُسلَّم ويُدفع، وألا يُلغى أو يُسترجع، وأن تكون المنصة قد حصّلت فعلياً عمولتها عن هذا الطلب من المورد.
3. لا يحق للمسوّق المطالبة بأي مبلغ مالي من أي نوع، ومنها الأجر أو التعويض أو المصروفات أو مقابل الجهد أو الإعلان، ما لم تحقق المنصة ربحاً فعلياً من طلبات واردة عن طريقه وفق هذا البند. وإذا لم يتحقق ربح فلا يستحق المسوّق شيئاً.
4. إذا استُرجع طلب كلياً أو جزئياً بعد صرف عمولته، خُصم ما يقابله من مستحقات المسوّق اللاحقة.
5. يتحمل المسوّق أي ضرائب أو التزامات نظامية تترتب على دخله من هذه الاتفاقية.

البند الخامس: صرف المستحقات
1. تُصرف المستحقات القابلة للصرف شهرياً بتحويل بنكي إلى حساب باسم المسوّق نفسه، متى بلغت الحد الأدنى للصرف المعلن في لوحته.
2. يلتزم المسوّق بصحة بيانات حسابه البنكي، ولا تتحمل المنصة تبعات أي خطأ فيها.

البند السادس: مكافحة التحايل
يُعد تحايلاً، على سبيل المثال لا الحصر:
1. الشراء عبر رابطه لنفسه أو لأقاربه أو بحسابات وهمية أو متعددة بقصد الحصول على العمولة (الإحالة الذاتية).
2. إنشاء طلبات أو زيارات وهمية أو مؤتمتة، أو التلاعب بالروابط أو ملفات الارتباط أو سرقة إحالات الآخرين.
3. الإعلان المضلل أو الوعود غير الصحيحة بالأسعار أو العروض، أو استخدام اسم المنصة أو علامتها في إعلانات البحث المدفوعة أو نطاقات مشابهة دون إذن كتابي.
4. الرسائل المزعجة (السبام) أو انتحال صفة المنصة أو موظفيها أو مورديها.
5. التواطؤ مع مورد أو عميل للتلاعب بالطلبات أو الأسعار أو الاسترجاع، أو تسجيل موردين وهميين أو موردين يملكهم المسوّق نفسه أو تحت إدارته.
وعند ثبوت التحايل يحق للمنصة دون إنذار: إلغاء عمولة الطلبات المرتبطة به، واسترداد ما صُرف عنها، وإيقاف الحساب أو إنهاء الاتفاقية فوراً، مع حفظ حقها في المطالبة بالتعويض عن أي ضرر.

البند السابع: التزامات المسوّق
1. الالتزام بالأنظمة السعودية، ومنها نظام التجارة الإلكترونية ونظام حماية البيانات الشخصية وضوابط الإعلان.
2. الإفصاح للجمهور بأنه يحصل على عمولة من الإحالات.
3. عدم جمع بيانات العملاء أو استخدامها خارج الغرض المسموح.
4. المحافظة على سرية المعلومات غير المعلنة التي يطّلع عليها.

البند الثامن: التزامات المنصة
1. توفير رابط الإحالة ولوحة التتبع وإتاحة بيانات الطلبات والعمولات للمسوّق بشفافية.
2. احتساب العمولات وصرف المستحقات المؤهلة في مواعيدها وفق هذه الاتفاقية.
3. إبلاغ المسوّق بأي تعديل على الاتفاقية قبل سريانه، ويحق له إنهاء الاتفاقية إن لم يقبل التعديل.

البند التاسع: الإيقاف والإنهاء
1. يحق لأي من الطرفين إنهاء الاتفاقية في أي وقت بإشعار عبر المنصة.
2. يحق للمنصة إيقاف الحساب مؤقتاً للتحقق من أي نشاط مشتبه به، ولا تُصرف المستحقات المرتبطة بالنشاط محل التحقق حتى انتهائه.
3. لا يترتب على الإنهاء أي تعويض لأي طرف، مع مراعاة البند الثاني (فقرة 4) والبند السادس.

البند العاشر: أحكام عامة
1. تخضع هذه الاتفاقية لأنظمة المملكة العربية السعودية، ويُسعى لحل أي خلاف ودياً، وإلا فالاختصاص للجهات القضائية المختصة في المملكة.
2. تُحفظ نسخة إلكترونية من هذه الاتفاقية مع رقم الإصدار وبصمة النص وتاريخ ووقت القبول، ويحق للمسوّق الاطلاع عليها في أي وقت من لوحته.
3. لا يجوز للمسوّق التنازل عن حقوقه أو التزاماته بموجب هذه الاتفاقية للغير.$c$::text as body) t
where not exists (select 1 from public.affiliate_contract_versions);
