-- Price & markup management ("إدارة الأسعار والعمولات").
-- * The supplier's original price (products.supplier_price_halalas) is never changed by pricing.
-- * Sale price (products.price_halalas, before VAT) = original + markup of exactly ONE rule.
-- * Priority: product (4) > supplier (3) > category (2) > all (1); one active rule per target.
-- * Every price change is logged with actor, time, old and new values.

create table if not exists public.pricing_rules (
  id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('all','category','supplier','product')),
  supplier_id uuid references public.suppliers(id),
  category text check (category in ('water','quran','supplies','food','equipment')),
  product_id uuid references public.products(id),
  method text not null check (method in ('percent','fixed','final_price')),
  value integer not null check (value >= 0),
  active boolean not null default true,
  note text check (note is null or length(note) <= 500),
  created_by uuid, created_at timestamptz not null default now(),
  updated_by uuid, updated_at timestamptz not null default now(),
  constraint pricing_rule_target check (
    (scope='all' and supplier_id is null and category is null and product_id is null) or
    (scope='category' and category is not null and supplier_id is null and product_id is null) or
    (scope='supplier' and supplier_id is not null and category is null and product_id is null) or
    (scope='product' and product_id is not null and supplier_id is null and category is null)),
  constraint final_price_product_only check (method <> 'final_price' or scope = 'product'),
  constraint percent_bounds check (method <> 'percent' or value <= 100000),
  constraint amount_bounds check (value <= 100000000)
);
create unique index if not exists pricing_rules_one_active_per_target on public.pricing_rules
  (scope, coalesce(supplier_id::text,''), coalesce(category,''), coalesce(product_id::text,'')) where active;
alter table public.pricing_rules enable row level security;
revoke all on public.pricing_rules from public, anon, authenticated;
grant select on public.pricing_rules to authenticated;
create policy pricing_rules_operator_read on public.pricing_rules for select to authenticated using ((select private.is_platform_operator()));

alter table public.products add column if not exists markup_halalas integer not null default 0 check (markup_halalas >= 0);
alter table public.products add column if not exists pricing_rule_id uuid;
alter table public.products add column if not exists price_conflict boolean not null default false;
alter table public.products add column if not exists vat_rate_bp integer not null default 0;
alter table public.products add column if not exists display_price_halalas integer;
alter table public.products add column if not exists price_computed_at timestamptz;
update public.products set supplier_price_halalas = price_halalas where supplier_price_halalas is null;

create or replace function private.rule_priority(p_scope text) returns integer language sql immutable set search_path='' as $$
  select case p_scope when 'product' then 4 when 'supplier' then 3 when 'category' then 2 else 1 end $$;

create or replace function private.rule_markup(p_method text, p_value integer, p_orig integer, out markup integer, out conflict boolean)
language plpgsql immutable set search_path='' as $$
begin
  conflict := false;
  if p_method = 'percent' then markup := round(p_orig::numeric * p_value / 10000);
  elsif p_method = 'fixed' then markup := p_value;
  elsif p_method = 'final_price' then markup := p_value - p_orig;
    if markup < 0 then markup := 0; conflict := true; end if;   -- never sell below the supplier's own price
  else markup := 0; end if;
end $$;

-- The single applicable rule for a product (highest priority active match).
create or replace function private.applicable_rule(p_supplier uuid, p_category text, p_product uuid, p_exclude uuid default null)
returns public.pricing_rules language sql stable security definer set search_path='' as $$
  select r.* from public.pricing_rules r
  where r.active and (p_exclude is null or r.id <> p_exclude) and (
    r.scope='all' or (r.scope='category' and r.category=p_category) or
    (r.scope='supplier' and r.supplier_id=p_supplier) or (r.scope='product' and r.product_id=p_product))
  order by private.rule_priority(r.scope) desc limit 1 $$;

