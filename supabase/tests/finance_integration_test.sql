-- Integration tests for supplier-direct payments, pricing, commissions and invoices.
-- Run against the local dev DB:  su postgres -c "psql -X -d rwaa_dev -f supabase/tests/finance_integration_test.sql"
-- Everything runs in one transaction that is rolled back at the end.
\set ON_ERROR_STOP 1
\pset pager off
begin;
set local client_min_messages = warning;

create schema test;
grant usage on schema test to public;
create table test.results (n serial primary key, scenario text, name text, ok boolean, detail text);
grant all on test.results to public; grant usage on sequence test.results_n_seq to public;
create table test.sessions (uid uuid primary key, sid uuid not null);
grant select on test.sessions to public;
create table test.ctx (k text primary key, v text);
grant all on test.ctx to public;

create function test.ok(p_scenario text, p_name text, p_ok boolean, p_detail text default null) returns void language sql as $$
  insert into test.results(scenario, name, ok, detail) values (p_scenario, p_name, coalesce(p_ok,false), p_detail) $$;
create function test.set(k text, v text) returns void language sql as $$ insert into test.ctx values (k, v) on conflict (k) do update set v=excluded.v $$;
create function test.get(k text) returns text language sql stable as $$ select v from test.ctx where ctx.k = get.k $$;
create function test.mk_user(p_uid uuid, p_email text, p_phone text) returns void language plpgsql as $$
declare v_sid uuid := gen_random_uuid(); begin
  insert into auth.users(id, email, email_confirmed_at, phone, phone_confirmed_at, encrypted_password)
  values (p_uid, p_email, now(), p_phone, now(), extensions.crypt('x', extensions.gen_salt('bf', 4)));
  insert into auth.sessions(id, user_id, aal) values (v_sid, p_uid, 'aal1');
  insert into auth.mfa_amr_claims(session_id, authentication_method) values (v_sid, 'password');
  insert into test.sessions values (p_uid, v_sid);
end $$;
create function test.as_user(p_uid uuid) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated', 'aal', 'aal1',
    'session_id', (select sid from test.sessions where uid=p_uid), 'amr', json_build_array(json_build_object('method','password')))::text, true);
  perform set_config('role', 'authenticated', true); end $$;
create function test.as_service() returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true); perform set_config('role', 'service_role', true); end $$;
create function test.as_anon() returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true); perform set_config('role', 'anon', true); end $$;
create function test.reset() returns void language plpgsql as $$ begin
  perform set_config('role', 'postgres', true); perform set_config('request.jwt.claims', '', true); end $$;
grant execute on all functions in schema test to public;

-- Deterministic clock for date-dependent billing rules (rolled back with the test).
create or replace function private.ksa_today() returns date language sql stable set search_path='' as $$
  select coalesce(nullif((select v from test.ctx where k='today'),''), (now() at time zone 'Asia/Riyadh')::date::text)::date $$;

-- ---------------------------------------------------------------- fixtures
do $$
declare v_admin uuid := '00000000-0000-0000-0000-0000000000a0';
begin
  perform test.mk_user(v_admin, 'admin@rawaa.test', '+966500000001');
  insert into public.admin_profiles(user_id, role, status, permissions, login_mode) values (v_admin, 'super_admin', 'active', '{}', 'password');
  insert into private.platform_operators(user_id) values (v_admin);
  perform test.mk_user('00000000-0000-0000-0000-0000000000b1', 's1@rawaa.test', '+966500000011');
  perform test.mk_user('00000000-0000-0000-0000-0000000000b2', 's2@rawaa.test', '+966500000012');
  perform test.mk_user('00000000-0000-0000-0000-0000000000b3', 's3@rawaa.test', '+966500000013');
  perform test.mk_user('00000000-0000-0000-0000-0000000000c1', 'c1@rawaa.test', '+966500000021');
  perform test.mk_user('00000000-0000-0000-0000-0000000000c2', 'c2@rawaa.test', '+966500000022');
  perform test.mk_user('00000000-0000-0000-0000-0000000000d1', 'courier@rawaa.test', '+966500000031');
  -- the platform's own bank account and direct payments switched on (dev environment)
  update private.finance_settings set direct_payments_enabled = true, platform_bank_name = 'مصرف الراجحي',
    platform_iban = 'SA0380000000608010167519', platform_account_holder = 'رِواء الحرمين', platform_address = 'مكة المكرمة';
end $$;

-- helper: register + approve a supplier through the real flow; returns supplier id in ctx
create function test.onboard(p_key text, p_owner uuid, p_name text, p_cr text, p_iban text, p_tax text) returns uuid language plpgsql as $$
declare c record; v_app uuid; v_sup uuid; begin
  select version_id, body_sha256 into c from public.supplier_contract_versions where is_current;
  perform test.as_user(p_owner);
  v_app := public.submit_seller_application(jsonb_build_object('business_name', p_name, 'commercial_registration', p_cr, 'entity_type', 'distributor',
    'iban', p_iban, 'tax_number', p_tax, 'phone', '0500000000', 'email', p_key||'@x.test', 'national_address', 'مكة - العزيزية',
    'document_path', p_owner::text||'/cr-1.pdf', 'account_holder_name', p_name, 'bank_name', 'مصرف الراجحي'),
    c.version_id, c.body_sha256, 'ممثل '||p_name, true, gen_random_uuid());
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  perform public.admin_decide_application(v_app, true);
  perform test.reset();
  select id into v_sup from public.suppliers where owner_id = p_owner;
  perform test.set(p_key, v_sup::text);
  return v_sup;
end $$;
grant execute on function test.onboard(text,uuid,text,text,text,text) to public;

-- helper: complete payment settings + connect a (test) gateway + admin approval
create function test.activate_payments(p_sup uuid, p_owner uuid, p_vat boolean) returns void language plpgsql as $$ begin
  perform test.as_user(p_owner);
  perform public.supplier_save_payment_profile(p_sup, jsonb_build_object('entity_type','distributor','legal_name','منشأة '||left(p_sup::text,4),
    'cr_number','1010123456','account_holder_name','منشأة اختبار','bank_name','مصرف الراجحي','iban','SA0380000000608010167519',
    'vat_registered', p_vat, 'tax_number', case when p_vat then '300000000000003' end,
    'vat_certificate_path', case when p_vat then p_owner::text||'/vat.pdf' end));
  perform public.supplier_set_payment_methods(p_sup, 'https://pay.example.sa/'||left(p_sup::text,8), true, null);
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  perform public.admin_review_payment_profile(p_sup, 'approve', null);
  perform test.reset();
end $$;
grant execute on function test.activate_payments(uuid,uuid,boolean) to public;

