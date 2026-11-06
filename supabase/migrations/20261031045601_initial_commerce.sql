-- Commercial marketplace. No donation balances, fundraising or public evidence.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null check (length(full_name) between 2 and 100),
 phone text not null check (length(phone) between 9 and 20),
 city text not null check (city in ('makkah','madinah')),
 created_at timestamptz not null default now()
);
create table public.suppliers (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id),
 name text not null check(length(name) between 2 and 160),
 cities text[] not null check(cities <@ array['makkah','madinah']::text[] and cardinality(cities)>0),
 approval_status text not null default 'pending' check(approval_status in ('pending','approved','blocked')),
 created_at timestamptz not null default now()
);
create index suppliers_owner_idx on public.suppliers(owner_id);
create table public.products (
 id uuid primary key default gen_random_uuid(),
 name text not null check (length(name) between 2 and 160),
 description text not null default '',
 category text not null check (category in ('water','quran','supplies','food','equipment')),
 price_halalas integer not null check (price_halalas > 0),
 stock integer not null default 0 check (stock >= 0),
 unit text not null,
 cities text[] not null default array['makkah','madinah']::text[] check (cities <@ array['makkah','madinah']::text[] and cardinality(cities)>0),
 active boolean not null default false,
 featured boolean not null default false,
 supplier_id uuid references public.suppliers(id),
 check(not active or supplier_id is not null),
 created_at timestamptz not null default now()
);
create index products_supplier_idx on public.products(supplier_id);
create table public.seller_applications (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references auth.users(id),
 business_name text not null check (length(business_name) between 2 and 160),
 commercial_registration text not null check (commercial_registration ~ '^[0-9]{10}$'),
 phone text not null check (length(phone) between 9 and 20),
 city text not null check (city in ('makkah','madinah')),
 category text not null check (category in ('water','quran','supplies','food','equipment')),
 document_path text not null,
 status text not null default 'pending' check (status in ('pending','approved','rejected')),
 created_at timestamptz not null default now()
);
create index seller_applications_owner_idx on public.seller_applications(owner_id);
create table public.orders (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id),
 request_id uuid not null,
 city text not null check (city in ('makkah','madinah')),
 address text not null check (length(address) between 10 and 1000),
 recipient_name text not null check (length(recipient_name) between 2 and 100),
 phone text not null check (length(phone) between 9 and 20),
 subtotal_halalas bigint not null check (subtotal_halalas >= 0),
 delivery_halalas integer check (delivery_halalas >= 0),
 status text not null default 'pending' check (status in ('pending','confirmed','preparing','out_for_delivery','delivered','cancelled')),
 created_at timestamptz not null default now(),
 unique(customer_id,request_id)
);
create index orders_customer_created_idx on public.orders(customer_id,created_at desc);
create table public.order_items (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id) on delete cascade,
 product_id uuid not null references public.products(id),
 product_name text not null,
 unit_price_halalas integer not null check (unit_price_halalas > 0),
 quantity integer not null check (quantity between 1 and 99),
 unique(order_id,product_id)
);
create index order_items_product_idx on public.order_items(product_id);
create table public.quote_requests (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id),
 organization_name text not null check (length(organization_name) between 2 and 160),
 contact_phone text not null check (length(contact_phone) between 9 and 20),
 city text not null check (city in ('makkah','madinah')),
 details text not null check (length(details) between 10 and 3000),
 status text not null default 'pending' check (status in ('pending','contacted','closed')),
 created_at timestamptz not null default now()
);
create index quote_requests_customer_idx on public.quote_requests(customer_id);
create table public.subscription_requests (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id),
 frequency text not null check (frequency in ('weekly','monthly')),
 city text not null check (city in ('makkah','madinah')),
 details text not null check (length(details) between 10 and 2000),
 status text not null default 'requested' check (status in ('requested','contacted','closed')),
 created_at timestamptz not null default now()
);
create index subscription_requests_customer_idx on public.subscription_requests(customer_id);
-- Assignment is an operations action, never a user-editable JWT metadata claim.
create table public.deliveries (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null unique references public.orders(id),
 courier_id uuid not null references auth.users(id),
 reviewer_id uuid not null references auth.users(id),
 status text not null default 'scheduled' check (status in ('scheduled','submitted','approved','changes_requested')),
 recipient_confirmed_at timestamptz,
 reviewed_at timestamptz,
 created_at timestamptz not null default now(),
 check (courier_id <> reviewer_id)
);
create index deliveries_courier_idx on public.deliveries(courier_id);
create index deliveries_reviewer_idx on public.deliveries(reviewer_id);
create table public.delivery_evidence (
 id uuid primary key default gen_random_uuid(),
 delivery_id uuid not null references public.deliveries(id),
 uploaded_by uuid not null references auth.users(id),
 object_path text not null unique,
 created_at timestamptz not null default now()
);
create index delivery_evidence_delivery_idx on public.delivery_evidence(delivery_id);
create index delivery_evidence_uploader_idx on public.delivery_evidence(uploaded_by);

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.suppliers enable row level security;
alter table public.seller_applications enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.quote_requests enable row level security;
alter table public.subscription_requests enable row level security;
alter table public.deliveries enable row level security;
alter table public.delivery_evidence enable row level security;

