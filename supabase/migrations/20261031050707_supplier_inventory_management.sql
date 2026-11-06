-- Supplier-owned product management. Archived rows remain for order history.
alter table public.products add column inventory_version integer not null default 1,
 add column archived boolean not null default false,
 add constraint archived_product_hidden check(not archived or not active);
create function private.bump_inventory_version() returns trigger language plpgsql set search_path='' as $$
begin new.inventory_version:=old.inventory_version+1; return new; end $$;
create trigger bump_inventory_version before update on public.products for each row execute function private.bump_inventory_version();
revoke all on function private.bump_inventory_version() from public,anon,authenticated;

create or replace function private.supplier_products() returns setof public.products language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 return query select p.* from public.products p join public.suppliers s on s.id=p.supplier_id
 where s.owner_id=auth.uid() and s.approval_status='approved' and not p.archived order by p.created_at desc;
end $$;

create function private.my_supplier_accounts() returns table(id uuid,name text,cities text[])
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 return query select s.id,s.name,s.cities from public.suppliers s where s.owner_id=auth.uid() and s.approval_status='approved' order by s.created_at;
end $$;
create function public.my_supplier_accounts() returns table(id uuid,name text,cities text[])
language sql stable security invoker set search_path='' as $$select * from private.my_supplier_accounts()$$;

create function private.supplier_save_product(p_product_id uuid,p_supplier_id uuid,p_data jsonb,p_expected_version integer) returns public.products
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
 if coalesce(cardinality(v_cities),0) not between 1 and 2 or not(v_cities <@ v_supplier.cities) or cardinality(v_cities)<>(select count(distinct x) from unnest(v_cities) x) then raise exception 'invalid product cities';end if;
 v_active:=(p_data->>'active')::boolean;
 if p_product_id is null then
  insert into public.products(name,description,category,price_halalas,stock,unit,cities,active,supplier_id)
  values(v_name,v_description,v_category,v_price,v_stock,v_unit,v_cities,v_active,p_supplier_id) returning * into v_product;
 else
  update public.products set name=v_name,description=v_description,category=v_category,price_halalas=v_price,stock=v_stock,unit=v_unit,cities=v_cities,active=v_active where id=p_product_id returning * into v_product;
 end if;
 return v_product;
end $$;
create function public.supplier_save_product(p_product_id uuid,p_supplier_id uuid,p_data jsonb,p_expected_version integer) returns public.products
language sql security invoker set search_path='' as $$ select private.supplier_save_product(p_product_id,p_supplier_id,p_data,p_expected_version) $$;

create function private.supplier_adjust_stock(p_product_id uuid,p_delta integer,p_expected_version integer) returns public.products
language plpgsql security definer set search_path='' as $$
declare v_product public.products%rowtype;
begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 select * into v_product from public.products where id=p_product_id for update;
 if not found or not private.owns_supplier(v_product.supplier_id) or v_product.archived then raise exception 'permission denied' using errcode='42501';end if;
 if p_expected_version is null or v_product.inventory_version<>p_expected_version then raise exception 'inventory changed; reload before saving' using errcode='40001';end if;
 if p_delta is null or p_delta=0 or p_delta not between -1000000 and 1000000 or v_product.stock+p_delta not between 0 and 1000000 then raise exception 'invalid stock adjustment';end if;
 update public.products set stock=stock+p_delta where id=p_product_id returning * into v_product;
 return v_product;
end $$;
create function public.supplier_adjust_stock(p_product_id uuid,p_delta integer,p_expected_version integer) returns public.products
language sql security invoker set search_path='' as $$select private.supplier_adjust_stock(p_product_id,p_delta,p_expected_version)$$;

create function private.supplier_archive_product(p_product_id uuid,p_expected_version integer) returns void
language plpgsql security definer set search_path='' as $$
declare v_product public.products%rowtype;
begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 select * into v_product from public.products where id=p_product_id for update;
 if not found or not private.owns_supplier(v_product.supplier_id) or v_product.archived then raise exception 'permission denied' using errcode='42501';end if;
 if p_expected_version is null or v_product.inventory_version<>p_expected_version then raise exception 'inventory changed; reload before saving' using errcode='40001';end if;
 update public.products set active=false,archived=true where id=p_product_id;
end $$;
create function public.supplier_archive_product(p_product_id uuid,p_expected_version integer) returns void
language sql security invoker set search_path='' as $$select private.supplier_archive_product(p_product_id,p_expected_version)$$;

create table private.inventory_imports (
 user_id uuid not null references auth.users(id), request_id uuid not null,
 supplier_id uuid not null references public.suppliers(id), product_ids uuid[] not null,
 created_at timestamptz not null default now(),primary key(user_id,request_id)
);
create index inventory_imports_supplier_idx on private.inventory_imports(supplier_id);
alter table private.inventory_imports enable row level security;
revoke all on private.inventory_imports from public,anon,authenticated;
create function private.supplier_import_products(p_supplier_id uuid,p_rows jsonb,p_request_id uuid) returns uuid[]
language plpgsql security definer set search_path='' as $$
declare v_ids uuid[];v_row jsonb;v_product public.products%rowtype;v_supplier uuid;
begin
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
create function public.supplier_import_products(p_supplier_id uuid,p_rows jsonb,p_request_id uuid) returns uuid[]
language sql security invoker set search_path='' as $$select private.supplier_import_products(p_supplier_id,p_rows,p_request_id)$$;

revoke all on function private.my_supplier_accounts(),public.my_supplier_accounts(),private.supplier_save_product(uuid,uuid,jsonb,integer),public.supplier_save_product(uuid,uuid,jsonb,integer),private.supplier_adjust_stock(uuid,integer,integer),public.supplier_adjust_stock(uuid,integer,integer),private.supplier_archive_product(uuid,integer),public.supplier_archive_product(uuid,integer),private.supplier_import_products(uuid,jsonb,uuid),public.supplier_import_products(uuid,jsonb,uuid) from public,anon;
grant execute on function private.my_supplier_accounts(),public.my_supplier_accounts(),private.supplier_save_product(uuid,uuid,jsonb,integer),public.supplier_save_product(uuid,uuid,jsonb,integer),private.supplier_adjust_stock(uuid,integer,integer),public.supplier_adjust_stock(uuid,integer,integer),private.supplier_archive_product(uuid,integer),public.supplier_archive_product(uuid,integer),private.supplier_import_products(uuid,jsonb,uuid),public.supplier_import_products(uuid,jsonb,uuid) to authenticated;
