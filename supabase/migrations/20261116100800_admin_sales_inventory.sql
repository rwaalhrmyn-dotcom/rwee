-- Admin tools: platform sales tracking, inventory count (جرد), and per-supplier commission
-- invoicing (including a preview of commissions not yet invoiced). Read-only except the
-- per-supplier close/issue, which reuses the same invoice rules as the monthly close.

-- ---------------------------------------------------------------- sales tracking
create or replace function public.admin_sales_report(p_from date, p_to date, p_supplier uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_from timestamptz; v_to timestamptz;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'invalid period'; end if;
  if p_to - p_from > 400 then raise exception 'period too long (max 400 days)'; end if;
  v_from := (p_from::timestamp at time zone 'Asia/Riyadh');
  v_to := ((p_to + 1)::timestamp at time zone 'Asia/Riyadh');
  return (with o as (
      select o.*, s.name as supplier_name from public.orders o left join public.suppliers s on s.id=o.supplier_id
      where o.created_at >= v_from and o.created_at < v_to and o.payment_mode='supplier_direct'
        and (p_supplier is null or o.supplier_id=p_supplier)),
    li as (
      select oi.*, o.status as order_status, o.payment_status from public.order_items oi join o on o.id=oi.order_id)
    select jsonb_build_object(
      'period', jsonb_build_object('from', p_from, 'to', p_to),
      'totals', (select jsonb_build_object(
          'orders', count(*),
          'paid_orders', count(*) filter (where payment_status='paid'),
          'awaiting_payment', count(*) filter (where payment_status='unpaid' and status<>'cancelled'),
          'delivered', count(*) filter (where status='delivered'),
          'cancelled', count(*) filter (where status='cancelled'),
          'gross_halalas', coalesce(sum(payable_halalas) filter (where status<>'cancelled'),0),
          'paid_halalas', coalesce(sum(payable_halalas) filter (where payment_status='paid'),0),
          'unpaid_halalas', coalesce(sum(payable_halalas) filter (where payment_status='unpaid' and status<>'cancelled'),0),
          'refunded_halalas', coalesce(sum(refunded_halalas),0),
          'vat_halalas', coalesce(sum(vat_halalas) filter (where payment_status='paid'),0),
          'cod_orders', count(*) filter (where payment_method='cod'),
          'link_orders', count(*) filter (where payment_method='supplier_link')) from o),
      'commission', (select jsonb_build_object(
          'expected_halalas', coalesce(sum(base_commission_halalas + markup_commission_halalas) filter (where order_status<>'cancelled'),0),
          'base_halalas', coalesce(sum(base_commission_halalas) filter (where order_status<>'cancelled'),0),
          'markup_halalas', coalesce(sum(markup_commission_halalas) filter (where order_status<>'cancelled'),0),
          'accrued_halalas', (select coalesce(sum(e.total_commission_halalas),0) from public.commission_entries e join o on o.id=e.order_id)) from li),
      'by_day', (select coalesce(jsonb_agg(d order by d->>'day'),'[]'::jsonb) from (
          select jsonb_build_object('day', (created_at at time zone 'Asia/Riyadh')::date, 'orders', count(*),
            'gross_halalas', coalesce(sum(payable_halalas) filter (where status<>'cancelled'),0),
            'paid_halalas', coalesce(sum(payable_halalas) filter (where payment_status='paid'),0)) d
          from o group by (created_at at time zone 'Asia/Riyadh')::date) x),
      'by_supplier', (select coalesce(jsonb_agg(x order by (x->>'gross_halalas')::bigint desc),'[]'::jsonb) from (
          select jsonb_build_object('supplier_id', supplier_id, 'supplier', supplier_name, 'orders', count(*),
            'paid_orders', count(*) filter (where payment_status='paid'),
            'gross_halalas', coalesce(sum(payable_halalas) filter (where status<>'cancelled'),0),
            'paid_halalas', coalesce(sum(payable_halalas) filter (where payment_status='paid'),0),
            'unpaid_halalas', coalesce(sum(payable_halalas) filter (where payment_status='unpaid' and status<>'cancelled'),0),
            'refunded_halalas', coalesce(sum(refunded_halalas),0),
            'commission_halalas', (select coalesce(sum(l.base_commission_halalas + l.markup_commission_halalas),0) from li l
                                    where l.supplier_id=o.supplier_id and l.order_status<>'cancelled')) x
          from o group by supplier_id, supplier_name) t),
      'by_product', (select coalesce(jsonb_agg(x order by (x->>'qty')::bigint desc),'[]'::jsonb) from (
          select jsonb_build_object('product_id', product_id, 'product', max(product_name),
            'supplier', (select s.name from public.suppliers s where s.id=max(li.supplier_id::text)::uuid),
            'qty', sum(quantity), 'sales_halalas', sum(coalesce(line_net_halalas, unit_price_halalas*quantity)),
            'commission_halalas', sum(base_commission_halalas + markup_commission_halalas)) x
          from li where order_status<>'cancelled' group by product_id order by sum(quantity) desc limit 100) t),
      'orders', (select coalesce(jsonb_agg(x order by x->>'created_at' desc),'[]'::jsonb) from (
          select jsonb_build_object('id', id, 'created_at', created_at, 'supplier', supplier_name, 'city', city, 'status', status,
            'payment_status', payment_status, 'payment_method', payment_method, 'payable_halalas', payable_halalas,
            'refunded_halalas', refunded_halalas) x from o order by created_at desc limit 500) t)
    ));
end $$;

-- ---------------------------------------------------------------- inventory count (جرد)
create or replace function public.admin_inventory_report(p_supplier uuid default null, p_low integer default 5) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_since timestamptz := now() - interval '30 days';
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select jsonb_build_object('product_id', p.id, 'product', p.name, 'category', p.category, 'unit', p.unit,
      'supplier_id', p.supplier_id, 'supplier', s.name, 'active', p.active, 'archived', p.archived, 'stock', p.stock,
      'original_halalas', p.supplier_price_halalas, 'price_halalas', p.price_halalas,
      'stock_value_original_halalas', coalesce(p.supplier_price_halalas,0)::bigint * greatest(p.stock,0),
      'stock_value_sale_halalas', coalesce(p.price_halalas,0)::bigint * greatest(p.stock,0),
      'reserved_qty', (select coalesce(sum(oi.quantity),0) from public.order_items oi join public.orders o on o.id=oi.order_id
                        where oi.product_id=p.id and o.status in ('pending','confirmed','preparing','out_for_delivery')),
      'sold_30d', (select coalesce(sum(oi.quantity),0) from public.order_items oi join public.orders o on o.id=oi.order_id
                    where oi.product_id=p.id and o.status<>'cancelled' and o.created_at >= v_since),
      'state', case when p.stock <= 0 then 'out' when p.stock <= coalesce(p_low,5) then 'low' else 'ok' end)
    from public.products p left join public.suppliers s on s.id=p.supplier_id
    where not p.archived and (p_supplier is null or p.supplier_id=p_supplier)
    order by (p.stock <= 0) desc, (p.stock <= coalesce(p_low,5)) desc, s.name, p.name;
end $$;

-- ---------------------------------------------------------------- commission invoicing
-- Commissions earned but not yet on any invoice, per supplier and month (incl. the open month).
create or replace function public.admin_uninvoiced_commissions() returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select jsonb_build_object('supplier_id', e.supplier_id, 'supplier', s.name, 'period_month', e.period_month,
      'orders', count(distinct e.order_id) filter (where e.kind='accrual'),
      'original_halalas', coalesce(sum(e.gross_original_halalas),0),
      'commission_halalas', coalesce(sum(e.total_commission_halalas),0),
      'closable', e.period_month < private.ksa_month(now()),
      'invoice_status', (select i.status from public.commission_invoices i where i.supplier_id=e.supplier_id and i.period_month=e.period_month))
    from public.commission_entries e join public.suppliers s on s.id=e.supplier_id
    where e.invoice_id is null and e.credit_note_id is null
    group by e.supplier_id, s.name, e.period_month order by e.period_month desc, s.name;
end $$;

-- Close (and optionally issue) one supplier's invoice for a completed month. Same rules as
-- the monthly close: one invoice per supplier per month, issued invoices are never changed.
create or replace function public.admin_close_supplier_period(p_supplier uuid, p_month date, p_issue boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_month date := date_trunc('month', p_month)::date; v_inv uuid; v_status text; v_no text;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if v_month >= private.ksa_month(now()) then raise exception 'only completed months can be closed'; end if;
  perform pg_advisory_xact_lock(hashtextextended('close-period:'||v_month::text, 0));
  select id, status into v_inv, v_status from public.commission_invoices where supplier_id=p_supplier and period_month=v_month;
  if v_inv is null then
    if not exists(select 1 from public.commission_entries where supplier_id=p_supplier and invoice_id is null and credit_note_id is null and period_month <= v_month) then
      raise exception 'no uninvoiced commissions for this supplier up to this month'; end if;
    insert into public.commission_invoices(supplier_id, period_month, period_start, period_end)
    values (p_supplier, v_month, v_month, (v_month + interval '1 month - 1 day')::date) returning id into v_inv;
    v_status := 'draft';
  end if;
  if v_status = 'draft' then
    update public.commission_entries set invoice_id=v_inv
     where supplier_id=p_supplier and invoice_id is null and credit_note_id is null and period_month <= v_month;
    perform private.recompute_invoice(v_inv);
    if p_issue then perform private.issue_invoice(v_inv); end if;
  end if;
  select invoice_no, status into v_no, v_status from public.commission_invoices where id=v_inv;
  perform private.admin_log('billing_close_supplier_period', 'supplier', p_supplier::text);
  return jsonb_build_object('invoice_id', v_inv, 'invoice_no', v_no, 'status', v_status);
end $$;

revoke all on function public.admin_sales_report(date,date,uuid), public.admin_inventory_report(uuid,integer),
  public.admin_uninvoiced_commissions(), public.admin_close_supplier_period(uuid,date,boolean) from public, anon;
grant execute on function public.admin_sales_report(date,date,uuid), public.admin_inventory_report(uuid,integer),
  public.admin_uninvoiced_commissions(), public.admin_close_supplier_period(uuid,date,boolean) to authenticated;
