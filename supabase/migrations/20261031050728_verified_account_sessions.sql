-- Authoritative account/session checks for reads, writes and privileged RPCs.
-- Client metadata never grants privileges; existing role tables remain authoritative.
create function private.has_verified_session() returns boolean
language sql stable security definer set search_path='' as $$
 select (select auth.uid()) is not null and exists(
  select 1 from auth.users u join auth.sessions s on s.user_id=u.id
  where u.id=(select auth.uid()) and u.email_confirmed_at is not null
   and not coalesce(u.is_anonymous,false) and u.deleted_at is null
   and (u.banned_until is null or u.banned_until<=now())
   and s.id=case when (auth.jwt()->>'session_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then (auth.jwt()->>'session_id')::uuid else null end
 )
$$;
create function private.assert_account_session() returns void
language plpgsql stable security definer set search_path='' as $$begin
 if not private.has_verified_session() then raise exception 'authenticated verified session required' using errcode='42501'; end if;
end $$;
revoke all on function private.has_verified_session(),private.assert_account_session() from public,anon;
grant execute on function private.has_verified_session(),private.assert_account_session() to authenticated;

create or replace function private.place_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_line jsonb; v_product public.products%rowtype; v_quantity integer; v_total bigint:=0; v_seen uuid[]:=array[]::uuid[];
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

create or replace function private.submit_delivery_evidence(p_delivery_id uuid,p_object_path text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_delivery public.deliveries%rowtype; v_id uuid;
begin
 perform private.assert_account_session();
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found or v_delivery.courier_id<>auth.uid() or v_delivery.status='approved' then raise exception 'permission denied' using errcode='42501'; end if;
 if not exists(select 1 from public.orders where id=v_delivery.order_id and payment_status='paid' and status<>'cancelled') then raise exception 'verified payment required'; end if;
 if p_object_path is null or p_object_path !~ '[.](mp4|webm)$' or split_part(p_object_path,'/',1)<>v_delivery.order_id::text or not exists(select 1 from storage.objects where bucket_id='delivery-evidence' and name=p_object_path and owner_id=auth.uid()::text) then raise exception 'invalid evidence object'; end if;
 insert into public.delivery_evidence(delivery_id,uploaded_by,object_path) values(p_delivery_id,auth.uid(),p_object_path) returning id into v_id;
 update public.deliveries set status='submitted',recipient_confirmed_at=null,reviewed_at=null where id=p_delivery_id;
 return v_id;
end $$;

create or replace function private.confirm_delivery_receipt(p_delivery_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_delivery public.deliveries%rowtype;
begin
 perform private.assert_account_session();
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found or v_delivery.status<>'submitted' or not exists(select 1 from public.orders o where o.id=v_delivery.order_id and o.customer_id=auth.uid()) then raise exception 'permission denied' using errcode='42501'; end if;
 if not exists(select 1 from public.orders where id=v_delivery.order_id and payment_status='paid' and status<>'cancelled') then raise exception 'verified payment required'; end if;
 if not private.delivery_has_video(p_delivery_id) then raise exception 'delivery video required'; end if;
 update public.deliveries set recipient_confirmed_at=coalesce(recipient_confirmed_at,now()) where id=p_delivery_id;
end $$;

create or replace function private.review_delivery(p_delivery_id uuid,p_decision text) returns void
language plpgsql security definer set search_path='' as $$
declare v_delivery public.deliveries%rowtype;
begin
 perform private.assert_account_session();
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found or v_delivery.reviewer_id<>auth.uid() or v_delivery.courier_id=auth.uid() or v_delivery.status<>'submitted' then raise exception 'permission denied' using errcode='42501'; end if;
 if p_decision is null or p_decision not in ('approved','changes_requested') then raise exception 'invalid decision'; end if;
 if not exists(select 1 from public.orders where id=v_delivery.order_id and payment_status='paid' and status<>'cancelled') then raise exception 'verified payment required'; end if;
 if not private.delivery_has_video(p_delivery_id) then raise exception 'delivery video required'; end if;
 if p_decision='approved' and v_delivery.recipient_confirmed_at is null then raise exception 'recipient confirmation required'; end if;
 update public.deliveries set status=p_decision,reviewed_at=now() where id=p_delivery_id;
 if p_decision='approved' then update public.orders set status='delivered' where id=v_delivery.order_id; end if;
end $$;

create or replace function private.place_customized_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid,p_customization jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_id uuid;v_intent text;v_name text;v_print boolean;v_phrase text;v_custom text;v_language text;v_fee integer:=0;
begin
 perform private.assert_account_session();
 if v_user is null then raise exception 'authenticated user required' using errcode='42501';end if;
 if p_request_id is null then raise exception 'request id required';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||p_request_id::text,0));
 select id into v_id from public.orders where customer_id=v_user and request_id=p_request_id;
 if v_id is not null then return v_id;end if;
 if p_customization is null or jsonb_typeof(p_customization)<>'object' then raise exception 'invalid customization';end if;
 v_intent:=coalesce(p_customization->>'intent','standard');
 if v_intent not in ('standard','sadaqah') then raise exception 'invalid order intent';end if;
 if p_customization ? 'print_name' and jsonb_typeof(p_customization->'print_name')<>'boolean' then raise exception 'invalid print option';end if;
 v_print:=coalesce((p_customization->>'print_name')::boolean,false);
 if p_customization ? 'beneficiary_name' and jsonb_typeof(p_customization->'beneficiary_name') not in ('string','null') then raise exception 'invalid beneficiary name';end if;
 v_name:=nullif(btrim(p_customization->>'beneficiary_name'),'');
 if length(v_name)>100 then raise exception 'beneficiary name too long';end if;
 if v_intent='standard' then
  if v_print then raise exception 'printing requires sadaqah purchase';end if;
  v_name:=null;
 end if;
 if v_print then
  if v_name is null then raise exception 'beneficiary name required for printing';end if;
  v_phrase:=p_customization->>'phrase_key';v_language:=p_customization->>'print_language';
  if v_phrase is null or v_phrase not in ('on_behalf','prayer','gift','custom') then raise exception 'invalid print phrase';end if;
  if v_language is null or v_language not in ('ar','en','ur','id') then raise exception 'invalid print language';end if;
  if v_phrase='custom' then
   if jsonb_typeof(p_customization->'custom_phrase')<>'string' then raise exception 'invalid custom phrase';end if;
   v_custom:=nullif(btrim(p_customization->>'custom_phrase'),'');
   if v_custom is null or length(v_custom)>160 then raise exception 'custom phrase required (1-160 characters)';end if;
  end if;
  select price_halalas into v_fee from public.checkout_services where code='name_printing' and active for share;
  if not found then raise exception 'printing service unavailable';end if;
 end if;
 v_id:=private.place_order(p_items,p_city,p_address,p_recipient_name,p_phone,p_request_id);
 update public.orders set intent=v_intent,beneficiary_name=v_name,print_name=v_print,print_phrase_key=v_phrase,print_custom_phrase=v_custom,print_language=v_language,customization_fee_halalas=v_fee where id=v_id;
 return v_id;
end $$;

create or replace function private.supplier_products() returns setof public.products language plpgsql stable security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 return query select p.* from public.products p join public.suppliers s on s.id=p.supplier_id
 where s.owner_id=auth.uid() and s.approval_status='approved' and not p.archived order by p.created_at desc;
end $$;

create or replace function private.supplier_order_summaries() returns table(id uuid,created_at timestamptz,status text,city text,item_total_halalas bigint,quantity bigint,print_name boolean,beneficiary_name text)
language plpgsql stable security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 return query select o.id,o.created_at,o.status,o.city,sum(i.unit_price_halalas::bigint*i.quantity)::bigint,sum(i.quantity)::bigint,o.print_name,case when o.print_name then o.beneficiary_name else null end
 from public.orders o join public.order_items i on i.order_id=o.id join public.products p on p.id=i.product_id join public.suppliers s on s.id=p.supplier_id
 where s.owner_id=auth.uid() and s.approval_status='approved'
 group by o.id order by o.created_at desc;
end$$;

create or replace function private.set_printing_service_price(p_price_halalas integer) returns void language plpgsql security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501';end if;
 if p_price_halalas is null or p_price_halalas not between 0 and 100000 then raise exception 'invalid printing price';end if;
 update public.checkout_services set price_halalas=p_price_halalas where code='name_printing';
end$$;

create or replace function private.loyalty_wallet() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_wallet jsonb;
begin
 perform private.assert_account_session();
 if v_user is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select jsonb_build_object('balance',a.balance,'lifetime',a.lifetime) into v_wallet from private.loyalty_accounts a where a.customer_id=v_user;
 return coalesce(v_wallet,jsonb_build_object('balance',0,'lifetime',0)) || jsonb_build_object('transactions',coalesce((
  select jsonb_agg(row_to_json(x) order by x.created_at desc,x.id desc) from (
   select id,order_id,kind,points,created_at from private.loyalty_transactions where customer_id=v_user order by created_at desc,id desc limit 20
  ) x
 ),'[]'::jsonb));
end $$;

create or replace function private.set_loyalty_enabled(p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform private.assert_account_session();
 if auth.uid() is null or not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501'; end if;
 if p_enabled is null then raise exception 'enabled is required'; end if;
 update public.loyalty_settings set enabled=p_enabled where id;
end $$;

create or replace function private.place_loyalty_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid,p_customization jsonb,p_loyalty_points integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_subtotal bigint; v_balance bigint; v_enabled boolean;
begin
 perform private.assert_account_session();
 if v_user is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 if p_request_id is null then raise exception 'request id required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||p_request_id::text,0));
 select id into v_id from public.orders where customer_id=v_user and request_id=p_request_id;
 if v_id is not null then return v_id; end if;
 if p_loyalty_points is null or p_loyalty_points not in (0,100,300,500) then raise exception 'invalid loyalty reward'; end if;
 select enabled into v_enabled from public.loyalty_settings where id for share;
 if p_loyalty_points>0 and not coalesce(v_enabled,false) then raise exception 'loyalty program paused'; end if;
 v_id := private.place_customized_order(p_items,p_city,p_address,p_recipient_name,p_phone,p_request_id,p_customization);
 if p_loyalty_points>0 then
  select subtotal_halalas into v_subtotal from public.orders where id=v_id;
  if p_loyalty_points::bigint*5*4>v_subtotal then raise exception 'loyalty discount exceeds product limit'; end if;
  insert into private.loyalty_accounts(customer_id) values(v_user) on conflict do nothing;
  select balance into v_balance from private.loyalty_accounts where customer_id=v_user for update;
  if v_balance<p_loyalty_points then raise exception 'insufficient loyalty points'; end if;
  update private.loyalty_accounts set balance=balance-p_loyalty_points where customer_id=v_user;
  insert into private.loyalty_transactions(customer_id,order_id,kind,points) values(v_user,v_id,'redeem',-p_loyalty_points);
  update public.orders set loyalty_discount_halalas=p_loyalty_points::bigint*5 where id=v_id;
 end if;
 return v_id;
end $$;

create or replace function private.record_verified_payment(p_order_id uuid,p_reference text) returns void
language plpgsql security definer set search_path='' as $$
declare v_order public.orders%rowtype; v_reference text:=btrim(p_reference); v_time timestamptz:=now(); v_existing text;
begin
 perform private.assert_account_session();
 if auth.uid() is null or not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501'; end if;
 if v_reference is null or length(v_reference) not between 6 and 160 then raise exception 'invalid payment reference'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found or v_order.status='cancelled' then raise exception 'order unavailable for payment confirmation'; end if;
 select reference into v_existing from private.order_payments where order_id=p_order_id;
 if v_existing is not null then
  if v_existing=v_reference then return; end if;
  raise exception 'payment already recorded';
 end if;
 insert into private.order_payments(order_id,reference,amount_halalas,verified_by,verified_at)
 values(p_order_id,v_reference,v_order.total_halalas+coalesce(v_order.delivery_halalas,0),auth.uid(),v_time);
 update public.orders set payment_status='paid',paid_at=v_time where id=p_order_id;
end $$;

create or replace function private.my_supplier_accounts() returns table(id uuid,name text,cities text[])
language plpgsql stable security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 return query select s.id,s.name,s.cities from public.suppliers s where s.owner_id=auth.uid() and s.approval_status='approved' order by s.created_at;
end $$;

create or replace function private.supplier_save_product(p_product_id uuid,p_supplier_id uuid,p_data jsonb,p_expected_version integer) returns public.products
language plpgsql security definer set search_path='' as $$
declare v_product public.products%rowtype;v_supplier public.suppliers%rowtype;v_name text;v_unit text;v_description text;v_category text;v_price integer;v_stock integer;v_cities text[];v_active boolean;
begin
 perform private.assert_account_session();
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 if p_product_id is not null then
  select * into v_product from public.products where id=p_product_id for update;
  if not found or not private.owns_supplier(v_product.supplier_id) or v_product.archived or v_product.supplier_id<>p_supplier_id then raise exception 'permission denied' using errcode='42501';end if;
  if p_expected_version is null or v_product.inventory_version<>p_expected_version then raise exception 'inventory changed; reload before saving' using errcode='40001';end if;
 end if;
 select * into v_supplier from public.suppliers where id=p_supplier_id and owner_id=auth.uid() and approval_status='approved' for share;
 if not found then raise exception 'permission denied' using errcode='42501';end if;
 if p_data is null or jsonb_typeof(p_data)<>'object' then raise exception 'invalid product data';end if;
 if jsonb_typeof(p_data->'name') is distinct from 'string' or jsonb_typeof(p_data->'description') is distinct from 'string' or jsonb_typeof(p_data->'unit') is distinct from 'string' or jsonb_typeof(p_data->'category') is distinct from 'string' then raise exception 'invalid product data';end if;
 v_name:=btrim(p_data->>'name');v_unit:=btrim(p_data->>'unit');v_description:=btrim(p_data->>'description');v_category:=p_data->>'category';
 if length(v_name) not between 2 and 160 or length(v_unit) not between 1 and 40 or length(v_description)>2000 or v_category not in ('water','quran','supplies','food','equipment') then raise exception 'invalid product data';end if;
 if jsonb_typeof(p_data->'price_halalas') is distinct from 'number' or coalesce(p_data->>'price_halalas','') !~ '^[0-9]{1,9}$' or jsonb_typeof(p_data->'stock') is distinct from 'number' or coalesce(p_data->>'stock','') !~ '^[0-9]{1,7}$' then raise exception 'invalid product price or stock';end if;
 v_price:=(p_data->>'price_halalas')::integer;v_stock:=(p_data->>'stock')::integer;
 if v_price not between 1 and 100000000 or v_stock not between 0 and 1000000 then raise exception 'invalid product price or stock';end if;
 if jsonb_typeof(p_data->'cities') is distinct from 'array' or jsonb_typeof(p_data->'active') is distinct from 'boolean' then raise exception 'invalid product cities or visibility';end if;
 select array_agg(value) into v_cities from jsonb_array_elements_text(p_data->'cities');
 if coalesce(cardinality(v_cities),0) not between 1 and 4 or not(v_cities <@ v_supplier.cities) or cardinality(v_cities)<>(select count(distinct x) from unnest(v_cities) x) then raise exception 'invalid product cities';end if;
 v_active:=(p_data->>'active')::boolean;
 if p_product_id is null then
  insert into public.products(name,description,category,price_halalas,stock,unit,cities,active,supplier_id)
  values(v_name,v_description,v_category,v_price,v_stock,v_unit,v_cities,v_active,p_supplier_id) returning * into v_product;
 else
  update public.products set name=v_name,description=v_description,category=v_category,price_halalas=v_price,stock=v_stock,unit=v_unit,cities=v_cities,active=v_active where id=p_product_id returning * into v_product;
 end if;
 return v_product;
end $$;

create or replace function private.supplier_adjust_stock(p_product_id uuid,p_delta integer,p_expected_version integer) returns public.products
language plpgsql security definer set search_path='' as $$
declare v_product public.products%rowtype;
begin
 perform private.assert_account_session();
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 select * into v_product from public.products where id=p_product_id for update;
 if not found or not private.owns_supplier(v_product.supplier_id) or v_product.archived then raise exception 'permission denied' using errcode='42501';end if;
 if p_expected_version is null or v_product.inventory_version<>p_expected_version then raise exception 'inventory changed; reload before saving' using errcode='40001';end if;
 if p_delta is null or p_delta=0 or p_delta not between -1000000 and 1000000 or v_product.stock+p_delta not between 0 and 1000000 then raise exception 'invalid stock adjustment';end if;
 update public.products set stock=stock+p_delta where id=p_product_id returning * into v_product;
 return v_product;
end $$;

create or replace function private.supplier_archive_product(p_product_id uuid,p_expected_version integer) returns void
language plpgsql security definer set search_path='' as $$
declare v_product public.products%rowtype;
begin
 perform private.assert_account_session();
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 select * into v_product from public.products where id=p_product_id for update;
 if not found or not private.owns_supplier(v_product.supplier_id) or v_product.archived then raise exception 'permission denied' using errcode='42501';end if;
 if p_expected_version is null or v_product.inventory_version<>p_expected_version then raise exception 'inventory changed; reload before saving' using errcode='40001';end if;
 update public.products set active=false,archived=true where id=p_product_id;
end $$;

create or replace function private.supplier_import_products(p_supplier_id uuid,p_rows jsonb,p_request_id uuid) returns uuid[]
language plpgsql security definer set search_path='' as $$
declare v_ids uuid[];v_row jsonb;v_product public.products%rowtype;v_supplier uuid;
begin
 perform private.assert_account_session();
 if auth.uid() is null or not private.owns_supplier(p_supplier_id) then raise exception 'permission denied' using errcode='42501';end if;
 if p_request_id is null then raise exception 'import request required';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||p_request_id::text,0));
 select supplier_id,product_ids into v_supplier,v_ids from private.inventory_imports where user_id=auth.uid() and request_id=p_request_id;
 if found then
  if v_supplier<>p_supplier_id then raise exception 'invalid import request';end if;
  return v_ids;
 end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows) not between 1 and 200 then raise exception 'invalid import rows';end if;
 v_ids:=array[]::uuid[];
 for v_row in select value from jsonb_array_elements(p_rows) loop
  v_product:=private.supplier_save_product(null,p_supplier_id,v_row,null);v_ids:=array_append(v_ids,v_product.id);
 end loop;
 insert into private.inventory_imports(user_id,request_id,supplier_id,product_ids) values(auth.uid(),p_request_id,p_supplier_id,v_ids);
 return v_ids;
