-- 35% platform markup: supplier enters net price; shown/sold price = net * 1.35 (auto).
alter table public.products add column if not exists supplier_price_halalas integer;

create or replace function private.supplier_save_product(p_product_id uuid, p_supplier_id uuid, p_data jsonb, p_expected_version integer)
returns public.products language plpgsql security definer set search_path to '' as $function$
declare v_product public.products%rowtype;v_supplier public.suppliers%rowtype;v_name text;v_unit text;v_description text;v_category text;v_price integer;v_sale integer;v_stock integer;v_cities text[];v_active boolean;
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
 v_sale := round(v_price * 1.35);  -- 35% platform markup over the supplier's net price
 if jsonb_typeof(p_data->'cities') is distinct from 'array' or jsonb_typeof(p_data->'active') is distinct from 'boolean' then raise exception 'invalid product cities or visibility';end if;
 select array_agg(value) into v_cities from jsonb_array_elements_text(p_data->'cities');
 if coalesce(cardinality(v_cities),0) not between 1 and 4 or not(v_cities <@ v_supplier.cities) or cardinality(v_cities)<>(select count(distinct x) from unnest(v_cities) x) then raise exception 'invalid product cities';end if;
 v_active:=(p_data->>'active')::boolean;
 if p_product_id is null then
  insert into public.products(name,description,category,price_halalas,supplier_price_halalas,stock,unit,cities,active,supplier_id)
  values(v_name,v_description,v_category,v_sale,v_price,v_stock,v_unit,v_cities,v_active,p_supplier_id) returning * into v_product;
 else
  update public.products set name=v_name,description=v_description,category=v_category,price_halalas=v_sale,supplier_price_halalas=v_price,stock=v_stock,unit=v_unit,cities=v_cities,active=v_active where id=p_product_id returning * into v_product;
 end if;
 return v_product;
end $function$;