-- helper: place a paid order (quote -> order -> verified capture)
create function test.paid_order(p_customer uuid, p_items jsonb, p_charge text) returns uuid language plpgsql as $$
declare v_order uuid; v_total bigint; begin
  perform test.as_user(p_customer);
  v_order := public.place_order(p_items, 'makkah', 'حي العزيزية، شارع 1، مبنى 2', 'عميل اختبار', '0500000000', gen_random_uuid(), '{}'::jsonb, 0);
  perform public.set_order_delivery(v_order, 'oto');
  perform public.choose_order_payment_method(v_order, 'supplier_link');
  perform test.reset();
  perform test.as_user((select s.owner_id from public.suppliers s join public.orders o on o.supplier_id=s.id where o.id=v_order));
  perform public.supplier_confirm_order_payment(v_order, p_charge);
  perform test.reset();
  return v_order;
end $$;
grant execute on function test.paid_order(uuid,jsonb,text) to public;


-- helper: complete an order the way production requires (documented receipt with video evidence)
create function test.complete_order(p_order uuid, p_at timestamptz) returns void language plpgsql as $$
declare v_d uuid := gen_random_uuid(); v_courier uuid := '00000000-0000-0000-0000-0000000000d1'; v_path text := p_order::text||'/receipt.mp4'; begin
  insert into public.deliveries(id, order_id, courier_id, reviewer_id, status, recipient_confirmed_at, reviewed_at)
  values (v_d, p_order, v_courier, '00000000-0000-0000-0000-0000000000a0', 'approved', now(), now());
  insert into storage.objects(bucket_id, name, owner_id) values ('delivery-evidence', v_path, v_courier::text);
  insert into public.delivery_evidence(id, delivery_id, uploaded_by, object_path) values (gen_random_uuid(), v_d, v_courier, v_path);
  update public.orders set delivered_at = p_at, status = 'delivered' where id = p_order;
end $$;
grant execute on function test.complete_order(uuid,timestamptz) to public;

-- ================================================================ 1. supplier without a payment method
do $$
declare s1 uuid; v_prod public.products; v_blk text[]; v_seen int;
begin
  s1 := test.onboard('s1', '00000000-0000-0000-0000-0000000000b1', 'مؤسسة المياه الأولى', '1010000001', 'SA0380000000608010167519', '300000000000003');
  select selling_blockers into v_blk from public.suppliers where id=s1;
  perform test.ok('01 no payment method', 'approved supplier is not selling without payment setup',
    not (select selling_enabled from public.suppliers where id=s1) and 'payment_profile_incomplete' = any(v_blk), array_to_string(v_blk, ','));
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  v_prod := private.supplier_save_product(null, s1, jsonb_build_object('name','مياه 330 مل','description','كرتون 40','unit','كرتون','category','water',
    'price_halalas',10000,'stock',100,'cities',jsonb_build_array('makkah'),'active',true), null);
  perform test.reset();
  perform test.set('p1', v_prod.id::text);
  perform test.as_anon();
  select count(*) into v_seen from public.products where id=v_prod.id;
  perform test.reset();
  perform test.ok('01 no payment method', 'products hidden from shoppers while supplier cannot sell', v_seen = 0, v_seen::text);
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000c1');
    perform public.place_order(jsonb_build_array(jsonb_build_object('product_id',v_prod.id,'quantity',1)), 'makkah', 'حي العزيزية، شارع 1، مبنى 2', 'عميل', '0500000000', gen_random_uuid(), '{}'::jsonb, 0);
    perform test.ok('01 no payment method', 'paid order rejected for supplier without active payment method', false, 'order was created');
  exception when others then perform test.ok('01 no payment method', 'paid order rejected for supplier without active payment method', sqlerrm ilike '%supplier unavailable%', sqlerrm); end;
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000b1');
    perform public.supplier_save_payment_profile(s1, jsonb_build_object('iban','SA0380000000608010167518'));
    perform test.ok('01 no payment method', 'invalid IBAN checksum rejected', false);
  exception when others then perform test.ok('01 no payment method', 'invalid IBAN checksum rejected', sqlerrm ilike '%IBAN%', sqlerrm); end;
end $$;

-- ================================================================ 2. supplier sets its own payment link / cash on delivery
do $$
declare s1 uuid := test.get('s1')::uuid; r jsonb; v_status text; v_sec int;
begin
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  r := public.supplier_save_payment_profile(s1, jsonb_build_object('entity_type','distributor','legal_name','مؤسسة المياه الأولى','cr_number','1010000001',
    'account_holder_name','مؤسسة المياه الأولى','bank_name','مصرف الراجحي','iban','SA03 8000 0000 6080 1016 7519','vat_registered',true,
    'tax_number','300000000000003','vat_certificate_path','00000000-0000-0000-0000-0000000000b1/vat.pdf'));
  perform test.reset();
  perform test.ok('02 payment method', 'complete bank data without a payment method stays incomplete', r->>'status' = 'incomplete' and (r->'missing') ? 'payment_method', r::text);
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000b1');
    perform public.supplier_set_payment_methods(s1, 'http://insecure.example/pay', false, null);
    perform test.ok('02 payment method', 'non-https payment link rejected', false);
  exception when others then perform test.ok('02 payment method', 'non-https payment link rejected', sqlerrm ilike '%https%', sqlerrm); end;
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  r := public.supplier_set_payment_methods(s1, 'https://pay.example.sa/water1', true, 'ادفع عبر الرابط أو نقداً عند الاستلام');
  perform test.reset();
  perform test.ok('02 payment method', 'payment link + COD moves profile to pending review (قيد التحقق)', r->>'status' = 'pending', r::text);
  perform test.ok('02 payment method', 'no Tap key is required or stored', not exists(select 1 from private.supplier_gateway_secrets where supplier_id=s1));
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  perform public.admin_review_payment_profile(s1, 'approve', 'تم التحقق');
  perform test.reset();
  select status into v_status from public.supplier_payment_profiles where supplier_id=s1;
  perform test.ok('02 payment method', 'admin approval activates payment method (مفعل)', v_status = 'active', v_status);
  perform test.ok('02 payment method', 'supplier can sell after payment + contract + approval', (select selling_enabled from public.suppliers where id=s1),
    (select array_to_string(selling_blockers,',') from public.suppliers where id=s1));
  -- sensitive change on an active profile is queued for re-verification, selling continues
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  r := public.supplier_save_payment_profile(s1, jsonb_build_object('entity_type','distributor','legal_name','مؤسسة المياه الأولى','cr_number','1010000001',
    'account_holder_name','مؤسسة المياه الأولى','bank_name','البنك الأهلي السعودي','iban','SA1810000001234567891234','vat_registered',true,
    'tax_number','300000000000003','vat_certificate_path','00000000-0000-0000-0000-0000000000b1/vat.pdf'));
  perform test.reset();
  perform test.ok('02 payment method', 'IBAN change on active account needs admin approval', r ? 'change_request'
    and (select iban from public.supplier_payment_profiles where supplier_id=s1) = 'SA0380000000608010167519'
    and (select selling_enabled from public.suppliers where id=s1), r::text);
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  perform public.admin_decide_payment_change((r->>'change_request')::uuid, false, 'لم يُرفق خطاب البنك');
  perform test.reset();
  perform test.ok('02 payment method', 'rejected change leaves verified details untouched',
    (select iban from public.supplier_payment_profiles where supplier_id=s1) = 'SA0380000000608010167519');