end $$;

create or replace function private.is_platform_operator() returns boolean language sql stable security definer set search_path='' as $$select private.has_verified_session() and exists(select 1 from private.platform_operators where user_id=auth.uid())$$;

create or replace function private.owns_supplier(p_supplier_id uuid) returns boolean language sql stable security definer set search_path='' as $$select private.has_verified_session() and exists(select 1 from public.suppliers where id=p_supplier_id and owner_id=auth.uid() and approval_status='approved')$$;

create or replace function private.can_access_order(p_order_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select private.has_verified_session() and (
 exists(select 1 from public.orders o where o.id=p_order_id and o.customer_id=(select auth.uid()))
 or exists(select 1 from public.deliveries d where d.order_id=p_order_id and (d.courier_id=(select auth.uid()) or d.reviewer_id=(select auth.uid())))
 )
$$;

create or replace function private.portal_access() returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('is_authenticated',private.has_verified_session(),'is_admin',private.is_platform_operator(),'is_supplier',private.has_verified_session() and exists(select 1 from public.suppliers where owner_id=auth.uid() and approval_status='approved'))$$;

create policy verified_account_access on public.profiles as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.products as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.suppliers as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.seller_applications as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.orders as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.order_items as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.quote_requests as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.subscription_requests as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.deliveries as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.delivery_evidence as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.facility_needs as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.checkout_services as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_access on public.loyalty_settings as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));

create policy verified_account_storage on storage.objects as restrictive for all to authenticated using((select private.has_verified_session())) with check((select private.has_verified_session()));
