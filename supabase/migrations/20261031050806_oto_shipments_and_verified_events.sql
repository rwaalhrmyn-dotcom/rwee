-- OTO is a transport integration. Carrier delivery never completes a Riwa receipt.
create table public.shipments (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id),
 supplier_id uuid not null references public.suppliers(id),
 provider_order_id text not null unique,
 pickup_code text not null check(length(pickup_code) between 1 and 80),
 package_weight numeric not null check(package_weight between 0.01 and 1000),
 package_count integer not null check(package_count between 1 and 99),
 export_state text not null default 'draft' check(export_state in ('draft','exporting','exported','unknown')),
 provider_status text,
 tracking_number text,
 carrier text,
 tracking_url text,
 last_event_at timestamptz,
 last_synced_at timestamptz,
 operation_id uuid,
 operation_kind text,
 operation_started_at timestamptz,
 created_at timestamptz not null default now(),
 unique(order_id,supplier_id)
);
create index shipments_supplier_created_idx on public.shipments(supplier_id,created_at desc);
alter table public.shipments enable row level security;
revoke all on public.shipments from public,anon,authenticated;
grant select(id,order_id,supplier_id,provider_order_id,export_state,provider_status,tracking_number,carrier,tracking_url,last_event_at,last_synced_at,created_at) on public.shipments to authenticated;
create policy shipments_owner_read on public.shipments for select to authenticated using(
 (select private.has_verified_session()) and (
 (select private.is_platform_operator()) or private.owns_supplier(supplier_id) or
 exists(select 1 from public.orders o where o.id=order_id and o.customer_id=(select auth.uid()))
 ));
create table private.oto_events(
 fingerprint text primary key check(fingerprint ~ '^[0-9a-f]{64}$'),
 shipment_id uuid not null references public.shipments(id),
 event_type text not null,
 event_value text not null,
 event_at timestamptz not null,
 received_at timestamptz not null default now()
);
alter table private.oto_events enable row level security;
revoke all on private.oto_events from public,anon,authenticated;

create function private.shipping_candidates() returns table(order_id uuid,supplier_id uuid,supplier_name text)
language plpgsql stable security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501';end if;
 return query select distinct o.id,s.id,s.name from public.orders o join public.order_items i on i.order_id=o.id join public.products p on p.id=i.product_id join public.suppliers s on s.id=p.supplier_id
 where o.payment_status='paid' and o.status not in ('cancelled','delivered') and s.approval_status='approved' limit 100;
end$$;
create function public.shipping_candidates() returns table(order_id uuid,supplier_id uuid,supplier_name text)
language sql security invoker set search_path='' as $$select * from private.shipping_candidates()$$;