end $$;

-- ================================================================ 3. contract consent
do $$
declare c record; v_cnt int; v_acc record; s1 uuid := test.get('s1')::uuid; v_blk text[];
begin
  select version_id, body_sha256 into c from public.supplier_contract_versions where is_current;
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000b2');
    perform public.submit_seller_application(jsonb_build_object('business_name','x'), c.version_id, c.body_sha256, 'ممثل', false, gen_random_uuid());
    perform test.ok('03 contract', 'registration impossible without explicit consent', false);
  exception when others then perform test.ok('03 contract', 'registration impossible without explicit consent', sqlerrm ilike '%consent%', sqlerrm); end;
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000b2');
    perform public.submit_seller_application(jsonb_build_object('business_name','x'), c.version_id, repeat('0',64), 'ممثل المنشأة', true, gen_random_uuid());
    perform test.ok('03 contract', 'consent bound to the exact contract text hash', false);
  exception when others then perform test.ok('03 contract', 'consent bound to the exact contract text hash', sqlerrm ilike '%contract version changed%', sqlerrm); end;
  select a.* into v_acc from private.supplier_contract_acceptances a where a.supplier_id=s1;
  perform test.ok('03 contract', 'acceptance stores version, hash, signer, session and time',
    v_acc.version_id = c.version_id and v_acc.body_sha256 = c.body_sha256 and v_acc.signer_id = '00000000-0000-0000-0000-0000000000b1'
    and v_acc.session_id is not null and v_acc.accepted_at is not null);
  -- legacy-style application without consent cannot be approved
  insert into public.seller_applications(owner_id, business_name, commercial_registration, phone, city, category, document_path, iban)
  values ('00000000-0000-0000-0000-0000000000c2', 'بدون عقد', '1010000099', '0500000000', 'makkah', 'water', '00000000-0000-0000-0000-0000000000c2/cr.pdf', 'SA0380000000608010167519');
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000a0');
    perform public.admin_decide_application((select id from public.seller_applications where business_name='بدون عقد'), true);
    perform test.ok('03 contract', 'approval blocked without recorded consent', false);
  exception when others then perform test.ok('03 contract', 'approval blocked without recorded consent', sqlerrm ilike '%not explicitly accepted%', sqlerrm); end;
  -- v3 needs legal review before publication
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000a0');
    perform public.admin_publish_contract('rw-v3-2026-11-direct-pay');
    perform test.ok('03 contract', 'v3 cannot be published before legal review', false);
  exception when others then perform test.ok('03 contract', 'v3 cannot be published before legal review', sqlerrm ilike '%legal review%', sqlerrm); end;
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  perform public.admin_record_contract_legal_review('rw-v3-2026-11-direct-pay', 'المستشار القانوني', 'تمت المراجعة');
  perform public.admin_publish_contract('rw-v3-2026-11-direct-pay');
  perform test.reset();
  perform test.ok('03 contract', 'after publishing v3, previous acceptance stays valid during grace', (select selling_enabled from public.suppliers where id=s1));
  update private.finance_settings set contract_reaccept_grace_days = 0;
  perform private.refresh_supplier_selling(s1);
  select selling_blockers into v_blk from public.suppliers where id=s1;
  perform test.ok('03 contract', 'after grace, supplier must accept the new version', 'contract_not_accepted' = any(v_blk), array_to_string(v_blk,','));
  select count(*) into v_cnt from public.supplier_notifications where supplier_id=s1 and kind='contract_update';
  perform test.ok('03 contract', 'supplier notified of the new contract version', v_cnt = 1);
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  perform private.accept_supplier_contract(s1, 'rw-v3-2026-11-direct-pay',
    (select body_sha256 from public.supplier_contract_versions where version_id='rw-v3-2026-11-direct-pay'), 'ممثل مؤسسة المياه الأولى', gen_random_uuid(), true);
  perform test.reset();
  perform test.ok('03 contract', 'accepting v3 restores selling', (select selling_enabled from public.suppliers where id=s1));
  begin
    update private.supplier_contract_acceptances set signer_full_name='x' where supplier_id=s1;
    perform test.ok('03 contract', 'acceptance records are append-only', false);
  exception when others then perform test.ok('03 contract', 'acceptance records are append-only', sqlerrm ilike '%append only%', sqlerrm); end;
end $$;

-- ================================================================ 4. 5% base commission + markup (spec example)
do $$
declare s1 uuid := test.get('s1')::uuid; p uuid := test.get('p1')::uuid; v_order uuid; i public.order_items; pr public.products; prev_rule uuid;
begin
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  -- preview first: nothing changes until saved
  perform count(*) from public.admin_preview_pricing_rule(null, 'all', null, null, null, 'fixed', 1000);
  perform test.reset();
  perform test.ok('04 commission', 'preview does not change prices', (select price_halalas from public.products where id=p) = 10000);
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  prev_rule := (public.admin_save_pricing_rule(null, 'all', null, null, null, 'fixed', 1000, 'زيادة 10 ريال')).id;
  perform test.reset();
  select * into pr from public.products where id=p;
  perform test.ok('04 commission', 'sale price = original 100 + markup 10 = 110, original untouched',
    pr.supplier_price_halalas = 10000 and pr.markup_halalas = 1000 and pr.price_halalas = 11000, format('%s/%s/%s', pr.supplier_price_halalas, pr.markup_halalas, pr.price_halalas));
  perform test.ok('04 commission', 'VAT-inclusive display price for VAT-registered supplier = 126.50', pr.display_price_halalas = 12650, pr.display_price_halalas::text);
  v_order := test.paid_order('00000000-0000-0000-0000-0000000000c1', jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1)), 'chg_TEST000001');
  perform test.set('o1', v_order::text);
  select * into i from public.order_items where order_id=v_order;
  perform test.ok('04 commission', 'base 5% = 5 SAR on original price only', i.base_commission_halalas = 500, i.base_commission_halalas::text);
  perform test.ok('04 commission', 'markup commission = 10 SAR', i.markup_commission_halalas = 1000);
  perform test.ok('04 commission', 'total Rawaa commission = 15 SAR', i.base_commission_halalas + i.markup_commission_halalas = 1500);
  perform test.ok('04 commission', 'order paid only after verified capture', (select payment_status from public.orders where id=v_order) = 'paid');
  -- rule priority: product rule overrides global, one rule per target
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  perform public.admin_save_pricing_rule(null, 'product', null, null, p, 'percent', 2000, '20%');
  perform test.reset();
  perform test.ok('04 commission', 'product-level rule takes priority over global rule', (select markup_halalas from public.products where id=p) = 2000);
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000a0');
    perform public.admin_save_pricing_rule(null, 'product', null, null, p, 'fixed', 500, 'duplicate');
    perform test.ok('04 commission', 'second active rule for the same target rejected', false);
  exception when others then perform test.ok('04 commission', 'second active rule for the same target rejected', sqlerrm ilike '%already exists%', sqlerrm); end;
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000a0');
    perform public.admin_set_pricing_rule_active((select id from public.pricing_rules where product_id=p and active), false);
    perform public.admin_save_pricing_rule(null, 'product', null, null, p, 'final_price', 9000, 'below');
    perform test.ok('04 commission', 'final price below supplier price rejected', false);
  exception when others then perform test.ok('04 commission', 'final price below supplier price rejected', sqlerrm ilike '%cannot be below%', sqlerrm); end;
  perform test.ok('04 commission', 'price changes are audit-logged with old and new values',
    exists(select 1 from public.pricing_audit_log where entity_type='product_price' and entity_id=p::text and old_value ? 'price_halalas' and new_value ? 'price_halalas'));
  perform test.reset();
