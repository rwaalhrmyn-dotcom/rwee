-- Remove Tap from Rawaa: customers pay the supplier directly through the supplier's own
-- payment link or cash on delivery. The supplier confirms receipt; Rawaa never touches the
-- money and collects its commission from the supplier through the monthly invoice.
-- Additive: the old gateway columns/tables stay (no data loss) but are no longer required.

alter table public.supplier_payment_profiles add column if not exists payment_link text
  check (payment_link is null or (payment_link ~ '^https://[^\s<>"'']{4,}$' and length(payment_link) <= 500));
alter table public.supplier_payment_profiles add column if not exists accepts_cod boolean not null default false;
alter table public.supplier_payment_profiles add column if not exists payment_instructions text
  check (payment_instructions is null or length(payment_instructions) <= 500);

-- A supplier needs at least one way to be paid (link or COD) instead of a Tap key.
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
  if p.payment_link is null and not p.accepts_cod then m := array_append(m, 'payment_method'); end if;
  return m;
end $$;

create or replace function public.admin_review_payment_profile(p_supplier uuid, p_action text, p_note text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare cur public.supplier_payment_profiles; miss text[]; v_new text;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into cur from public.supplier_payment_profiles where supplier_id=p_supplier for update;
  if not found then raise exception 'payment profile not found'; end if;
  miss := private.payment_profile_missing(cur);
  if p_action in ('approve','reactivate') then
    if cardinality(miss) > 0 then raise exception 'payment profile incomplete: %', array_to_string(miss, ', '); end if;
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
    coalesce(p_note, case v_new when 'active' then 'تم التحقق من بيانات الدفع وطرق استلام ثمن الطلبات.' else 'راجع إعدادات الدفع في لوحة المورد.' end),
    'payment_profile', p_supplier::text, null);
  update private.finance_alerts set resolved_at=now(), resolved_by=auth.uid(), resolution_note=p_action
   where supplier_id=p_supplier and kind='payment_profile_review' and resolved_at is null;
  perform private.refresh_supplier_selling(p_supplier);
  return jsonb_build_object('status', v_new);
end $$;