create or replace function private.supplier_vat_bp(p_supplier uuid) returns integer
language sql stable security definer set search_path='' as $$
  select case when coalesce((select p.vat_registered from public.supplier_payment_profiles p where p.supplier_id=p_supplier),
                            private.is_valid_sa_vat((select s.tax_number from public.suppliers s where s.id=p_supplier)))
              then (select vat_rate_bp from private.finance_settings where id) else 0 end $$;

create or replace function private.trg_product_pricing() returns trigger language plpgsql security definer set search_path='' as $$
declare r public.pricing_rules; m record;
begin
  if new.supplier_price_halalas is null then new.supplier_price_halalas := new.price_halalas; end if;
  if new.supplier_price_halalas is null or new.supplier_price_halalas < 1 then raise exception 'invalid supplier price'; end if;
  r := private.applicable_rule(new.supplier_id, new.category, new.id);
  select * into m from private.rule_markup(coalesce(r.method,'none'), coalesce(r.value,0), new.supplier_price_halalas);
  new.markup_halalas := m.markup;
  new.price_conflict := m.conflict;
  new.pricing_rule_id := r.id;
  new.price_halalas := new.supplier_price_halalas + m.markup;
  new.vat_rate_bp := private.supplier_vat_bp(new.supplier_id);
  new.display_price_halalas := new.price_halalas + round(new.price_halalas::numeric * new.vat_rate_bp / 10000)::integer;
  new.price_computed_at := now();
  return new;
end $$;
drop trigger if exists product_pricing on public.products;
create trigger product_pricing before insert or update of supplier_price_halalas, price_halalas, category, supplier_id, vat_rate_bp
  on public.products for each row execute function private.trg_product_pricing();

create or replace function private.trg_product_price_audit() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.supplier_price_halalas is distinct from new.supplier_price_halalas then
    insert into public.pricing_audit_log(actor_id, entity_type, entity_id, action, old_value, new_value)
    values (auth.uid(), 'supplier_price', new.id::text, 'supplier_price_changed',
      jsonb_build_object('supplier_price_halalas', old.supplier_price_halalas), jsonb_build_object('supplier_price_halalas', new.supplier_price_halalas));
  end if;
  if old.price_halalas is distinct from new.price_halalas or old.display_price_halalas is distinct from new.display_price_halalas then
    insert into public.pricing_audit_log(actor_id, entity_type, entity_id, action, old_value, new_value)
    values (auth.uid(), 'product_price', new.id::text, 'sale_price_changed',
      jsonb_build_object('price_halalas', old.price_halalas, 'markup_halalas', old.markup_halalas, 'display_price_halalas', old.display_price_halalas, 'rule', old.pricing_rule_id),
      jsonb_build_object('price_halalas', new.price_halalas, 'markup_halalas', new.markup_halalas, 'display_price_halalas', new.display_price_halalas, 'rule', new.pricing_rule_id));
  end if;
  return null;
end $$;
drop trigger if exists product_price_audit on public.products;
create trigger product_price_audit after update on public.products for each row execute function private.trg_product_price_audit();

-- Recompute shelf prices for a target (all products when every argument is null).
create or replace function private.reprice_products(p_supplier uuid, p_category text, p_product uuid, p_reason text) returns integer
language plpgsql security definer set search_path='' as $$
declare n integer;
begin
  update public.products p set vat_rate_bp = private.supplier_vat_bp(p.supplier_id)
  where (p_product is null or p.id = p_product) and (p_supplier is null or p.supplier_id = p_supplier) and (p_category is null or p.category = p_category);
  get diagnostics n = row_count;
  return n;
end $$;

-- VAT status changes on a supplier reprice its catalog.
create or replace function private.trg_profile_vat_reprice() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if tg_op = 'INSERT' or old.vat_registered is distinct from new.vat_registered then
    perform private.reprice_products(new.supplier_id, null, null, 'vat_status'); end if;
  return null;
end $$;
create trigger payment_profile_vat_reprice after insert or update of vat_registered on public.supplier_payment_profiles
  for each row execute function private.trg_profile_vat_reprice();