end $$;

-- ================================================================ 5. admin changes the commission rate
do $$
declare p uuid := test.get('p1')::uuid; v_order uuid; i public.order_items; old_i public.order_items;
begin
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000b1');
    perform public.admin_update_finance_settings('{"commission_rate_bp":0}');
    perform test.ok('05 rate change', 'suppliers cannot change the commission rate', false);
  exception when others then perform test.ok('05 rate change', 'suppliers cannot change the commission rate', sqlerrm ilike '%forbidden%', sqlerrm); end;
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  perform public.admin_update_finance_settings('{"commission_rate_bp":700}');
  perform test.reset();
  v_order := test.paid_order('00000000-0000-0000-0000-0000000000c1', jsonb_build_array(jsonb_build_object('product_id',p,'quantity',2)), 'chg_TEST000002');
  perform test.set('o2', v_order::text);
  select * into i from public.order_items where order_id=v_order;
  select * into old_i from public.order_items where order_id=test.get('o1')::uuid;
  perform test.ok('05 rate change', 'new orders use 7%: 7% x 200 = 14 SAR', i.commission_rate_bp = 700 and i.base_commission_halalas = 1400, i.base_commission_halalas::text);
  perform test.ok('05 rate change', 'earlier order keeps its 5% snapshot', old_i.commission_rate_bp = 500 and old_i.base_commission_halalas = 500);
  perform test.ok('05 rate change', 'setting change audit-logged', exists(select 1 from public.pricing_audit_log where entity_type='finance_setting'
    and (old_value->>'commission_rate_bp')::int = 500 and (new_value->>'commission_rate_bp')::int = 700));
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  perform public.admin_update_finance_settings('{"commission_rate_bp":500}');
  perform test.reset();
end $$;

-- ================================================================ 6. VAT computed separately and correctly
do $$
declare s2 uuid; p2 uuid; o public.orders; q jsonb; v_order uuid; p1 uuid := test.get('p1')::uuid;
begin
  s2 := test.onboard('s2', '00000000-0000-0000-0000-0000000000b2', 'تاجر غير مسجل بالضريبة', '1010000002', 'SA0380000000608010167519', null);
  perform test.activate_payments(s2, '00000000-0000-0000-0000-0000000000b2', false);
  perform test.as_user('00000000-0000-0000-0000-0000000000b2');
  p2 := (private.supplier_save_product(null, s2, jsonb_build_object('name','مصحف','description','مصحف المدينة','unit','حبة','category','quran',
    'price_halalas',5000,'stock',50,'cities',jsonb_build_array('makkah'),'active',true), null)).id;
  perform test.reset();
  perform test.set('p2', p2::text);
  perform test.ok('06 VAT', 'no VAT on a supplier that is not VAT registered', (select vat_rate_bp from public.products where id=p2) = 0
    and (select display_price_halalas from public.products where id=p2) = (select price_halalas from public.products where id=p2));
  -- VAT-registered supplier: 15% on the full sale price (original + markup), never assumed exempt
  q := public.checkout_quote(jsonb_build_array(jsonb_build_object('product_id',p1,'quantity',1)), 'makkah', 'oto');
  perform test.ok('06 VAT', 'quote: VAT 15% of 120 SAR sale price = 18 SAR', (q->'groups'->0->>'vat_halalas')::bigint = 1800, q->'groups'->0->>'vat_halalas');
  v_order := test.paid_order('00000000-0000-0000-0000-0000000000c2', jsonb_build_array(jsonb_build_object('product_id',p2,'quantity',2)), 'chg_TEST000003');
  select * into o from public.orders where id=v_order;
  perform test.ok('06 VAT', 'order total for non-VAT supplier = sale price only (no automatic 15%)', o.vat_halalas = 0 and o.payable_halalas = o.subtotal_halalas,
    format('sub=%s vat=%s payable=%s', o.subtotal_halalas, o.vat_halalas, o.payable_halalas));
  perform test.ok('06 VAT', 'commission math independent of VAT: 5% of 100 SAR original = 5 SAR',
    (select base_commission_halalas from public.order_items where order_id=v_order) = 500);
  -- supplier delivery fee VAT follows the supplier's VAT status
  update public.suppliers set accepts_delivery = true where id = test.get('s1')::uuid;
  q := public.checkout_quote(jsonb_build_array(jsonb_build_object('product_id',p1,'quantity',1)), 'makkah', 'supplier');
  perform test.ok('06 VAT', 'supplier delivery fee carries VAT for a VAT-registered supplier',
    (q->'groups'->0->>'delivery_halalas')::int = 25 and (q->'groups'->0->>'vat_halalas')::bigint = 1800 + 4, q::text);
  perform test.set('o3', v_order::text);
end $$;

-- ================================================================ 7. completed order accrues commission (once)
do $$
declare v_order uuid := test.get('o1')::uuid; n int; r text;
begin
  select count(*) into n from public.commission_entries where order_id=v_order;
  perform test.ok('07 accrual', 'no commission before the order is completed', n = 0);
  begin
    update public.orders set status = 'delivered' where id = v_order;
    perform test.ok('07 accrual', 'completion requires documented receipt', false);
  exception when others then perform test.ok('07 accrual', 'completion requires documented receipt', sqlerrm ilike '%documented receipt%', sqlerrm); end;
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  r := public.supplier_confirm_order_payment(v_order, 'chg_TEST000001')->>'status';
  perform test.reset();
  perform test.ok('07 accrual', 'repeated payment confirmation is ignored', r = 'already_paid', r);
  perform test.complete_order(v_order, '2026-10-15 10:00+03');
  perform test.complete_order(test.get('o2')::uuid, '2026-10-20 10:00+03');
  perform test.complete_order(test.get('o3')::uuid, '2026-10-21 10:00+03');
  select count(*) into n from public.commission_entries where order_id=v_order and kind='accrual';
  perform test.ok('07 accrual', 'delivered + paid order accrues commission in its completion month',
    n = 1 and (select period_month from public.commission_entries where order_id=v_order) = '2026-10-01', n::text);
  update public.orders set status = 'delivered' where id = v_order;  -- no-op transition
  perform private.try_accrue_order(v_order);
  select count(*) into n from public.commission_entries where order_id=v_order;
  perform test.ok('07 accrual', 'accrual is idempotent', n = 1, n::text);
