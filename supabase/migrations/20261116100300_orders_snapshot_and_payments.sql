-- Purchase-time financial snapshot per order line, single-supplier orders for
-- supplier-direct payments, server-side quotes, and verified gateway processing
-- (duplicates, amount mismatches, cancellations, refunds, disputes).

-- ---------------------------------------------------------------- snapshot columns
alter table public.order_items add column if not exists supplier_id uuid references public.suppliers(id);
alter table public.order_items add column if not exists supplier_price_halalas integer;
alter table public.order_items add column if not exists markup_halalas integer not null default 0;
alter table public.order_items add column if not exists pricing_rule_id uuid;
alter table public.order_items add column if not exists commission_rate_bp integer;
alter table public.order_items add column if not exists commission_on_markup boolean;
alter table public.order_items add column if not exists base_commission_halalas bigint not null default 0;
alter table public.order_items add column if not exists markup_commission_halalas bigint not null default 0;
alter table public.order_items add column if not exists line_net_halalas bigint;
alter table public.order_items add column if not exists vat_rate_bp integer not null default 0;
alter table public.order_items add column if not exists line_vat_halalas bigint not null default 0;

create or replace function private.trg_order_item_immutable() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op = 'DELETE' then raise exception 'order lines are immutable financial records'; end if;
  if (old.product_id, old.unit_price_halalas, old.quantity, old.supplier_id, old.supplier_price_halalas, old.markup_halalas, old.commission_rate_bp,
      old.commission_on_markup, old.base_commission_halalas, old.markup_commission_halalas, old.line_net_halalas, old.vat_rate_bp, old.line_vat_halalas)
     is distinct from
     (new.product_id, new.unit_price_halalas, new.quantity, new.supplier_id, new.supplier_price_halalas, new.markup_halalas, new.commission_rate_bp,
      new.commission_on_markup, new.base_commission_halalas, new.markup_commission_halalas, new.line_net_halalas, new.vat_rate_bp, new.line_vat_halalas) then
    raise exception 'order line pricing snapshot is immutable';
  end if;
  return new;
end $$;
drop trigger if exists order_item_immutable on public.order_items;
create trigger order_item_immutable before update or delete on public.order_items for each row execute function private.trg_order_item_immutable();

alter table public.orders add column if not exists supplier_id uuid references public.suppliers(id);
alter table public.orders add column if not exists payment_mode text not null default 'platform_legacy' check (payment_mode in ('platform_legacy','supplier_direct'));
alter table public.orders add column if not exists vat_rate_bp integer not null default 0;
alter table public.orders add column if not exists items_vat_halalas bigint not null default 0;
alter table public.orders add column if not exists vat_halalas bigint not null default 0;
-- orders.total_halalas is a generated legacy column (subtotal + customization - loyalty, no delivery/VAT);
-- payable_halalas is the VAT-inclusive amount the customer pays on supplier-direct orders.
alter table public.orders add column if not exists payable_halalas bigint;
alter table public.orders add column if not exists delivered_at timestamptz;
alter table public.orders add column if not exists cancelled_at timestamptz;
alter table public.orders add column if not exists refunded_halalas bigint not null default 0 check (refunded_halalas >= 0);
alter table public.orders add column if not exists refund_status text not null default 'none' check (refund_status in ('none','partial','full'));
alter table public.orders add column if not exists payment_flag text check (payment_flag in ('duplicate_payment','amount_mismatch','paid_after_cancel'));

-- Totals for supplier-direct orders are always computed server-side; once paid they are frozen.
create or replace function private.trg_order_totals() returns trigger language plpgsql set search_path='' as $$
declare v_payable bigint; v_vat bigint;
begin
  if tg_op = 'UPDATE' then
    if new.status = 'delivered' and old.status is distinct from 'delivered' then new.delivered_at := coalesce(new.delivered_at, now()); end if;
    if new.status = 'cancelled' and old.status is distinct from 'cancelled' then new.cancelled_at := coalesce(new.cancelled_at, now()); end if;
  end if;
  if new.payment_mode = 'supplier_direct' then
    v_vat := new.items_vat_halalas + round(coalesce(new.delivery_halalas,0)::numeric * new.vat_rate_bp / 10000)::bigint;
    v_payable := new.subtotal_halalas + coalesce(new.delivery_halalas,0) + v_vat;
    if tg_op = 'UPDATE' and old.payment_status = 'paid' and (v_payable is distinct from old.payable_halalas or v_vat is distinct from old.vat_halalas
       or new.subtotal_halalas is distinct from old.subtotal_halalas or new.delivery_halalas is distinct from old.delivery_halalas) then
      raise exception 'amounts of a paid order are immutable'; end if;
    new.vat_halalas := v_vat; new.payable_halalas := v_payable;
  end if;
  return new;
end $$;
drop trigger if exists order_totals on public.orders;
create trigger order_totals before insert or update on public.orders for each row execute function private.trg_order_totals();