-- Visibility: shoppers only see products of suppliers allowed to sell.
grant select (selling_enabled) on public.suppliers to anon, authenticated;  -- non-sensitive flag used by the visibility policy
create policy products_selling_supplier_anon on public.products as restrictive for select to anon
  using (exists (select 1 from public.suppliers s where s.id = products.supplier_id and s.selling_enabled));
create policy products_selling_supplier_auth on public.products as restrictive for select to authenticated
  using ((select private.is_platform_operator()) or private.owns_supplier(supplier_id)
    or exists (select 1 from public.suppliers s where s.id = products.supplier_id and s.selling_enabled));

-- ---------------------------------------------------------------- supplier writes the ORIGINAL price only
create or replace function private.supplier_save_product(p_product_id uuid, p_supplier_id uuid, p_data jsonb, p_expected_version integer)
returns public.products language plpgsql security definer set search_path to '' as $function$
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
 -- price_halalas here is the supplier's ORIGINAL price; the sale price is derived by pricing rules.
 if p_product_id is null then
  insert into public.products(name,description,category,price_halalas,supplier_price_halalas,stock,unit,cities,active,supplier_id)
  values(v_name,v_description,v_category,v_price,v_price,v_stock,v_unit,v_cities,v_active,p_supplier_id) returning * into v_product;
 else
  update public.products set name=v_name,description=v_description,category=v_category,supplier_price_halalas=v_price,stock=v_stock,unit=v_unit,cities=v_cities,active=v_active where id=p_product_id returning * into v_product;
 end if;
 return v_product;
end $function$;

-- Admin no longer overwrites prices directly; price changes go through pricing rules.
create or replace function public.admin_update_product(p_id uuid, p_price_halalas integer, p_stock integer, p_active boolean, p_featured boolean)
returns void language plpgsql security definer set search_path to '' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_price_halalas is not null then
    raise exception 'direct price edits are disabled; use pricing rules (إدارة الأسعار والعمولات)'; end if;
  if p_stock is not null and (p_stock < 0 or p_stock > 1000000) then raise exception 'invalid stock'; end if;
  update public.products set stock=coalesce(p_stock,stock), active=coalesce(p_active,active), featured=coalesce(p_featured,featured) where id=p_id;
  if not found then raise exception 'product not found'; end if;
  perform private.admin_log('product_update','product',p_id::text);
end $$;

-- ---------------------------------------------------------------- admin pricing RPCs
create or replace function private.rule_matches(r public.pricing_rules, p public.products) returns boolean language sql immutable set search_path='' as $$
  select r.scope='all' or (r.scope='category' and r.category=p.category) or (r.scope='supplier' and r.supplier_id=p.supplier_id) or (r.scope='product' and r.product_id=p.id) $$;

create or replace function public.admin_preview_pricing_rule(p_rule_id uuid, p_scope text, p_supplier uuid, p_category text, p_product uuid,
  p_method text, p_value integer, p_active boolean default true)
returns table(product_id uuid, product_name text, supplier_name text, category text, original_halalas integer, current_price_halalas integer,
  current_rule_scope text, new_markup_halalas integer, new_price_halalas integer, new_display_price_halalas integer, vat_rate_bp integer,
  conflict boolean, governed_by_proposed boolean, changed boolean)