end $$;

-- ================================================================ 8a. cancellation + duplicate/mismatch payments
do $$
declare p uuid := test.get('p1')::uuid; v_order uuid; v_stock int; v_after int; r text;
begin
  select stock into v_stock from public.products where id=p;
  perform test.as_user('00000000-0000-0000-0000-0000000000c1');
  v_order := public.place_order(jsonb_build_array(jsonb_build_object('product_id',p,'quantity',3)), 'makkah', 'حي العزيزية، شارع 1، مبنى 2', 'عميل', '0500000000', gen_random_uuid(), '{}'::jsonb, 0);
  perform public.cancel_my_order(v_order);
  perform test.reset();
  select stock into v_after from public.products where id=p;
  perform test.ok('08 cancel/refund', 'cancelling an unpaid order restores stock', v_after = v_stock, format('%s -> %s', v_stock, v_after));
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000b1');
    perform public.supplier_confirm_order_payment(v_order, 'TRX-LATE');
    perform test.ok('08 cancel/refund', 'supplier cannot confirm payment on a cancelled order', false);
  exception when others then perform test.ok('08 cancel/refund', 'supplier cannot confirm payment on a cancelled order', sqlerrm ilike '%cancelled%', sqlerrm); end;
  perform test.reset();
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  r := public.supplier_confirm_order_payment(test.get('o1')::uuid, 'TRX-DUP')->>'status';
  perform test.reset();
  perform test.ok('08 cancel/refund', 'confirming an already-paid order is a no-op (no double payment)',
    r = 'already_paid' and (select count(*) from private.order_payments where order_id=test.get('o1')::uuid) = 1, r);
  perform test.as_user('00000000-0000-0000-0000-0000000000c1');
  v_order := public.place_order(jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1)), 'makkah', 'حي العزيزية، شارع 1، مبنى 2', 'عميل', '0500000000', gen_random_uuid(), '{}'::jsonb, 0);
  perform test.reset();
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000b1');
    perform public.supplier_confirm_order_payment(v_order, 'TRX-EARLY');
    perform test.ok('08 cancel/refund', 'payment cannot be confirmed before the customer chooses a method', false);
  exception when others then perform test.ok('08 cancel/refund', 'payment cannot be confirmed before the customer chooses a method', sqlerrm ilike '%payment method%', sqlerrm); end;
  perform test.reset();
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000c2');
    perform public.supplier_confirm_order_payment(v_order, 'TRX-FAKE');
    perform test.ok('08 cancel/refund', 'a customer cannot mark an order paid', false);
  exception when others then perform test.ok('08 cancel/refund', 'a customer cannot mark an order paid', sqlerrm ilike '%forbidden%', sqlerrm); end;
  perform test.reset();
end $$;

-- ================================================================ 9. month-end invoice
do $$
declare s1 uuid := test.get('s1')::uuid; s2 uuid := test.get('s2')::uuid; r jsonb; inv public.commission_invoices; n int;
begin
  update private.finance_settings set platform_iban = null;
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  r := public.admin_close_period('2026-10-01', true);
  perform test.reset();
  perform test.ok('09 invoice', 'issuing refused until the platform bank account is configured',
    (r->>'issued')::int = 0 and jsonb_array_length(r->'errors') >= 1, r::text);
  update private.finance_settings set platform_iban = 'SA0380000000608010167519';
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  r := public.admin_close_period('2026-10-01', true);
  perform test.reset();
  select * into inv from public.commission_invoices where supplier_id=s1 and period_month='2026-10-01';
  perform test.set('inv1', inv.id::text);
  perform test.ok('09 invoice', 'one invoice per supplier for the closed month', (select count(*) from public.commission_invoices where period_month='2026-10-01') = 2);
  perform test.ok('09 invoice', 'invoice totals: orders, original sales, base, markup',
    inv.order_count = 2 and inv.gross_original_halalas = 30000 and inv.base_commission_halalas = 500 + 1400 and inv.markup_commission_halalas = 1000 + 2*2000,
    format('orders=%s gross=%s base=%s markup=%s', inv.order_count, inv.gross_original_halalas, inv.base_commission_halalas, inv.markup_commission_halalas));
  perform test.ok('09 invoice', 'no platform VAT when the platform is not VAT registered', inv.vat_halalas = 0 and inv.total_halalas = 6900, inv.total_halalas::text);
  perform test.ok('09 invoice', 'unique invoice number, issue date, due date = 5 Nov',
    inv.invoice_no ~ '^RWA-INV-202610-[0-9]{6}$' and inv.due_date = '2026-11-05' and inv.status <> 'draft', inv.invoice_no||' '||inv.due_date);
  perform test.ok('09 invoice', 'invoice snapshots supplier and platform legal/bank details',
    inv.platform_snapshot->>'iban' = 'SA0380000000608010167519' and inv.supplier_snapshot ? 'cr_number' and inv.snapshot_sha256 ~ '^[0-9a-f]{64}$');
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  r := public.admin_close_period('2026-10-01', true);
  perform test.reset();
  select count(*) into n from public.commission_invoices where period_month='2026-10-01';
  perform test.ok('09 invoice', 're-running the close never duplicates invoices', n = 2 and (r->>'created')::int = 0, r::text);
  perform test.ok('09 invoice', 'supplier notified when the invoice is issued',
    exists(select 1 from public.supplier_notifications where supplier_id=s1 and kind='invoice_issued'));
  begin
    update public.commission_invoices set total_halalas = 1 where id = inv.id;
    perform test.ok('09 invoice', 'issued invoice amounts are immutable', false);
  exception when others then perform test.ok('09 invoice', 'issued invoice amounts are immutable', sqlerrm ilike '%immutable%', sqlerrm); end;
  begin
    perform private.close_billing_period(private.ksa_month(now()), true);
    perform test.ok('09 invoice', 'the running month cannot be closed early', false);
  exception when others then perform test.ok('09 invoice', 'the running month cannot be closed early', sqlerrm ilike '%completed months%', sqlerrm); end;
end $$;

