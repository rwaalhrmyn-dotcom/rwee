-- Extend service coverage without changing existing supplier authorizations.
alter table public.profiles drop constraint profiles_city_check;
alter table public.profiles add constraint profiles_city_check check(city in ('makkah','madinah','jeddah','taif'));
alter table public.seller_applications drop constraint seller_applications_city_check;
alter table public.seller_applications add constraint seller_applications_city_check check(city in ('makkah','madinah','jeddah','taif'));
alter table public.orders drop constraint orders_city_check;
alter table public.orders add constraint orders_city_check check(city in ('makkah','madinah','jeddah','taif'));
alter table public.quote_requests drop constraint quote_requests_city_check;
alter table public.quote_requests add constraint quote_requests_city_check check(city in ('makkah','madinah','jeddah','taif'));
alter table public.subscription_requests drop constraint subscription_requests_city_check;
alter table public.subscription_requests add constraint subscription_requests_city_check check(city in ('makkah','madinah','jeddah','taif'));
alter table public.facility_needs drop constraint facility_needs_city_check;
alter table public.facility_needs add constraint facility_needs_city_check check(city in ('makkah','madinah','jeddah','taif'));
alter table public.products drop constraint products_cities_check;
alter table public.products add constraint products_cities_check check(cities <@ array['makkah','madinah','jeddah','taif']::text[] and cardinality(cities)>0);
alter table public.suppliers drop constraint suppliers_cities_check;
alter table public.suppliers add constraint suppliers_cities_check check(cities <@ array['makkah','madinah','jeddah','taif']::text[] and cardinality(cities)>0);

create or replace function private.place_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_line jsonb; v_product public.products%rowtype; v_quantity integer; v_total bigint:=0; v_seen uuid[]:=array[]::uuid[];
begin
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

create or replace function private.supplier_save_product(p_product_id uuid,p_supplier_id uuid,p_data jsonb,p_expected_version integer) returns public.products
language plpgsql security definer set search_path='' as $$
declare v_product public.products%rowtype;v_supplier public.suppliers%rowtype;v_name text;v_unit text;v_description text;v_category text;v_price integer;v_stock integer;v_cities text[];v_active boolean;
begin
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