language plpgsql stable security definer set search_path='' as $$
declare prop public.pricing_rules; p public.products; best public.pricing_rules; m record; cur_scope text;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  prop := row(coalesce(p_rule_id, gen_random_uuid()), p_scope, p_supplier, p_category, p_product, p_method, p_value, coalesce(p_active,true),
              null, null, now(), null, now())::public.pricing_rules;
  for p in select * from public.products pr where not pr.archived and private.rule_matches(prop, pr)
            or (p_rule_id is not null and pr.pricing_rule_id = p_rule_id) order by pr.name loop
    best := private.applicable_rule(p.supplier_id, p.category, p.id, p_rule_id);
    if prop.active and private.rule_matches(prop, p) and (best.id is null or private.rule_priority(prop.scope) >= private.rule_priority(best.scope)) then
      best := prop; end if;
    select * into m from private.rule_markup(coalesce(best.method,'none'), coalesce(best.value,0), p.supplier_price_halalas);
    select r.scope into cur_scope from public.pricing_rules r where r.id = p.pricing_rule_id;
    product_id := p.id; product_name := p.name; category := p.category; original_halalas := p.supplier_price_halalas;
    supplier_name := (select s.name from public.suppliers s where s.id=p.supplier_id);
    current_price_halalas := p.price_halalas; current_rule_scope := cur_scope; new_markup_halalas := m.markup;
    new_price_halalas := p.supplier_price_halalas + m.markup; vat_rate_bp := p.vat_rate_bp;
    new_display_price_halalas := new_price_halalas + round(new_price_halalas::numeric * p.vat_rate_bp / 10000)::integer;
    conflict := m.conflict; governed_by_proposed := best.id = prop.id; changed := new_price_halalas is distinct from p.price_halalas;
    return next;
  end loop;
end $$;

create or replace function public.admin_save_pricing_rule(p_rule_id uuid, p_scope text, p_supplier uuid, p_category text, p_product uuid,
  p_method text, p_value integer, p_note text default null) returns public.pricing_rules
language plpgsql security definer set search_path='' as $$
declare old_r public.pricing_rules; new_r public.pricing_rules; v_orig integer;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_scope = 'product' and p_method = 'final_price' then
    select supplier_price_halalas into v_orig from public.products where id = p_product;
    if v_orig is null then raise exception 'product not found'; end if;
    if p_value < v_orig then raise exception 'final price (%) cannot be below the supplier original price (%)', p_value, v_orig; end if;
  end if;
  if p_rule_id is null then
    if exists(select 1 from public.pricing_rules r where r.active and r.scope=p_scope and r.supplier_id is not distinct from p_supplier
               and r.category is not distinct from p_category and r.product_id is not distinct from p_product) then
      raise exception 'an active rule already exists for this target; edit it instead (only one rule per target)'; end if;
    insert into public.pricing_rules(scope, supplier_id, category, product_id, method, value, note, created_by, updated_by)
    values (p_scope, p_supplier, p_category, p_product, p_method, p_value, nullif(btrim(p_note),''), auth.uid(), auth.uid()) returning * into new_r;
  else
    select * into old_r from public.pricing_rules where id=p_rule_id for update;
    if not found then raise exception 'rule not found'; end if;
    update public.pricing_rules set scope=p_scope, supplier_id=p_supplier, category=p_category, product_id=p_product, method=p_method, value=p_value,
      note=nullif(btrim(p_note),''), updated_by=auth.uid(), updated_at=now() where id=p_rule_id returning * into new_r;
    perform private.reprice_products(old_r.supplier_id, old_r.category, old_r.product_id, 'rule_update');
  end if;
  perform private.reprice_products(new_r.supplier_id, new_r.category, new_r.product_id, 'rule_save');
  perform private.fin_audit('pricing_rule', new_r.id::text, case when old_r.id is null then 'create' else 'update' end, to_jsonb(old_r), to_jsonb(new_r));
  return new_r;
end $$;

create or replace function public.admin_set_pricing_rule_active(p_rule_id uuid, p_active boolean) returns public.pricing_rules
language plpgsql security definer set search_path='' as $$
declare old_r public.pricing_rules; new_r public.pricing_rules;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into old_r from public.pricing_rules where id=p_rule_id for update;
  if not found then raise exception 'rule not found'; end if;
  if p_active and exists(select 1 from public.pricing_rules r where r.active and r.id<>p_rule_id and r.scope=old_r.scope
      and r.supplier_id is not distinct from old_r.supplier_id and r.category is not distinct from old_r.category and r.product_id is not distinct from old_r.product_id) then
    raise exception 'another active rule already governs this target'; end if;
  update public.pricing_rules set active=p_active, updated_by=auth.uid(), updated_at=now() where id=p_rule_id returning * into new_r;
  perform private.reprice_products(new_r.supplier_id, new_r.category, new_r.product_id, 'rule_toggle');
  perform private.fin_audit('pricing_rule', p_rule_id::text, case when p_active then 'activate' else 'deactivate' end, to_jsonb(old_r), to_jsonb(new_r));
  return new_r;