create function private.prepare_oto_shipment(p_order_id uuid,p_supplier_id uuid,p_pickup_code text,p_package_weight numeric,p_package_count integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_order public.orders%rowtype;v_code text:=btrim(p_pickup_code);
begin
 perform private.assert_account_session();
 if not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501';end if;
 if v_code is null or v_code !~ '^[A-Za-z0-9_-]{1,80}$' or p_package_weight is null or p_package_weight not between 0.01 and 1000 or p_package_count is null or p_package_count not between 1 and 99 then raise exception 'invalid shipping package';end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found or v_order.payment_status<>'paid' or v_order.status in ('cancelled','delivered') then raise exception 'verified payment required';end if;
 if not exists(select 1 from public.order_items i join public.products p on p.id=i.product_id join public.suppliers s on s.id=p.supplier_id where i.order_id=p_order_id and s.id=p_supplier_id and s.approval_status='approved') then raise exception 'supplier not part of order';end if;
 insert into public.shipments(order_id,supplier_id,provider_order_id,pickup_code,package_weight,package_count)
 values(p_order_id,p_supplier_id,'riwa-'||p_order_id::text||'-'||p_supplier_id::text,v_code,p_package_weight,p_package_count)
 on conflict(order_id,supplier_id) do nothing returning id into v_id;
 if v_id is null then select id into v_id from public.shipments where order_id=p_order_id and supplier_id=p_supplier_id;end if;
 return v_id;
end$$;
create function public.prepare_oto_shipment(p_order_id uuid,p_supplier_id uuid,p_pickup_code text,p_package_weight numeric,p_package_count integer) returns uuid
language sql security invoker set search_path='' as $$select private.prepare_oto_shipment(p_order_id,p_supplier_id,p_pickup_code,p_package_weight,p_package_count)$$;

create function private.claim_oto_operation(p_shipment_id uuid,p_action text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.shipments%rowtype;o public.orders%rowtype;v_op uuid:=gen_random_uuid();v_items jsonb;v_amount numeric;v_city text;v_payload jsonb;
begin
 perform private.assert_account_session();
 if p_action is null or p_action not in ('export','refresh') then raise exception 'invalid shipping action';end if;
 -- Always lock order before shipment, matching preparation and avoiding a lock inversion.
 select ord.* into o from public.orders ord join public.shipments sh on sh.order_id=ord.id where sh.id=p_shipment_id for update of ord;
 if not found then raise exception 'permission denied' using errcode='42501';end if;
 select * into s from public.shipments where id=p_shipment_id for update;
 if not(private.is_platform_operator() or private.owns_supplier(s.supplier_id) or o.customer_id=auth.uid()) then raise exception 'permission denied' using errcode='42501';end if;
 if p_action='export' then
  if not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501';end if;
  if o.payment_status<>'paid' or o.status in ('cancelled','delivered') then raise exception 'verified payment required';end if;
  if s.export_state<>'draft' then raise exception 'shipping export already attempted; refresh to reconcile';end if;
 else
  if s.export_state='draft' then raise exception 'shipping export required';end if;
 end if;
 if s.operation_started_at>now()-interval '60 seconds' then raise exception 'shipping rate limited';end if;
 if p_action='export' then
  select jsonb_agg(jsonb_build_object('name',i.product_name,'price',i.unit_price_halalas::numeric/100,'quantity',i.quantity,'sku',i.product_id::text)),sum(i.unit_price_halalas::numeric*i.quantity)/100 into v_items,v_amount
   from public.order_items i join public.products p on p.id=i.product_id where i.order_id=o.id and p.supplier_id=s.supplier_id;
  if v_items is null then raise exception 'supplier not part of order';end if;
  v_city:=case o.city when 'makkah' then 'Makkah' when 'madinah' then 'Madinah' when 'jeddah' then 'Jeddah' when 'taif' then 'Taif' end;
  v_payload:=jsonb_build_object('orderId',s.provider_order_id,'parentOrderId',o.id::text,'pickupLocationCode',s.pickup_code,'createShipment',false,'payment_method','paid','amount',v_amount,'amount_due',0,'currency','SAR','packageWeight',s.package_weight,'packageCount',s.package_count,'customer',jsonb_build_object('name',o.recipient_name,'mobile',o.phone,'address',o.address,'city',v_city,'country','SA'),'items',v_items);
 end if;
 update public.shipments set operation_id=v_op,operation_kind=p_action,operation_started_at=now(),export_state=case when p_action='export' then 'exporting' else export_state end where id=s.id;
 return jsonb_build_object('shipment_id',s.id,'operation_id',v_op,'provider_order_id',s.provider_order_id,'payload',v_payload);
end$$;
create function public.claim_oto_operation(p_shipment_id uuid,p_action text) returns jsonb
language sql security invoker set search_path='' as $$select private.claim_oto_operation(p_shipment_id,p_action)$$;

-- Only the trusted Edge Function may complete a provider operation.
create function private.complete_oto_operation(p_shipment_id uuid,p_operation_id uuid,p_success boolean,p_result jsonb) returns boolean
language plpgsql security definer set search_path='' as $$
declare s public.shipments%rowtype;v_status text;v_tracking text;v_carrier text;v_url text;
begin
 select * into s from public.shipments where id=p_shipment_id for update;
 if not found or p_operation_id is null or s.operation_id is null or s.operation_id is distinct from p_operation_id then return false;end if;
 if p_success is not true then
  update public.shipments set export_state=case when operation_kind='export' then 'unknown' else export_state end,operation_id=null where id=s.id;return false;
 end if;
 if s.operation_kind='refresh' then
  v_status:=p_result->>'status';v_tracking:=nullif(p_result->>'tracking_number','');v_carrier:=nullif(p_result->>'carrier','');v_url:=nullif(p_result->>'tracking_url','');
  if v_status is null or v_status !~ '^[A-Za-z0-9_-]{1,80}$' or length(v_tracking)>160 or length(v_carrier)>100 or (v_url is not null and (length(v_url)>2048 or v_url !~ '^https://app[.]tryoto[.]com/')) then raise exception 'invalid provider result';end if;
  -- A response started before a newer webhook may not replace that webhook's status.
  if s.last_event_at is null or s.last_event_at<=s.operation_started_at then
   update public.shipments set provider_status=v_status,tracking_number=v_tracking,carrier=v_carrier,tracking_url=v_url where id=s.id;
  end if;
 end if;
 update public.shipments set export_state='exported',last_synced_at=now(),operation_id=null where id=s.id;
 return true;
end$$;
create function public.complete_oto_operation(p_shipment_id uuid,p_operation_id uuid,p_success boolean,p_result jsonb) returns boolean
language sql security invoker set search_path='' as $$select private.complete_oto_operation(p_shipment_id,p_operation_id,p_success,p_result)$$;

create function private.ingest_oto_event(p_fingerprint text,p_order_id text,p_event_type text,p_value text,p_event_at timestamptz) returns boolean
language plpgsql security definer set search_path='' as $$
declare s public.shipments%rowtype;v_inserted text;
begin
 if p_fingerprint is null or p_fingerprint !~ '^[0-9a-f]{64}$' or p_event_type is null or p_event_type not in ('orderStatus','shipmentError') or p_value is null or p_value !~ '^[A-Za-z0-9_-]{1,80}$' or p_event_at is null or p_event_at>now()+interval '5 minutes' then raise exception 'invalid provider event';end if;
 select * into s from public.shipments where provider_order_id=p_order_id for update;
 if not found then return false;end if;
 insert into private.oto_events(fingerprint,shipment_id,event_type,event_value,event_at) values(p_fingerprint,s.id,p_event_type,p_value,p_event_at) on conflict(fingerprint) do nothing returning fingerprint into v_inserted;
 if v_inserted is null or (s.last_event_at is not null and p_event_at<=s.last_event_at) then return false;end if;
 update public.shipments set last_event_at=p_event_at,provider_status=case when p_event_type='shipmentError' then 'shipmentError' else p_value end where id=s.id;
 -- Never update public.orders or deliveries. Evidence and recipient/reviewer approval remain mandatory.
 return true;
end$$;
create function public.ingest_oto_event(p_fingerprint text,p_order_id text,p_event_type text,p_value text,p_event_at timestamptz) returns boolean
language sql security invoker set search_path='' as $$select private.ingest_oto_event(p_fingerprint,p_order_id,p_event_type,p_value,p_event_at)$$;

revoke all on function private.shipping_candidates(),public.shipping_candidates(),private.prepare_oto_shipment(uuid,uuid,text,numeric,integer),public.prepare_oto_shipment(uuid,uuid,text,numeric,integer),private.claim_oto_operation(uuid,text),public.claim_oto_operation(uuid,text) from public,anon;
grant execute on function private.shipping_candidates(),public.shipping_candidates(),private.prepare_oto_shipment(uuid,uuid,text,numeric,integer),public.prepare_oto_shipment(uuid,uuid,text,numeric,integer),private.claim_oto_operation(uuid,text),public.claim_oto_operation(uuid,text) to authenticated;
revoke all on function private.complete_oto_operation(uuid,uuid,boolean,jsonb),public.complete_oto_operation(uuid,uuid,boolean,jsonb),private.ingest_oto_event(text,text,text,text,timestamptz),public.ingest_oto_event(text,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function private.complete_oto_operation(uuid,uuid,boolean,jsonb),public.complete_oto_operation(uuid,uuid,boolean,jsonb),private.ingest_oto_event(text,text,text,text,timestamptz),public.ingest_oto_event(text,text,text,text,timestamptz) to service_role;

grant usage on schema private to service_role;