-- ================================================================ 10. partial and full payment
do $$
declare inv uuid := test.get('inv1')::uuid; pay uuid; st text; v_paid bigint;
begin
  perform test.set('today', '2026-11-03');
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  pay := public.supplier_submit_invoice_payment(inv, 3000, 'TRX-1001', '2026-11-02', null);
  perform test.reset();
  perform test.ok('10 payments', 'submitted transfer does not count until verified', (select paid_halalas from public.commission_invoices where id=inv) = 0);
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000b1');
    perform public.admin_review_invoice_payment(pay, true, null);
    perform test.ok('10 payments', 'supplier cannot verify its own transfer', false);
  exception when others then perform test.ok('10 payments', 'supplier cannot verify its own transfer', sqlerrm ilike '%forbidden%', sqlerrm); end;
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  st := public.admin_review_invoice_payment(pay, true, null);
  perform test.reset();
  perform test.ok('10 payments', 'verified partial payment -> partially paid', st = 'partially_paid', st);
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  pay := public.supplier_submit_invoice_payment(inv, 3900, 'TRX-1002', '2026-11-04', null);
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  st := public.admin_review_invoice_payment(pay, true, null);
  perform test.reset();
  select paid_halalas into v_paid from public.commission_invoices where id=inv;
  perform test.ok('10 payments', 'full payment -> paid', st = 'paid' and v_paid = 6900, st||' '||v_paid);
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000a0');
    perform public.admin_review_invoice_payment(pay, false, null);
    perform test.ok('10 payments', 'a verified payment cannot be reviewed again', false);
  exception when others then perform test.ok('10 payments', 'a verified payment cannot be reviewed again', sqlerrm ilike '%not awaiting review%', sqlerrm); end;
  perform test.reset();
end $$;

-- ================================================================ 11. late payment, warning, suspension
do $$
declare s2 uuid := test.get('s2')::uuid; inv2 uuid; r jsonb; v_order uuid; p2 uuid := test.get('p2')::uuid; o3 uuid := test.get('o3')::uuid;
begin
  select id into inv2 from public.commission_invoices where supplier_id=s2 and period_month='2026-10-01';
  perform test.set('today', '2026-11-08');
  r := private.run_billing_jobs();
  perform test.ok('11 overdue', 'unpaid invoice past day 5 becomes overdue', (select status from public.commission_invoices where id=inv2) = 'overdue', r::text);
  perform test.ok('11 overdue', 'overdue warning sent to supplier and admin alerted',
    exists(select 1 from public.supplier_notifications where dedupe_key='overdue:'||inv2) and exists(select 1 from private.finance_alerts where dedupe_key='overdue:'||inv2));
  perform private.run_billing_jobs();
  perform test.ok('11 overdue', 'warnings are not duplicated by repeated runs', (select count(*) from public.supplier_notifications where dedupe_key='overdue:'||inv2) = 1);
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000a0');
    perform public.admin_set_orders_suspended(s2, true, 'تأخر سداد', false);
    perform test.ok('11 overdue', 'suspension not allowed before the contractual warning period', false);
  exception when others then perform test.ok('11 overdue', 'suspension not allowed before the contractual warning period', sqlerrm ilike '%warning period%', sqlerrm); end;
  perform test.set('today', '2026-11-13');
  perform test.as_user('00000000-0000-0000-0000-0000000000a0');
  perform public.admin_set_orders_suspended(s2, true, 'تأخر سداد فاتورة أكتوبر', false);
  perform test.reset();
  perform test.ok('11 overdue', 'suspended supplier no longer sells', not (select selling_enabled from public.suppliers where id=s2));
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000c2');
    perform public.place_order(jsonb_build_array(jsonb_build_object('product_id',p2,'quantity',1)), 'makkah', 'حي العزيزية، شارع 1، مبنى 2', 'عميل', '0500000000', gen_random_uuid(), '{}'::jsonb, 0);
    perform test.ok('11 overdue', 'new orders blocked for the suspended supplier', false);
  exception when others then perform test.ok('11 overdue', 'new orders blocked for the suspended supplier', sqlerrm ilike '%supplier unavailable%', sqlerrm); end;
  perform test.as_user('00000000-0000-0000-0000-0000000000b2');
  perform test.ok('11 overdue', 'suspended supplier still sees its invoices and history', (select count(*) from public.supplier_invoices(s2)) = 1);
  perform test.reset();
  update public.orders set status='confirmed' where id = o3 and false;  -- existing orders untouched
  perform test.ok('11 overdue', 'existing orders of the suspended supplier remain intact', (select status from public.orders where id=o3) = 'delivered');
end $$;

-- ================================================================ 8b. refunds before and after month close
do $$
declare o1 uuid := test.get('o1')::uuid; o2 uuid := test.get('o2')::uuid; inv1 uuid := test.get('inv1')::uuid; r jsonb; v_cn public.commission_credit_notes;
  v_inv public.commission_invoices; p uuid := test.get('p1')::uuid; o_new uuid; n bigint;
begin
  -- refund after the month was invoiced -> credit note, original invoice untouched
  perform test.as_service();
  r := public.svc_record_refund(o1, 'ref_TEST0001', 'chg_TEST000001', (select payable_halalas from public.orders where id=o1), 'succeeded', 'إرجاع المنتج', null);
  perform test.reset();
  select * into v_cn from public.commission_credit_notes where refund_id = (r->>'id')::uuid;
  select * into v_inv from public.commission_invoices where id=inv1;
  perform test.ok('08 cancel/refund', 'refund after month close issues a credit note (15 SAR) against the original invoice',
    v_cn.id is not null and v_cn.amount_halalas = 1500 and v_cn.invoice_id = inv1 and v_cn.credit_note_no ~ '^RWA-CN-', coalesce(v_cn.amount_halalas::text,'none'));
  perform test.ok('08 cancel/refund', 'original invoice amounts unchanged; credit recorded separately',
    v_inv.total_halalas = 6900 and v_inv.credited_halalas = 1500, format('total=%s credited=%s', v_inv.total_halalas, v_inv.credited_halalas));
  perform test.ok('08 cancel/refund', 'overpayment from the credit becomes supplier credit',
    private.supplier_available_credit(test.get('s1')::uuid, null) = 1500);
  -- refund on an order accrued in the open month -> reversal netted in the next invoice
  o_new := test.paid_order('00000000-0000-0000-0000-0000000000c1', jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1)), 'chg_TEST000009');
  perform test.complete_order(o_new, now());
  perform test.as_service();
  perform public.svc_record_refund(o_new, 'ref_TEST0002', 'chg_TEST000009', (select payable_halalas from public.orders where id=o_new) / 2, 'succeeded', 'إرجاع جزئي', null);
  perform test.reset();
  select coalesce(sum(total_commission_halalas),0) into n from public.commission_entries where order_id=o_new;
  perform test.ok('08 cancel/refund', 'partial refund reverses commission proportionally in the open period', n = 1250, n::text);
  perform test.ok('08 cancel/refund', 'order shows partial refund', (select refund_status from public.orders where id=o_new) = 'partial');
  begin
    perform test.as_service();
    perform public.svc_record_refund(o_new, 'ref_TEST0003', 'chg_TEST000009', (select payable_halalas from public.orders where id=o_new), 'succeeded', 'زيادة', null);
    perform test.ok('08 cancel/refund', 'refund cannot exceed the refundable amount', false);
  exception when others then perform test.ok('08 cancel/refund', 'refund cannot exceed the refundable amount', sqlerrm ilike '%exceeds%', sqlerrm); end;
  perform test.reset();
  perform test.as_service();
  perform public.svc_record_refund(o_new, 'ref_TEST0002', 'chg_TEST000009', 1, 'succeeded', 'إعادة إرسال', null);
  perform test.reset();
  select coalesce(sum(total_commission_halalas),0) into n from public.commission_entries where order_id=o_new;
  perform test.ok('08 cancel/refund', 'replayed refund notification does not reverse twice', n = 1250, n::text);