end $$;

create or replace function public.admin_pricing_rules() returns table(rule jsonb, target_label text, products_governed bigint)
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select to_jsonb(r),
    case r.scope when 'all' then 'جميع المنتجات' when 'category' then 'تصنيف: '||r.category
      when 'supplier' then 'مورد: '||coalesce((select s.name from public.suppliers s where s.id=r.supplier_id),'?')
      else 'منتج: '||coalesce((select p.name from public.products p where p.id=r.product_id),'?') end,
    (select count(*) from public.products p where p.pricing_rule_id=r.id)
  from public.pricing_rules r order by r.active desc, private.rule_priority(r.scope) desc, r.updated_at desc;
end $$;

create or replace function public.admin_pricing_overview() returns table(product_id uuid, product_name text, supplier_id uuid, supplier_name text, category text,
  original_halalas integer, markup_halalas integer, price_halalas integer, display_price_halalas integer, vat_rate_bp integer,
  rule_scope text, rule_method text, rule_value integer, price_conflict boolean, base_commission_unit integer, total_commission_unit integer, active boolean)
language plpgsql stable security definer set search_path='' as $$
declare s private.finance_settings := private.fin();
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select p.id, p.name, p.supplier_id, sp.name, p.category, p.supplier_price_halalas, p.markup_halalas, p.price_halalas, p.display_price_halalas,
    p.vat_rate_bp, r.scope, r.method, r.value, p.price_conflict,
    round((p.supplier_price_halalas + case when s.commission_on_markup then p.markup_halalas else 0 end)::numeric * s.commission_rate_bp / 10000)::integer,
    round((p.supplier_price_halalas + case when s.commission_on_markup then p.markup_halalas else 0 end)::numeric * s.commission_rate_bp / 10000)::integer + p.markup_halalas,
    p.active
  from public.products p left join public.suppliers sp on sp.id=p.supplier_id left join public.pricing_rules r on r.id=p.pricing_rule_id
  where not p.archived order by sp.name, p.name;
end $$;

create or replace function public.admin_pricing_audit(p_limit integer default 200) returns table(id bigint, created_at timestamptz, actor_email text,
  entity_type text, entity_id text, entity_label text, action text, old_value jsonb, new_value jsonb)
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select a.id, a.created_at, (select u.email::text from auth.users u where u.id=a.actor_id), a.entity_type, a.entity_id,
    case when a.entity_type in ('product_price','supplier_price') then (select p.name from public.products p where p.id::text=a.entity_id)
         when a.entity_type in ('payment_profile','supplier') then (select s.name from public.suppliers s where s.id::text=a.entity_id) else null end,
    a.action, a.old_value, a.new_value
  from public.pricing_audit_log a order by a.id desc limit greatest(1, least(coalesce(p_limit,200), 2000));
end $$;

revoke all on function public.admin_preview_pricing_rule(uuid,text,uuid,text,uuid,text,integer,boolean), public.admin_save_pricing_rule(uuid,text,uuid,text,uuid,text,integer,text),
  public.admin_set_pricing_rule_active(uuid,boolean), public.admin_pricing_rules(), public.admin_pricing_overview(), public.admin_pricing_audit(integer) from public, anon;
grant execute on function public.admin_preview_pricing_rule(uuid,text,uuid,text,uuid,text,integer,boolean), public.admin_save_pricing_rule(uuid,text,uuid,text,uuid,text,integer,text),
  public.admin_set_pricing_rule_active(uuid,boolean), public.admin_pricing_rules(), public.admin_pricing_overview(), public.admin_pricing_audit(integer) to authenticated;

-- initial computation for existing catalog
select private.reprice_products(null, null, null, 'initial');