-- ---------------------------------------------------------------- line pricing (shared by quote and order placement)
create or replace function private.price_line(p public.products, p_qty integer, s private.finance_settings,
  out supplier_price integer, out markup integer, out unit_price integer, out line_net bigint, out vat_bp integer, out line_vat bigint,
  out base_commission bigint, out markup_commission bigint)
language plpgsql stable set search_path='' as $$
begin
  supplier_price := p.supplier_price_halalas; markup := p.markup_halalas; unit_price := p.price_halalas;
  line_net := unit_price::bigint * p_qty; vat_bp := p.vat_rate_bp;
  line_vat := round(line_net::numeric * vat_bp / 10000)::bigint;
  base_commission := round((supplier_price::bigint * p_qty + case when s.commission_on_markup then markup::bigint * p_qty else 0 end)::numeric
                           * s.commission_rate_bp / 10000)::bigint;
  markup_commission := markup::bigint * p_qty;
end $$;

-- Read-only, authoritative quote. Groups the basket by supplier because each supplier
-- collects its own payment; the shopper sees this split before paying.
create or replace function public.checkout_quote(p_items jsonb, p_city text, p_delivery_method text default 'oto') returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s private.finance_settings := private.fin(); v_line jsonb; p public.products; q integer; l record; sup public.suppliers;
  groups jsonb := '{}'::jsonb; g jsonb; k text; result jsonb := '[]'::jsonb; d record; v_fee integer; v_del_vat bigint; v_unavailable jsonb := '[]'::jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 30 then raise exception 'invalid items'; end if;
  select supplier_delivery_halalas, oto_waybill_halalas into d from private.delivery_settings limit 1;
  for v_line in select value from jsonb_array_elements(p_items) loop
    q := coalesce((v_line->>'quantity')::integer, 0);
    select * into p from public.products where id = (v_line->>'product_id')::uuid;
    select * into sup from public.suppliers where id = p.supplier_id;
    if p.id is null or not p.active or p.archived or q not between 1 and 99 or (p_city is not null and not (p_city = any(p.cities)))
       or sup.id is null or not sup.selling_enabled or p.stock < q then
      v_unavailable := v_unavailable || jsonb_build_object('product_id', v_line->>'product_id', 'name', p.name,
        'reason', case when p.id is null or not p.active or p.archived then 'unavailable' when p.stock < q then 'insufficient_stock'
                       when sup.id is null or not sup.selling_enabled then 'supplier_not_selling' else 'not_in_city' end);
      continue;
    end if;
    select * into l from private.price_line(p, q, s);
    k := p.supplier_id::text;
    g := coalesce(groups->k, jsonb_build_object('supplier_id', p.supplier_id, 'supplier_name', sup.name, 'accepts_delivery', sup.accepts_delivery,
           'vat_rate_bp', private.supplier_vat_bp(p.supplier_id), 'lines', '[]'::jsonb, 'subtotal_halalas', 0, 'items_vat_halalas', 0));
    g := jsonb_set(g, '{lines}', (g->'lines') || jsonb_build_object('product_id', p.id, 'name', p.name, 'quantity', q, 'unit_price_halalas', l.unit_price,
           'line_net_halalas', l.line_net, 'vat_rate_bp', l.vat_bp, 'line_vat_halalas', l.line_vat, 'line_total_halalas', l.line_net + l.line_vat));
    g := jsonb_set(g, '{subtotal_halalas}', to_jsonb((g->>'subtotal_halalas')::bigint + l.line_net));
    g := jsonb_set(g, '{items_vat_halalas}', to_jsonb((g->>'items_vat_halalas')::bigint + l.line_vat));
    groups := jsonb_set(groups, array[k], g);
  end loop;
  for k in select jsonb_object_keys(groups) loop
    g := groups->k;
    v_fee := case when p_delivery_method = 'supplier' and (g->>'accepts_delivery')::boolean then coalesce(d.supplier_delivery_halalas, 25) else coalesce(d.oto_waybill_halalas, 0) end;
    v_del_vat := round(v_fee::numeric * (g->>'vat_rate_bp')::integer / 10000)::bigint;
    g := g || jsonb_build_object('delivery_halalas', v_fee, 'delivery_method', case when p_delivery_method='supplier' and (g->>'accepts_delivery')::boolean then 'supplier' else 'oto' end,
      'vat_halalas', (g->>'items_vat_halalas')::bigint + v_del_vat,
      'total_halalas', (g->>'subtotal_halalas')::bigint + v_fee + (g->>'items_vat_halalas')::bigint + v_del_vat);
    result := result || g;
  end loop;
  return jsonb_build_object('direct_payments', s.direct_payments_enabled, 'groups', result, 'supplier_count', jsonb_array_length(result),
    'requires_split', s.direct_payments_enabled and jsonb_array_length(result) > 1, 'unavailable', v_unavailable,
    'disclosure', case when s.direct_payments_enabled and jsonb_array_length(result) > 1 then
      'تحتوي سلتك على منتجات من أكثر من مورد. يُحصَّل ثمن كل طلب مباشرة لحساب مورده، لذلك يتم الدفع لكل مورد في عملية مستقلة.' else null end);