revoke all on public.profiles,public.products,public.seller_applications,public.orders,public.order_items,public.quote_requests,public.subscription_requests,public.deliveries,public.delivery_evidence from anon,authenticated;
grant select on public.products to anon,authenticated;
revoke all on public.suppliers from anon,authenticated;
grant select(id,name,cities,approval_status,created_at) on public.suppliers to anon,authenticated;
grant select on public.profiles,public.seller_applications,public.orders,public.order_items,public.quote_requests,public.subscription_requests,public.deliveries,public.delivery_evidence to authenticated;
grant insert(id,full_name,phone,city),update(full_name,phone,city) on public.profiles to authenticated;
grant insert(owner_id,business_name,commercial_registration,phone,city,category,document_path) on public.seller_applications to authenticated;
grant insert(customer_id,organization_name,contact_phone,city,details) on public.quote_requests to authenticated;
grant insert(customer_id,frequency,city,details) on public.subscription_requests to authenticated;

-- Avoid recursive orders <-> deliveries RLS. The only definer helpers are internal,
-- pinned to an empty search path, check auth.uid() and have no anonymous execute.
create function private.can_access_order(p_order_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select (select auth.uid()) is not null and (
 exists(select 1 from public.orders o where o.id=p_order_id and o.customer_id=(select auth.uid()))
 or exists(select 1 from public.deliveries d where d.order_id=p_order_id and (d.courier_id=(select auth.uid()) or d.reviewer_id=(select auth.uid())))
 )
$$;
create policy suppliers_visible on public.suppliers for select to anon,authenticated using(approval_status='approved');
create policy products_visible on public.products for select to anon,authenticated using(active and exists(select 1 from public.suppliers s where s.id=supplier_id and s.approval_status='approved'));
create policy profiles_read on public.profiles for select to authenticated using(id=(select auth.uid()));
create policy profiles_create on public.profiles for insert to authenticated with check(id=(select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated using(id=(select auth.uid())) with check(id=(select auth.uid()));
create policy seller_read on public.seller_applications for select to authenticated using(owner_id=(select auth.uid()));
create policy seller_create on public.seller_applications for insert to authenticated with check(owner_id=(select auth.uid()) and status='pending' and (storage.foldername(document_path))[1]=(select auth.uid())::text);
create policy order_read on public.orders for select to authenticated using(private.can_access_order(id));
create policy order_item_read on public.order_items for select to authenticated using(private.can_access_order(order_id));
create policy quote_read on public.quote_requests for select to authenticated using(customer_id=(select auth.uid()));
create policy quote_create on public.quote_requests for insert to authenticated with check(customer_id=(select auth.uid()) and status='pending');
create policy subscription_read on public.subscription_requests for select to authenticated using(customer_id=(select auth.uid()));
create policy subscription_create on public.subscription_requests for insert to authenticated with check(customer_id=(select auth.uid()) and status='requested');
create policy delivery_read on public.deliveries for select to authenticated using(private.can_access_order(order_id));
create policy evidence_read on public.delivery_evidence for select to authenticated using(exists(select 1 from public.deliveries d where d.id=delivery_id));

create function private.place_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_line jsonb; v_product public.products%rowtype; v_quantity integer; v_total bigint:=0; v_seen uuid[]:=array[]::uuid[];
begin
 if v_user is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 if p_request_id is null then raise exception 'request id required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||p_request_id::text,0));
 select id into v_id from public.orders where customer_id=v_user and request_id=p_request_id;
 if v_id is not null then return v_id; end if;
 if p_city is null or p_city not in ('makkah','madinah') or p_address is null or length(p_address) not between 10 and 1000 or p_recipient_name is null or length(p_recipient_name) not between 2 and 100 or p_phone is null or p_phone !~ '^[+0-9 ()-]{9,20}$' then raise exception 'invalid delivery details'; end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'invalid items'; end if;
 if jsonb_array_length(p_items) not between 1 and 30 then raise exception 'invalid item count'; end if;
 v_id:=gen_random_uuid();
 insert into public.orders(id,customer_id,request_id,city,address,recipient_name,phone,subtotal_halalas) values(v_id,v_user,p_request_id,p_city,p_address,p_recipient_name,p_phone,0);
 -- Lock in stable product order to prevent deadlocks across concurrent baskets.
 for v_line in select value from jsonb_array_elements(p_items) order by value->>'product_id' loop
  if jsonb_typeof(v_line->'quantity')<>'number' or (v_line->>'quantity') !~ '^[0-9]{1,2}$' then raise exception 'invalid quantity'; end if;
  v_quantity:=(v_line->>'quantity')::integer;
  if v_quantity is null or v_quantity not between 1 and 99 then raise exception 'invalid quantity'; end if;
  if (v_line->>'product_id')::uuid=any(v_seen) then raise exception 'duplicate product'; end if;
  select * into v_product from public.products where id=(v_line->>'product_id')::uuid for update;
  if not found or not v_product.active or not(p_city=any(v_product.cities)) then raise exception 'unavailable product'; end if;
  if not exists(select 1 from public.suppliers s where s.id=v_product.supplier_id and s.approval_status='approved' and p_city=any(s.cities)) then raise exception 'supplier unavailable'; end if;
  if v_product.stock<v_quantity then raise exception 'insufficient stock'; end if;
  v_seen:=array_append(v_seen,v_product.id);
  update public.products set stock=stock-v_quantity where id=v_product.id;
  v_total:=v_total+v_product.price_halalas::bigint*v_quantity;
  insert into public.order_items(order_id,product_id,product_name,unit_price_halalas,quantity) values(v_id,v_product.id,v_product.name,v_product.price_halalas,v_quantity);
 end loop;
 update public.orders set subtotal_halalas=v_total where id=v_id;
 return v_id;
end $$;
create function public.place_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid) returns uuid
language sql security invoker set search_path='' as $$ select private.place_order(p_items,p_city,p_address,p_recipient_name,p_phone,p_request_id) $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('delivery-evidence','delivery-evidence',false,52428800,array['video/mp4','video/webm']),
 ('seller-documents','seller-documents',false,10485760,array['application/pdf','image/jpeg','image/png'])
on conflict(id) do nothing;
create policy seller_doc_upload on storage.objects for insert to authenticated with check(bucket_id='seller-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy seller_doc_read on storage.objects for select to authenticated using(bucket_id='seller-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy evidence_upload on storage.objects for insert to authenticated with check(bucket_id='delivery-evidence' and exists(select 1 from public.deliveries d where d.order_id::text=(storage.foldername(name))[1] and d.courier_id=(select auth.uid()) and d.status in ('scheduled','submitted','changes_requested')));
create policy evidence_file_read on storage.objects for select to authenticated using(bucket_id='delivery-evidence' and exists(select 1 from public.delivery_evidence e where e.object_path=name));

create function private.submit_delivery_evidence(p_delivery_id uuid,p_object_path text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_delivery public.deliveries%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found or v_delivery.courier_id<>auth.uid() or v_delivery.status='approved' then raise exception 'permission denied' using errcode='42501'; end if;
 if split_part(p_object_path,'/',1)<>v_delivery.order_id::text or not exists(select 1 from storage.objects where bucket_id='delivery-evidence' and name=p_object_path and owner_id=auth.uid()::text) then raise exception 'invalid evidence object'; end if;
 insert into public.delivery_evidence(delivery_id,uploaded_by,object_path) values(p_delivery_id,auth.uid(),p_object_path) returning id into v_id;
 update public.deliveries set status='submitted',recipient_confirmed_at=null,reviewed_at=null where id=p_delivery_id;
 return v_id;
end $$;
create function public.submit_delivery_evidence(p_delivery_id uuid,p_object_path text) returns uuid
language sql security invoker set search_path='' as $$ select private.submit_delivery_evidence(p_delivery_id,p_object_path) $$;
create function private.confirm_delivery_receipt(p_delivery_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_delivery public.deliveries%rowtype;
begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found or v_delivery.status<>'submitted' or not exists(select 1 from public.orders o where o.id=v_delivery.order_id and o.customer_id=auth.uid()) then raise exception 'permission denied' using errcode='42501'; end if;
 update public.deliveries set recipient_confirmed_at=now() where id=p_delivery_id;
end $$;
create function public.confirm_delivery_receipt(p_delivery_id uuid) returns void
language sql security invoker set search_path='' as $$ select private.confirm_delivery_receipt(p_delivery_id) $$;
create function private.review_delivery(p_delivery_id uuid,p_decision text) returns void
language plpgsql security definer set search_path='' as $$
declare v_delivery public.deliveries%rowtype;
begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found or v_delivery.reviewer_id<>auth.uid() or v_delivery.courier_id=auth.uid() or v_delivery.status<>'submitted' then raise exception 'permission denied' using errcode='42501'; end if;
 if p_decision is null or p_decision not in ('approved','changes_requested') then raise exception 'invalid decision'; end if;
 if p_decision='approved' and v_delivery.recipient_confirmed_at is null then raise exception 'recipient confirmation required'; end if;
 update public.deliveries set status=p_decision,reviewed_at=now() where id=p_delivery_id;
 if p_decision='approved' then update public.orders set status='delivered' where id=v_delivery.order_id; end if;
end $$;
create function public.review_delivery(p_delivery_id uuid,p_decision text) returns void
language sql security invoker set search_path='' as $$ select private.review_delivery(p_delivery_id,p_decision) $$;

revoke all on function private.can_access_order(uuid),private.place_order(jsonb,text,text,text,text,uuid),private.submit_delivery_evidence(uuid,text),private.confirm_delivery_receipt(uuid),private.review_delivery(uuid,text) from public,anon;
grant execute on function private.can_access_order(uuid),private.place_order(jsonb,text,text,text,text,uuid),private.submit_delivery_evidence(uuid,text),private.confirm_delivery_receipt(uuid),private.review_delivery(uuid,text) to authenticated;
revoke all on function public.place_order(jsonb,text,text,text,text,uuid),public.submit_delivery_evidence(uuid,text),public.confirm_delivery_receipt(uuid),public.review_delivery(uuid,text) from public,anon;
grant execute on function public.place_order(jsonb,text,text,text,text,uuid),public.submit_delivery_evidence(uuid,text),public.confirm_delivery_receipt(uuid),public.review_delivery(uuid,text) to authenticated;