-- Supplier sets how customers pay it. Changing the link on an approved profile sends it back
-- to admin verification (anti-fraud): selling pauses until the new link is approved.
create or replace function public.supplier_set_payment_methods(p_supplier uuid, p_link text, p_cod boolean, p_instructions text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare cur public.supplier_payment_profiles; v_link text := nullif(btrim(coalesce(p_link,'')),''); v_status text;
begin
  perform private.require_supplier_owner(p_supplier);
  if v_link is not null and (v_link !~ '^https://[^\s<>"'']{4,}$' or length(v_link) > 500) then raise exception 'payment link must be a valid https:// URL'; end if;
  insert into public.supplier_payment_profiles(supplier_id) values (p_supplier) on conflict (supplier_id) do nothing;
  select * into cur from public.supplier_payment_profiles where supplier_id=p_supplier for update;
  v_status := cur.status;
  if cur.status = 'active' and (v_link is distinct from cur.payment_link or coalesce(p_cod,false) is distinct from cur.accepts_cod) then
    v_status := 'pending';
    perform private.raise_finance_alert('payment_profile_review','warning',p_supplier,null,null,'المورد عدّل طرق استلام الدفع — يلزم التحقق قبل إعادة التفعيل',
      jsonb_build_object('old_link',cur.payment_link,'new_link',v_link,'cod',p_cod), null);
  end if;
  update public.supplier_payment_profiles set payment_link=v_link, accepts_cod=coalesce(p_cod,false),
    payment_instructions=nullif(btrim(coalesce(p_instructions,'')),''), status=v_status,
    submitted_at=case when v_status='pending' then now() else submitted_at end, updated_at=now()
  where supplier_id=p_supplier returning * into cur;
  if cur.status = 'incomplete' and cardinality(private.payment_profile_missing(cur)) = 0 then
    update public.supplier_payment_profiles set status='pending', submitted_at=now() where supplier_id=p_supplier returning * into cur;
    perform private.raise_finance_alert('payment_profile_review','info',p_supplier,null,null,'بيانات دفع مورد مكتملة بانتظار التحقق', null, null);
  end if;
  perform private.fin_audit('payment_profile', p_supplier::text, 'set_payment_methods', null,
    jsonb_build_object('payment_link', v_link, 'accepts_cod', p_cod, 'status', cur.status));
  perform private.refresh_supplier_selling(p_supplier);
  return jsonb_build_object('status', cur.status, 'missing', private.payment_profile_missing(cur));
end $$;

-- Orders: how the customer chose to pay.
alter table public.orders add column if not exists payment_method text check (payment_method in ('supplier_link','cod'));

create or replace function public.order_payment_options(p_order uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare o public.orders; p public.supplier_payment_profiles;
begin
  select * into o from public.orders where id=p_order;
  if not found or not (private.can_access_order(o.id) or private.owns_supplier(o.supplier_id) or private.is_platform_operator()) then
    raise exception 'forbidden' using errcode='42501'; end if;
  select * into p from public.supplier_payment_profiles where supplier_id=o.supplier_id and status='active';
  return jsonb_build_object('order_id', o.id, 'payable_halalas', o.payable_halalas, 'payment_status', o.payment_status, 'payment_method', o.payment_method,
    'supplier_name', (select s.name from public.suppliers s where s.id=o.supplier_id),
    'payment_link', p.payment_link, 'accepts_cod', coalesce(p.accepts_cod,false), 'instructions', p.payment_instructions);
end $$;

create or replace function public.choose_order_payment_method(p_order uuid, p_method text) returns void
language plpgsql security definer set search_path='' as $$
declare o public.orders; p public.supplier_payment_profiles;
begin
  select * into o from public.orders where id=p_order for update;
  if not found or not private.can_access_order(o.id) then raise exception 'forbidden' using errcode='42501'; end if;
  if o.payment_mode <> 'supplier_direct' then raise exception 'order does not use supplier-direct payment'; end if;
  if o.payment_status = 'paid' or o.status = 'cancelled' then raise exception 'order payment can no longer be changed'; end if;
  select * into p from public.supplier_payment_profiles where supplier_id=o.supplier_id and status='active';
  if p.supplier_id is null then raise exception 'supplier cannot receive payments right now'; end if;
  if p_method = 'supplier_link' and p.payment_link is null then raise exception 'supplier has no payment link'; end if;
  if p_method = 'cod' and not p.accepts_cod then raise exception 'supplier does not accept cash on delivery'; end if;
  if p_method not in ('supplier_link','cod') then raise exception 'invalid payment method'; end if;
  update public.orders set payment_method=p_method where id=o.id;
  perform private.notify_supplier(o.supplier_id, 'new_order', 'طلب جديد بانتظار الدفع',
    'طلب بقيمة '||to_char(o.payable_halalas/100.0,'FM999999990.00')||' ر.س — طريقة الدفع: '||case p_method when 'cod' then 'الدفع عند الاستلام' else 'رابط الدفع الخاص بك' end
    ||'. أكّد استلام المبلغ من صفحة الطلبات.', 'order', o.id::text, 'neworder:'||o.id);
end $$;

-- Supplier confirms it received the full amount (link payment or cash on delivery).
create or replace function public.supplier_confirm_order_payment(p_order uuid, p_reference text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders; v_ref text := nullif(btrim(coalesce(p_reference,'')),''); v_at timestamptz := now();
begin
  select * into o from public.orders where id=p_order for update;
  if not found or not private.owns_supplier(o.supplier_id) then raise exception 'forbidden' using errcode='42501'; end if;
  if o.payment_mode <> 'supplier_direct' then raise exception 'order does not use supplier-direct payment'; end if;
  if o.status = 'cancelled' then raise exception 'order is cancelled'; end if;
  if o.payment_status = 'paid' then return jsonb_build_object('status','already_paid'); end if;
  if o.payment_method is null then raise exception 'customer has not chosen a payment method yet'; end if;
  if o.payment_method = 'supplier_link' and (v_ref is null or length(v_ref) < 3) then raise exception 'payment reference required'; end if;
  insert into private.order_payments(order_id, reference, amount_halalas, verified_by, verified_at, gateway)
  values (o.id, coalesce(v_ref, 'cod:'||o.id), o.payable_halalas, auth.uid(), v_at, o.payment_method);
  update public.orders set payment_status='paid', paid_at=v_at where id=o.id;
  insert into private.payment_events(provider,event_key,charge_id,order_id,provider_status,amount_halalas,outcome)
  values (o.payment_method, o.payment_method||':'||o.id||':CONFIRMED', coalesce(v_ref,'cod'), o.id, 'SUPPLIER_CONFIRMED', o.payable_halalas, 'paid');
  perform private.fin_audit('payment', o.id::text, 'supplier_confirmed_payment', null,
    jsonb_build_object('method',o.payment_method,'reference',v_ref,'amount_halalas',o.payable_halalas));
  return jsonb_build_object('status','paid');
end $$;

-- Refunds are made by the supplier outside the platform and recorded here; the matching
-- commission is reversed (credit note if the month's invoice was already issued).
create or replace function public.supplier_record_refund(p_order uuid, p_amount_halalas bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders; v_ref text;
begin
  select * into o from public.orders where id=p_order;
  if not found or not (private.owns_supplier(o.supplier_id) or private.is_platform_operator()) then raise exception 'forbidden' using errcode='42501'; end if;
  if o.payment_mode <> 'supplier_direct' then raise exception 'order does not use supplier-direct payment'; end if;
  select reference into v_ref from private.order_payments where order_id=o.id;
  return private.svc_record_refund(o.id, 'manual:'||gen_random_uuid(), v_ref, p_amount_halalas, 'succeeded', p_reason, auth.uid());
end $$;

-- Supplier's view of direct orders awaiting/with payment.
create or replace function public.supplier_direct_orders(p_supplier uuid) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform private.require_supplier_owner(p_supplier);
  return query select jsonb_build_object('id', o.id, 'created_at', o.created_at, 'status', o.status, 'payment_status', o.payment_status,
      'payment_method', o.payment_method, 'payable_halalas', o.payable_halalas, 'refunded_halalas', o.refunded_halalas,
      'recipient_name', o.recipient_name, 'city', o.city)
    from public.orders o where o.supplier_id=p_supplier and o.payment_mode='supplier_direct' order by o.created_at desc limit 500;
end $$;

revoke all on function public.supplier_set_payment_methods(uuid,text,boolean,text), public.order_payment_options(uuid),
  public.choose_order_payment_method(uuid,text), public.supplier_confirm_order_payment(uuid,text),
  public.supplier_record_refund(uuid,bigint,text), public.supplier_direct_orders(uuid) from public, anon;
grant execute on function public.supplier_set_payment_methods(uuid,text,boolean,text), public.order_payment_options(uuid),
  public.choose_order_payment_method(uuid,text), public.supplier_confirm_order_payment(uuid,text),
  public.supplier_record_refund(uuid,bigint,text), public.supplier_direct_orders(uuid) to authenticated;

-- Tap service entry points are retired.
revoke execute on function public.svc_charge_context(uuid,uuid), public.svc_order_gateway_secret(uuid),
  public.svc_record_charge_initiated(uuid,text,text,bigint,text,uuid), public.svc_process_charge(text,text,uuid,text,bigint,text,text) from service_role;

-- Tap is gone, so supplier-direct is now the only payment mode.
update private.finance_settings set direct_payments_enabled = true, tap_live_contract_confirmed = false, updated_at = now() where id;
select private.refresh_all_supplier_selling();