end $$;
grant execute on function public.checkout_quote(jsonb, text, text) to anon, authenticated;

-- ---------------------------------------------------------------- order placement with snapshots
create or replace function private.place_order(p_items jsonb, p_city text, p_address text, p_recipient_name text, p_phone text, p_request_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_line jsonb; v_product public.products%rowtype; v_quantity integer; v_total bigint:=0; v_items_vat bigint:=0;
  v_seen uuid[]:=array[]::uuid[]; s private.finance_settings := private.fin(); l record; v_supplier uuid; v_direct boolean;
begin
 perform private.assert_account_session();
 if v_user is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 if p_request_id is null then raise exception 'request id required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||p_request_id::text,0));
 select id into v_id from public.orders where customer_id=v_user and request_id=p_request_id;
 if v_id is not null then return v_id; end if;
 if p_city is null or p_city not in ('makkah','madinah','jeddah','taif') or p_address is null or length(p_address) not between 10 and 1000 or p_recipient_name is null or length(p_recipient_name) not between 2 and 100 or p_phone is null or p_phone !~ '^[+0-9 ()-]{9,20}$' then raise exception 'invalid delivery details'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'invalid items'; end if;
 if jsonb_array_length(p_items) not between 1 and 30 then raise exception 'invalid item count'; end if;
 v_direct := s.direct_payments_enabled;
 if v_direct then
   -- one payment collected by one supplier's own gateway: the basket must be single-supplier
   select min(p.supplier_id::text)::uuid into v_supplier from jsonb_array_elements(p_items) e join public.products p on p.id=(e.value->>'product_id')::uuid;
   if (select count(distinct p.supplier_id) from jsonb_array_elements(p_items) e join public.products p on p.id=(e.value->>'product_id')::uuid) > 1 then
     raise exception 'multi_supplier_order: split the basket by supplier; each supplier collects its own payment' using errcode='P0001'; end if;
   if not exists(select 1 from public.suppliers where id=v_supplier and selling_enabled) then
     raise exception 'supplier unavailable for paid orders' using errcode='P0001'; end if;
 end if;
 v_id:=gen_random_uuid();
 insert into public.orders(id,customer_id,request_id,city,address,recipient_name,phone,subtotal_halalas,supplier_id,payment_mode,vat_rate_bp)
 values(v_id,v_user,p_request_id,p_city,p_address,p_recipient_name,p_phone,0, case when v_direct then v_supplier end,
   case when v_direct then 'supplier_direct' else 'platform_legacy' end, case when v_direct then private.supplier_vat_bp(v_supplier) else 0 end);
 for v_line in select value from jsonb_array_elements(p_items) order by value->>'product_id' loop
  if jsonb_typeof(v_line->'quantity')<>'number' or (v_line->>'quantity') !~ '^[0-9]{1,2}$' then raise exception 'invalid quantity'; end if;
  v_quantity:=(v_line->>'quantity')::integer;
  if v_quantity is null or v_quantity not between 1 and 99 then raise exception 'invalid quantity'; end if;
  if (v_line->>'product_id')::uuid=any(v_seen) then raise exception 'duplicate product'; end if;
  select * into v_product from public.products where id=(v_line->>'product_id')::uuid for update;
  if not found or not v_product.active or v_product.archived or not(p_city=any(v_product.cities)) then raise exception 'unavailable product'; end if;
  if not exists(select 1 from public.suppliers s2 where s2.id=v_product.supplier_id and s2.approval_status='approved' and s2.selling_enabled and p_city=any(s2.cities)) then raise exception 'supplier unavailable'; end if;
  if v_product.stock<v_quantity then raise exception 'insufficient stock'; end if;
  v_seen:=array_append(v_seen,v_product.id);
  select * into l from private.price_line(v_product, v_quantity, s);
  update public.products set stock=stock-v_quantity where id=v_product.id;
  v_total:=v_total+l.line_net; v_items_vat := v_items_vat + l.line_vat;
  insert into public.order_items(order_id,product_id,product_name,unit_price_halalas,quantity,supplier_id,supplier_price_halalas,markup_halalas,pricing_rule_id,
    commission_rate_bp,commission_on_markup,base_commission_halalas,markup_commission_halalas,line_net_halalas,vat_rate_bp,line_vat_halalas)
  values(v_id,v_product.id,v_product.name,l.unit_price,v_quantity,v_product.supplier_id,l.supplier_price,l.markup,v_product.pricing_rule_id,
    s.commission_rate_bp,s.commission_on_markup,l.base_commission,l.markup_commission,l.line_net,l.vat_bp,l.line_vat);
 end loop;
 update public.orders set subtotal_halalas=v_total, items_vat_halalas=v_items_vat where id=v_id;
 return v_id;
end $$;

-- Platform-funded extras (loyalty discounts, name printing) cannot be applied to money
-- that settles directly in the supplier's account.
create or replace function public.place_order(p_items jsonb, p_city text, p_address text, p_recipient_name text, p_phone text, p_request_id uuid,
  p_customization jsonb, p_loyalty_points integer) returns uuid
language plpgsql set search_path='' as $$
begin
  if private.direct_payments_enabled() and (coalesce(p_loyalty_points,0) > 0 or coalesce((p_customization->>'print_name')::boolean,false)) then
    raise exception 'loyalty redemption and name printing are not available for supplier-direct orders';
  end if;
  return private.place_loyalty_order(p_items,p_city,p_address,p_recipient_name,p_phone,p_request_id,p_customization,p_loyalty_points);
end $$;
create or replace function public.place_order(p_items jsonb, p_city text, p_address text, p_recipient_name text, p_phone text, p_request_id uuid, p_customization jsonb) returns uuid
language plpgsql set search_path='' as $$
begin
  if private.direct_payments_enabled() and coalesce((p_customization->>'print_name')::boolean,false) then
    raise exception 'name printing is not available for supplier-direct orders'; end if;
  return private.place_customized_order(p_items,p_city,p_address,p_recipient_name,p_phone,p_request_id,p_customization);
end $$;
grant execute on function private.direct_payments_enabled() to authenticated;

-- Unpaid orders: customer may cancel; stock is restored exactly once.
create or replace function private.trg_order_cancel_effects() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    if new.payment_status = 'unpaid' then
      update public.products p set stock = p.stock + i.quantity from public.order_items i where i.order_id = new.id and p.id = i.product_id;
    elsif new.refund_status <> 'full' then
      perform private.raise_finance_alert('paid_order_cancelled','critical',new.supplier_id,new.id,null,
        'تم إلغاء طلب مدفوع دون استرجاع كامل — يلزم تنفيذ الاسترجاع عبر بوابة المورد', null, 'cancel:'||new.id);
    end if;
  end if;
  return null;
end $$;
drop trigger if exists order_cancel_effects on public.orders;
create trigger order_cancel_effects after update of status on public.orders for each row execute function private.trg_order_cancel_effects();

create or replace function public.cancel_my_order(p_order uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  perform private.assert_account_session();
  update public.orders set status='cancelled' where id=p_order and customer_id=auth.uid() and payment_status='unpaid' and status='pending';
  if not found then raise exception 'only your own unpaid pending orders can be cancelled'; end if;
end $$;
revoke all on function public.cancel_my_order(uuid) from public, anon; grant execute on function public.cancel_my_order(uuid) to authenticated;

-- ---------------------------------------------------------------- gateway records
create table if not exists private.gateway_charges (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  supplier_id uuid not null references public.suppliers(id),
  provider text not null check (provider in ('tap')),
  charge_id text unique,
  amount_halalas bigint not null check (amount_halalas > 0),
  currency text not null default 'SAR',
  mode text check (mode in ('test','live')),
  status text not null default 'initiated' check (status in ('initiated','captured','failed','cancelled','duplicate','refunded','partially_refunded','captured_after_cancel','amount_mismatch')),
  provider_status text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists gateway_charges_order_idx on private.gateway_charges(order_id);
alter table private.gateway_charges enable row level security;
revoke all on private.gateway_charges from public, anon, authenticated;

create table if not exists private.payment_events (
  id bigint generated always as identity primary key,
  provider text not null,
  event_key text not null unique,
  charge_id text,
  order_id uuid,
  provider_status text,
  amount_halalas bigint,
  outcome text,
  received_at timestamptz not null default now()
);
alter table private.payment_events enable row level security;
revoke all on private.payment_events from public, anon, authenticated;

create table if not exists public.order_refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  supplier_id uuid references public.suppliers(id),
  charge_id text,
  provider_refund_id text unique,
  amount_halalas bigint not null check (amount_halalas > 0),
  reason text not null check (length(btrim(reason)) between 3 and 500),
  status text not null default 'pending' check (status in ('pending','succeeded','failed')),
  requested_by uuid,
  created_at timestamptz not null default now(),
  processed_at timestamptz,
  commission_reversed boolean not null default false
);
alter table public.order_refunds enable row level security;
revoke all on public.order_refunds from public, anon, authenticated;
grant select on public.order_refunds to authenticated;
create policy order_refunds_read on public.order_refunds for select to authenticated
  using (private.can_access_order(order_id) or (select private.is_platform_operator()) or private.owns_supplier(supplier_id));

create table if not exists public.payment_disputes (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  supplier_id uuid references public.suppliers(id),
  opened_by uuid not null,
  opened_role text not null check (opened_role in ('customer','admin')),
  reason text not null check (length(btrim(reason)) between 5 and 1000),
  status text not null default 'open' check (status in ('open','under_review','resolved_customer','resolved_supplier','closed')),
  resolution_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_by uuid,
  resolved_at timestamptz
);
create unique index if not exists one_open_dispute_per_order on public.payment_disputes(order_id) where status in ('open','under_review');
alter table public.payment_disputes enable row level security;
revoke all on public.payment_disputes from public, anon, authenticated;
grant select on public.payment_disputes to authenticated;
create policy payment_disputes_read on public.payment_disputes for select to authenticated
  using (private.can_access_order(order_id) or (select private.is_platform_operator()) or private.owns_supplier(supplier_id));

-- ---------------------------------------------------------------- service-role entry points (Edge Functions)
create or replace function private.svc_charge_context(p_order uuid, p_user uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders; pp public.supplier_payment_profiles; sec private.supplier_gateway_secrets; sup public.suppliers;
begin
  select * into o from public.orders where id=p_order for update;
  if not found or o.customer_id is distinct from p_user then raise exception 'order not found' using errcode='42501'; end if;
  if o.payment_mode <> 'supplier_direct' then raise exception 'order does not use supplier-direct payment'; end if;
  if o.payment_status = 'paid' then raise exception 'order already paid'; end if;
  if o.status = 'cancelled' then raise exception 'order cancelled'; end if;
  select * into sup from public.suppliers where id=o.supplier_id;
  if not sup.selling_enabled then raise exception 'supplier cannot accept payments right now'; end if;
  select * into pp from public.supplier_payment_profiles where supplier_id=o.supplier_id;
  select * into sec from private.supplier_gateway_secrets where supplier_id=o.supplier_id;
  if pp.status <> 'active' or sec.supplier_id is null then raise exception 'supplier payment gateway not active'; end if;
  if o.payable_halalas is null or o.payable_halalas <= 0 then raise exception 'invalid order amount'; end if;
  return jsonb_build_object('order_id', o.id, 'supplier_id', o.supplier_id, 'supplier_name', sup.name, 'amount_halalas', o.payable_halalas, 'currency', 'SAR',
    'recipient_name', o.recipient_name, 'phone', o.phone, 'provider', sec.provider, 'mode', pp.gateway_mode, 'merchant_id', pp.gateway_merchant_id,
    'ciphertext', sec.ciphertext, 'iv', sec.iv, 'key_version', sec.key_version);
end $$;

create or replace function private.svc_order_gateway_secret(p_order uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare o public.orders; sec private.supplier_gateway_secrets;
begin
  select * into o from public.orders where id=p_order;
  if not found or o.supplier_id is null then return null; end if;
  select * into sec from private.supplier_gateway_secrets where supplier_id=o.supplier_id;
  if sec.supplier_id is null then return null; end if;
  return jsonb_build_object('order_id', o.id, 'supplier_id', o.supplier_id, 'provider', sec.provider, 'ciphertext', sec.ciphertext, 'iv', sec.iv,
    'key_version', sec.key_version, 'payable_halalas', o.payable_halalas, 'refunded_halalas', o.refunded_halalas,
    'charge_id', (select c.charge_id from private.gateway_charges c where c.order_id=o.id and c.status in ('captured','partially_refunded') order by c.updated_at desc limit 1));
end $$;

create or replace function private.svc_record_charge_initiated(p_order uuid, p_provider text, p_charge_id text, p_amount bigint, p_mode text, p_user uuid) returns void
language plpgsql security definer set search_path='' as $$
declare o public.orders;
begin
  select * into o from public.orders where id=p_order;
  if p_charge_id !~ '^chg_[A-Za-z0-9_]{6,80}$' then raise exception 'invalid charge id'; end if;
  insert into private.gateway_charges(order_id, supplier_id, provider, charge_id, amount_halalas, mode, created_by)
  values (p_order, o.supplier_id, p_provider, p_charge_id, p_amount, p_mode, p_user) on conflict (charge_id) do nothing;
end $$;

-- Idempotent, authoritative charge processing. Called with data the Edge Function
-- re-fetched from the provider using the supplier's own key (never trusting the payload).
create or replace function private.svc_process_charge(p_provider text, p_charge_id text, p_order uuid, p_provider_status text,
  p_amount_halalas bigint, p_currency text, p_mode text) returns text
language plpgsql security definer set search_path='' as $$
declare o public.orders; v_outcome text; v_existing text; v_key text := p_provider||':'||p_charge_id||':'||upper(coalesce(p_provider_status,''));
begin
  if exists(select 1 from private.payment_events where event_key=v_key) then return 'duplicate_event_ignored'; end if;
  select * into o from public.orders where id=p_order for update;
  if not found then
    insert into private.payment_events(provider,event_key,charge_id,order_id,provider_status,amount_halalas,outcome) values (p_provider,v_key,p_charge_id,null,p_provider_status,p_amount_halalas,'unknown_order');
    return 'unknown_order';
  end if;
  insert into private.gateway_charges(order_id, supplier_id, provider, charge_id, amount_halalas, mode, provider_status)
  values (o.id, o.supplier_id, p_provider, p_charge_id, greatest(p_amount_halalas,1), p_mode, p_provider_status)
  on conflict (charge_id) do update set provider_status = excluded.provider_status, updated_at = now();

  if upper(p_provider_status) = 'CAPTURED' then
    select reference into v_existing from private.order_payments where order_id=o.id;
    if v_existing = p_charge_id then v_outcome := 'already_recorded';
    elsif v_existing is not null then
      update private.gateway_charges set status='duplicate', updated_at=now() where charge_id=p_charge_id;
      update public.orders set payment_flag='duplicate_payment' where id=o.id;
      perform private.raise_finance_alert('duplicate_payment','critical',o.supplier_id,o.id,null,'دفعة مكررة لطلب مدفوع مسبقاً — يلزم استرجاعها للعميل',
        jsonb_build_object('charge_id',p_charge_id,'amount_halalas',p_amount_halalas),'dup:'||p_charge_id);
      v_outcome := 'duplicate_payment_flagged';
    elsif o.status = 'cancelled' then
      update private.gateway_charges set status='captured_after_cancel', updated_at=now() where charge_id=p_charge_id;
      update public.orders set payment_flag='paid_after_cancel' where id=o.id;
      perform private.raise_finance_alert('paid_after_cancel','critical',o.supplier_id,o.id,null,'تم تحصيل دفعة لطلب ملغى — يلزم الاسترجاع',
        jsonb_build_object('charge_id',p_charge_id),'pac:'||p_charge_id);
      v_outcome := 'paid_after_cancel_flagged';
    elsif upper(coalesce(p_currency,'')) <> 'SAR' or p_amount_halalas is distinct from o.payable_halalas then
      update private.gateway_charges set status='amount_mismatch', updated_at=now() where charge_id=p_charge_id;
      update public.orders set payment_flag='amount_mismatch' where id=o.id;
      perform private.raise_finance_alert('amount_mismatch','critical',o.supplier_id,o.id,null,'مبلغ الدفعة لا يطابق إجمالي الطلب — لم يُعتمد الدفع',
        jsonb_build_object('charge_id',p_charge_id,'charged',p_amount_halalas,'expected',o.payable_halalas,'currency',p_currency),'mis:'||p_charge_id);
      v_outcome := 'amount_mismatch_flagged';
    else
      insert into private.order_payments(order_id, reference, amount_halalas, verified_by, verified_at, gateway)
      values (o.id, p_charge_id, p_amount_halalas, null, now(), p_provider||'_supplier');
      update private.gateway_charges set status='captured', updated_at=now() where charge_id=p_charge_id;
      update public.orders set payment_status='paid', paid_at=now() where id=o.id;
      v_outcome := 'paid';
    end if;
  elsif upper(p_provider_status) in ('FAILED','DECLINED','CANCELLED','ABANDONED','TIMEDOUT','RESTRICTED','VOID','UNKNOWN') then
    update private.gateway_charges set status=case when upper(p_provider_status) in ('CANCELLED','ABANDONED','VOID') then 'cancelled' else 'failed' end, updated_at=now()
      where charge_id=p_charge_id and status='initiated';
    v_outcome := 'not_paid';
  else
    v_outcome := 'pending';
  end if;
  insert into private.payment_events(provider,event_key,charge_id,order_id,provider_status,amount_halalas,outcome)
  values (p_provider,v_key,p_charge_id,o.id,p_provider_status,p_amount_halalas,v_outcome);
  return v_outcome;
end $$;

-- Refund result (from the refund API response or the refund webhook). Commission is
-- reversed once, when the refund first succeeds.
create or replace function private.svc_record_refund(p_order uuid, p_refund_id text, p_charge_id text, p_amount bigint, p_status text, p_reason text, p_requested_by uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.orders; r public.order_refunds; v_prev text; v_total_refunded bigint;
begin
  if p_status not in ('pending','succeeded','failed') then raise exception 'invalid refund status'; end if;
  select * into o from public.orders where id=p_order for update;
  if not found or o.payment_status <> 'paid' then raise exception 'only paid orders can be refunded'; end if;
  select * into r from public.order_refunds where provider_refund_id=p_refund_id for update;
  v_prev := r.status;
  if r.id is null then
    if p_amount <= 0 or p_amount > o.payable_halalas - o.refunded_halalas then raise exception 'refund exceeds refundable amount'; end if;
    insert into public.order_refunds(order_id, supplier_id, charge_id, provider_refund_id, amount_halalas, reason, status, requested_by, processed_at)
    values (o.id, o.supplier_id, p_charge_id, p_refund_id, p_amount, coalesce(nullif(btrim(p_reason),''),'استرجاع'), p_status, p_requested_by,
      case when p_status<>'pending' then now() end) returning * into r;
  else
    update public.order_refunds set status=p_status, processed_at=case when p_status<>'pending' then now() else processed_at end where id=r.id returning * into r;
  end if;
  if p_status = 'succeeded' and v_prev is distinct from 'succeeded' then
    select coalesce(sum(amount_halalas),0) into v_total_refunded from public.order_refunds where order_id=o.id and status='succeeded';
    update public.orders set refunded_halalas=v_total_refunded,
      refund_status=case when v_total_refunded >= o.payable_halalas then 'full' else 'partial' end where id=o.id;
    update private.gateway_charges set status=case when v_total_refunded >= o.payable_halalas then 'refunded' else 'partially_refunded' end, updated_at=now()
      where charge_id=p_charge_id and status in ('captured','partially_refunded');
    perform private.reverse_commission_for_refund(r.id);
  end if;
  return to_jsonb(r);
end $$;

-- public wrappers: service_role only
create or replace function public.svc_charge_context(p_order uuid, p_user uuid) returns jsonb language sql security definer set search_path='' as $$ select private.svc_charge_context(p_order,p_user) $$;
create or replace function public.svc_order_gateway_secret(p_order uuid) returns jsonb language sql security definer set search_path='' as $$ select private.svc_order_gateway_secret(p_order) $$;
create or replace function public.svc_record_charge_initiated(p_order uuid, p_provider text, p_charge_id text, p_amount bigint, p_mode text, p_user uuid) returns void language sql security definer set search_path='' as $$ select private.svc_record_charge_initiated(p_order,p_provider,p_charge_id,p_amount,p_mode,p_user) $$;
create or replace function public.svc_process_charge(p_provider text, p_charge_id text, p_order uuid, p_provider_status text, p_amount_halalas bigint, p_currency text, p_mode text) returns text language sql security definer set search_path='' as $$ select private.svc_process_charge(p_provider,p_charge_id,p_order,p_provider_status,p_amount_halalas,p_currency,p_mode) $$;
create or replace function public.svc_record_refund(p_order uuid, p_refund_id text, p_charge_id text, p_amount bigint, p_status text, p_reason text, p_requested_by uuid) returns jsonb language sql security definer set search_path='' as $$ select private.svc_record_refund(p_order,p_refund_id,p_charge_id,p_amount,p_status,p_reason,p_requested_by) $$;
revoke all on function public.svc_charge_context(uuid,uuid), public.svc_order_gateway_secret(uuid), public.svc_record_charge_initiated(uuid,text,text,bigint,text,uuid),
  public.svc_process_charge(text,text,uuid,text,bigint,text,text), public.svc_record_refund(uuid,text,text,bigint,text,text,uuid),
  private.svc_charge_context(uuid,uuid), private.svc_order_gateway_secret(uuid), private.svc_record_charge_initiated(uuid,text,text,bigint,text,uuid),
  private.svc_process_charge(text,text,uuid,text,bigint,text,text), private.svc_record_refund(uuid,text,text,bigint,text,text,uuid) from public, anon, authenticated;
grant execute on function public.svc_charge_context(uuid,uuid), public.svc_order_gateway_secret(uuid), public.svc_record_charge_initiated(uuid,text,text,bigint,text,uuid),
  public.svc_process_charge(text,text,uuid,text,bigint,text,text), public.svc_record_refund(uuid,text,text,bigint,text,text,uuid) to service_role;

-- Edge Function helper: is the caller a platform operator (refunds are operator-only)?
create or replace function public.am_i_finance_operator() returns boolean language sql stable security definer set search_path='' as $$ select private.is_platform_operator() $$;
revoke all on function public.am_i_finance_operator() from public, anon; grant execute on function public.am_i_finance_operator() to authenticated;

-- ---------------------------------------------------------------- disputes
create or replace function public.open_order_dispute(p_order uuid, p_reason text) returns uuid
language plpgsql security definer set search_path='' as $$
declare o public.orders; v_id uuid; v_admin boolean := private.is_platform_operator();
begin
  perform private.assert_account_session();
  select * into o from public.orders where id=p_order;
  if not found or (o.customer_id <> auth.uid() and not v_admin) then raise exception 'order not found' using errcode='42501'; end if;
  if o.payment_status <> 'paid' then raise exception 'disputes apply to paid orders only'; end if;
  insert into public.payment_disputes(order_id, supplier_id, opened_by, opened_role, reason)
  values (o.id, o.supplier_id, auth.uid(), case when v_admin then 'admin' else 'customer' end, btrim(p_reason)) returning id into v_id;
  perform private.raise_finance_alert('dispute_opened','warning',o.supplier_id,o.id,null,'نزاع مالي مفتوح على طلب',jsonb_build_object('dispute',v_id),'dsp:'||v_id);
  if o.supplier_id is not null then
    perform private.notify_supplier(o.supplier_id,'dispute','نزاع مفتوح على طلب','تم فتح نزاع مالي على الطلب '||left(o.id::text,8)||'. سيتواصل فريق رواء معك.','order',o.id::text,'dsp:'||v_id);
  end if;
  return v_id;
end $$;

create or replace function public.admin_resolve_dispute(p_dispute uuid, p_status text, p_note text) returns void
language plpgsql security definer set search_path='' as $$
declare d public.payment_disputes;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_status not in ('under_review','resolved_customer','resolved_supplier','closed') then raise exception 'invalid dispute status'; end if;
  update public.payment_disputes set status=p_status, resolution_note=nullif(btrim(p_note),''), updated_at=now(),
    resolved_by=case when p_status<>'under_review' then auth.uid() end, resolved_at=case when p_status<>'under_review' then now() end
  where id=p_dispute returning * into d;
  if not found then raise exception 'dispute not found'; end if;
  perform private.fin_audit('commission', d.order_id::text, 'dispute_'||p_status, null, jsonb_build_object('dispute',p_dispute,'note',p_note));
  if p_status <> 'under_review' then
    update private.finance_alerts set resolved_at=now(), resolved_by=auth.uid(), resolution_note=p_status where dedupe_key='dsp:'||p_dispute;
    perform private.try_accrue_order(d.order_id);   -- accrues if delivered, paid and no other open dispute
  end if;
end $$;
revoke all on function public.open_order_dispute(uuid,text), public.admin_resolve_dispute(uuid,text,text) from public, anon;
grant execute on function public.open_order_dispute(uuid,text), public.admin_resolve_dispute(uuid,text,text) to authenticated;

-- Existing receipt rule, extended: supplier-direct payments are recorded at the VAT-inclusive
-- payable amount; legacy platform payments keep the original rule unchanged. Completion still
-- requires documented receipt (approved delivery + recipient confirmation + video evidence).
create or replace function private.require_paid_receipt() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if new.payment_mode = 'supplier_direct' then
  if tg_op='UPDATE' and old.payment_status='paid' and (new.payment_status<>'paid' or new.paid_at is distinct from old.paid_at) then
   raise exception 'verified payment is immutable'; end if;
  if new.payment_status='paid' and not exists(select 1 from private.order_payments p where p.order_id=new.id and p.verified_at=new.paid_at and p.amount_halalas=new.payable_halalas) then
   raise exception 'verified payment required'; end if;
 else
  if tg_op='UPDATE' and old.payment_status='paid' and (
   new.payment_status<>'paid' or new.paid_at is distinct from old.paid_at or
   new.subtotal_halalas+new.customization_fee_halalas-new.loyalty_discount_halalas+coalesce(new.delivery_halalas,0) <> old.total_halalas+coalesce(old.delivery_halalas,0)
  ) then raise exception 'verified payment is immutable'; end if;
  -- FIX (pre-existing): the legacy Tap webhook records the VAT-inclusive charge (base x 1.15) while
  -- manual admin recording uses the VAT-exclusive base; accept either so card payments are not rejected.
  if new.payment_status='paid' and not exists(select 1 from private.order_payments p where p.order_id=new.id and p.verified_at=new.paid_at
     and p.amount_halalas in (new.subtotal_halalas+new.customization_fee_halalas-new.loyalty_discount_halalas+coalesce(new.delivery_halalas,0),
                              round((new.subtotal_halalas+new.customization_fee_halalas-new.loyalty_discount_halalas+coalesce(new.delivery_halalas,0))*1.15))) then
   raise exception 'verified payment required';
  end if;
 end if;
 if new.status='delivered' then
  if new.payment_status<>'paid' then raise exception 'payment required before delivery completion'; end if;
  if not exists(select 1 from public.deliveries d where d.order_id=new.id and d.status='approved' and d.recipient_confirmed_at is not null and d.reviewed_at is not null and private.delivery_has_video(d.id)) then
   raise exception 'documented receipt required before completion';
  end if;
 end if;
 return new;
end $$;

-- FIX (pre-existing): the legacy Tap webhook wrapper ran with the caller's rights, so
-- service_role could not execute private.record_gateway_payment ("permission denied").
-- Run it as the owner; execution stays restricted to service_role.
create or replace function public.record_gateway_payment(p_order_id uuid, p_reference text, p_gateway text)
returns void language sql security definer set search_path='' as $$
  select private.record_gateway_payment(p_order_id,p_reference,p_gateway) $$;
revoke all on function public.record_gateway_payment(uuid,text,text) from public, anon, authenticated;
grant execute on function public.record_gateway_payment(uuid,text,text) to service_role;

-- Confidentiality: customers see their line prices and VAT, not the supplier's original
-- price, the markup or Rawaa's commission (available to suppliers/operators via RPCs).
revoke select on public.order_items from anon, authenticated;
grant select (id, order_id, product_id, product_name, unit_price_halalas, quantity, line_net_halalas, vat_rate_bp, line_vat_halalas, supplier_id)
  on public.order_items to authenticated;
