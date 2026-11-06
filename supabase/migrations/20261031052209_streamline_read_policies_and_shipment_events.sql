-- Preserve each existing read predicate while avoiding duplicate policies per role.
-- Public catalog access and authenticated access remain separate role targets.
do $$
declare item record;base_qual text;staff_qual text;
begin
 for item in select * from (values
  ('orders','order_read','operator_orders_read',false),
  ('order_items','order_item_read','operator_items_read',false),
  ('quote_requests','quote_read','operator_quotes_read',false),
  ('seller_applications','seller_read','operator_seller_read',false),
  ('products','products_visible','operator_products_read',true),
  ('suppliers','suppliers_visible','operator_supplier_read',true)
 ) as policies(table_name,base_name,staff_name,public_catalog)
 loop
  select pg_catalog.pg_get_expr(p.polqual,p.polrelid) into base_qual from pg_catalog.pg_policy p
   where p.polrelid=format('public.%I',item.table_name)::regclass and p.polname=item.base_name and p.polcmd='r' and p.polpermissive;
  select pg_catalog.pg_get_expr(p.polqual,p.polrelid) into staff_qual from pg_catalog.pg_policy p
   where p.polrelid=format('public.%I',item.table_name)::regclass and p.polname=item.staff_name and p.polcmd='r' and p.polpermissive;
  if base_qual is null or staff_qual is null then raise exception 'Expected read policies not found on %',item.table_name;end if;
  execute format('drop policy %I on public.%I',item.staff_name,item.table_name);
  if item.public_catalog then
   execute format('alter policy %I on public.%I to anon',item.base_name,item.table_name);
   execute format('create policy %I on public.%I for select to authenticated using ((%s) or (%s))',item.staff_name,item.table_name,base_qual,staff_qual);
  else
   execute format('alter policy %I on public.%I using ((%s) or (%s))',item.base_name,item.table_name,base_qual,staff_qual);
  end if;
 end loop;
end $$;
create index if not exists oto_events_shipment_idx on private.oto_events(shipment_id);