end $$;

-- ================================================================ 12. price change after the order
do $$
declare o1 uuid := test.get('o1')::uuid; p uuid := test.get('p1')::uuid; before_i public.order_items; after_i public.order_items;
begin
  select * into before_i from public.order_items where order_id=o1;
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  perform private.supplier_save_product(p, test.get('s1')::uuid, jsonb_build_object('name','مياه 330 مل','description','كرتون 40','unit','كرتون','category','water',
    'price_halalas',15000,'stock',100,'cities',jsonb_build_array('makkah'),'active',true), (select inventory_version from public.products where id=p));
  perform test.reset();
  select * into after_i from public.order_items where order_id=o1;
  perform test.ok('12 price change', 'completed order keeps purchase-time prices and commission', before_i = after_i);
  perform test.ok('12 price change', 'new supplier price flows into the shelf price (product rule 20%: 150 -> 180)',
    (select supplier_price_halalas from public.products where id=p) = 15000 and (select price_halalas from public.products where id=p) = 18000,
    (select price_halalas::text from public.products where id=p));
  begin
    update public.order_items set unit_price_halalas = 1 where order_id = o1;
    perform test.ok('12 price change', 'order line snapshot cannot be edited', false);
  exception when others then perform test.ok('12 price change', 'order line snapshot cannot be edited', sqlerrm ilike '%immutable%', sqlerrm); end;
  begin
    update public.orders set delivery_halalas = 999 where id = o1;
    perform test.ok('12 price change', 'paid order totals are frozen', false);
  exception when others then perform test.ok('12 price change', 'paid order totals are frozen', sqlerrm ilike '%immutable%', sqlerrm); end;
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000a0');
    perform public.admin_update_product(p, 1, null, null, null);
    perform test.ok('12 price change', 'admin cannot overwrite prices directly (rules only)', false);
  exception when others then perform test.ok('12 price change', 'admin cannot overwrite prices directly (rules only)', sqlerrm ilike '%pricing rules%', sqlerrm); end;
  perform test.reset();
end $$;

-- ================================================================ 13. multi-supplier basket
do $$
declare p1 uuid := test.get('p1')::uuid; p3 uuid; s3 uuid; q jsonb;
begin
  s3 := test.onboard('s3', '00000000-0000-0000-0000-0000000000b3', 'مصنع التمور', '1010000003', 'SA0380000000608010167519', '300000000000003');
  perform test.activate_payments(s3, '00000000-0000-0000-0000-0000000000b3', true);
  perform test.as_user('00000000-0000-0000-0000-0000000000b3');
  p3 := (private.supplier_save_product(null, s3, jsonb_build_object('name','تمر','description','علبة','unit','علبة','category','food',
    'price_halalas',3000,'stock',20,'cities',jsonb_build_array('makkah'),'active',true), null)).id;
  perform test.reset();
  q := public.checkout_quote(jsonb_build_array(jsonb_build_object('product_id',p1,'quantity',1), jsonb_build_object('product_id',p3,'quantity',1)), 'makkah', 'oto');
  perform test.ok('13 multi-supplier', 'quote splits the basket per supplier with disclosure before payment',
    (q->>'requires_split')::boolean and jsonb_array_length(q->'groups') = 2 and q->>'disclosure' is not null, q->>'disclosure');
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000c1');
    perform public.place_order(jsonb_build_array(jsonb_build_object('product_id',p1,'quantity',1), jsonb_build_object('product_id',p3,'quantity',1)),
      'makkah', 'حي العزيزية، شارع 1، مبنى 2', 'عميل', '0500000000', gen_random_uuid(), '{}'::jsonb, 0);
    perform test.ok('13 multi-supplier', 'single payment across suppliers is refused (no non-executable transaction)', false);
  exception when others then perform test.ok('13 multi-supplier', 'single payment across suppliers is refused (no non-executable transaction)', sqlerrm ilike '%multi_supplier_order%', sqlerrm); end;
  perform test.reset();
  perform test.ok('13 multi-supplier', 'each supplier group can be ordered separately',
    test.paid_order('00000000-0000-0000-0000-0000000000c1', jsonb_build_array(jsonb_build_object('product_id',p3,'quantity',1)), 'chg_TEST000010') is not null);
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000c1');
    perform public.place_order(jsonb_build_array(jsonb_build_object('product_id',p3,'quantity',1)), 'makkah', 'حي العزيزية، شارع 1، مبنى 2', 'عميل', '0500000000',
      gen_random_uuid(), '{}'::jsonb, 100);
    perform test.ok('13 multi-supplier', 'platform-funded loyalty discount refused on supplier-direct orders', false);
  exception when others then perform test.ok('13 multi-supplier', 'platform-funded loyalty discount refused on supplier-direct orders', sqlerrm ilike '%loyalty%', sqlerrm); end;
  perform test.reset();
end $$;

-- ================================================================ 14. supplier isolation
do $$
declare s1 uuid := test.get('s1')::uuid; inv1 uuid := test.get('inv1')::uuid; n int; o1 uuid := test.get('o1')::uuid;
begin
  perform test.as_user('00000000-0000-0000-0000-0000000000b3');   -- owner of s3 looks at s1
  select count(*) into n from public.supplier_payment_profiles where supplier_id = s1;
  perform test.ok('14 isolation', 'supplier cannot read another supplier''s payment profile', n = 0, n::text);
  select count(*) into n from public.commission_invoices where supplier_id = s1;
  perform test.ok('14 isolation', 'supplier cannot read another supplier''s invoices', n = 0, n::text);
  select count(*) into n from public.commission_entries where supplier_id = s1;
  perform test.ok('14 isolation', 'supplier cannot read another supplier''s commissions', n = 0, n::text);
  select count(*) into n from public.invoice_payments where supplier_id = s1;
  perform test.ok('14 isolation', 'supplier cannot read another supplier''s payments', n = 0, n::text);
  select count(*) into n from public.supplier_notifications where supplier_id = s1;
  perform test.ok('14 isolation', 'supplier cannot read another supplier''s notifications', n = 0, n::text);
  perform test.reset();
  begin perform test.as_user('00000000-0000-0000-0000-0000000000b3'); perform public.my_payment_profile(s1);
    perform test.ok('14 isolation', 'payment profile RPC denies other suppliers', false);
  exception when others then perform test.ok('14 isolation', 'payment profile RPC denies other suppliers', sqlerrm ilike '%permission denied%', sqlerrm); end;
  begin perform test.as_user('00000000-0000-0000-0000-0000000000b3'); perform public.invoice_document(inv1);
    perform test.ok('14 isolation', 'invoice document denies other suppliers', false);
  exception when others then perform test.ok('14 isolation', 'invoice document denies other suppliers', sqlerrm ilike '%permission denied%', sqlerrm); end;
  begin perform test.as_user('00000000-0000-0000-0000-0000000000b3'); perform public.supplier_finance_summary(s1);
    perform test.ok('14 isolation', 'finance summary denies other suppliers', false);
  exception when others then perform test.ok('14 isolation', 'finance summary denies other suppliers', sqlerrm ilike '%permission denied%', sqlerrm); end;
  begin perform test.as_user('00000000-0000-0000-0000-0000000000b3');
    perform public.supplier_submit_invoice_payment(inv1, 100, 'TRX-HACK', null, null);
    perform test.ok('14 isolation', 'cannot submit payments against another supplier''s invoice', false);
  exception when others then perform test.ok('14 isolation', 'cannot submit payments against another supplier''s invoice', sqlerrm ilike '%permission denied%', sqlerrm); end;
  perform test.as_user('00000000-0000-0000-0000-0000000000c2');
  select count(*) into n from public.orders where id = o1;
  perform test.ok('14 isolation', 'customer cannot read another customer''s order', n = 0, n::text);
  perform test.reset();
  perform test.as_anon();
  begin perform public.admin_finance_settings(); perform test.ok('14 isolation', 'anonymous users cannot reach admin finance', false);
  exception when others then perform test.ok('14 isolation', 'anonymous users cannot reach admin finance', true, sqlerrm); end;
  perform test.reset();
  begin perform test.as_user('00000000-0000-0000-0000-0000000000c1'); perform public.svc_process_charge('tap','chg_FAKE00001', o1, 'CAPTURED', 1, 'SAR', 'test');
    perform test.ok('14 isolation', 'customers cannot call service-role payment functions', false);
  exception when others then perform test.ok('14 isolation', 'customers cannot call service-role payment functions', sqlerrm ilike '%permission denied%', sqlerrm); end;
  perform test.reset();
  perform test.as_user('00000000-0000-0000-0000-0000000000b3');
  select count(*) into n from private.supplier_gateway_secrets;
  perform test.ok('14 isolation', 'gateway secrets unreachable by API roles', false, 'select succeeded');
exception when others then
  perform test.reset();
  perform test.ok('14 isolation', 'gateway secrets unreachable by API roles', sqlerrm ilike '%permission denied%', sqlerrm);
end $$;


-- ================================================================ 15. Tap removed: customer pays supplier by link or cash on delivery
do $$
declare p uuid := test.get('p1')::uuid; v_order uuid; r jsonb; v_seen boolean;
begin
  perform test.ok('15 no Tap', 'supplier-direct is the only payment mode', private.direct_payments_enabled());
  perform test.as_user('00000000-0000-0000-0000-0000000000c1');
  v_order := public.place_order(jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1)), 'makkah', 'حي العزيزية، شارع 1، مبنى 2', 'عميل', '0500000000', gen_random_uuid(), '{}'::jsonb, 0);
  r := public.order_payment_options(v_order);
  perform test.reset();
  perform test.ok('15 no Tap', 'customer sees the supplier payment link and COD option', r->>'payment_link' like 'https://%' and (r->>'accepts_cod')::boolean, r::text);
  begin
    perform test.as_user('00000000-0000-0000-0000-0000000000c2');
    perform public.order_payment_options(v_order);
    perform test.ok('15 no Tap', 'another customer cannot see this order''s payment details', false);
  exception when others then perform test.ok('15 no Tap', 'another customer cannot see this order''s payment details', sqlerrm ilike '%forbidden%', sqlerrm); end;
  perform test.reset();
  perform test.as_user('00000000-0000-0000-0000-0000000000c1');
  perform public.choose_order_payment_method(v_order, 'cod');
  perform test.reset();
  perform test.ok('15 no Tap', 'supplier is notified of the new order awaiting payment',
    exists(select 1 from public.supplier_notifications where ref_id=v_order::text and kind='new_order'));
  perform test.as_user('00000000-0000-0000-0000-0000000000b1');
  r := public.supplier_confirm_order_payment(v_order, null);
  perform test.reset();
  perform test.ok('15 no Tap', 'supplier confirms cash collected -> order paid for the exact payable amount',
    r->>'status' = 'paid' and exists(select 1 from private.order_payments op join public.orders o on o.id=op.order_id
      where op.order_id=v_order and op.amount_halalas=o.payable_halalas and op.gateway='cod'), r::text);
  perform test.as_service();
  begin
    perform public.svc_process_charge('tap', 'chg_X', v_order, 'CAPTURED', 1, 'SAR', 'test');
    v_seen := true;
  exception when others then v_seen := false; end;
  perform test.reset();
  perform test.ok('15 no Tap', 'Tap charge entry point is retired', not v_seen);
end $$;

-- ================================================================ 16. pricing confidentiality
do $$
declare p uuid := test.get('p1')::uuid; o uuid := test.get('o1')::uuid;
begin
  perform test.as_anon();
  begin perform supplier_price_halalas from public.products where id=p; perform test.ok('16 confidentiality', 'shoppers cannot read supplier original price/markup', false);
  exception when others then perform test.ok('16 confidentiality', 'shoppers cannot read supplier original price/markup', sqlerrm ilike '%permission denied%', sqlerrm); end;
  perform test.ok('16 confidentiality', 'shoppers can still read the public catalogue price', (select display_price_halalas from public.products where id=p) > 0);
  perform test.reset();
  perform test.as_user('00000000-0000-0000-0000-0000000000c1');
  begin perform base_commission_halalas from public.order_items where order_id=o; perform test.ok('16 confidentiality', 'customers cannot read Rawaa commission on their lines', false);
  exception when others then perform test.ok('16 confidentiality', 'customers cannot read Rawaa commission on their lines', sqlerrm ilike '%permission denied%', sqlerrm); end;
  perform test.ok('16 confidentiality', 'customers still read their own line prices', (select count(*) from public.order_items where order_id=o) = 1);
  perform test.reset();
end $$;

-- ---------------------------------------------------------------- report
select test.reset();
\echo
\echo '================ FINANCE INTEGRATION TEST RESULTS ================'
select scenario, case when ok then 'PASS' else 'FAIL' end as result, name, case when not ok then detail end as detail from test.results order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from test.results;
rollback;
