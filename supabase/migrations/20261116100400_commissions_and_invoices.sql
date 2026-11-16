-- Commission ledger, monthly commission invoices, payments, credit notes, overdue handling.
-- Rawaa commission per line = base (rate x original price, pre-VAT/shipping; optionally on
-- markup only when explicitly enabled) + markup (sale price - original), snapshotted at purchase.

create sequence if not exists private.invoice_seq;
create sequence if not exists private.credit_note_seq;

create table if not exists public.commission_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_no text unique,
  supplier_id uuid not null references public.suppliers(id),
  period_month date not null check (period_month = date_trunc('month', period_month)::date),
  period_start date not null,
  period_end date not null,
  status text not null default 'draft' check (status in ('draft','issued','partially_paid','paid','overdue','cancelled')),
  currency text not null default 'SAR',
  order_count integer not null default 0,
  gross_original_halalas bigint not null default 0,
  base_commission_halalas bigint not null default 0,
  markup_commission_halalas bigint not null default 0,
  adjustments_halalas bigint not null default 0,
  credits_applied_halalas bigint not null default 0 check (credits_applied_halalas >= 0),
  subtotal_halalas bigint not null default 0,
  vat_rate_bp integer not null default 0,
  vat_halalas bigint not null default 0,
  total_halalas bigint not null default 0 check (total_halalas >= 0),
  credit_generated_halalas bigint not null default 0 check (credit_generated_halalas >= 0),
  paid_halalas bigint not null default 0 check (paid_halalas >= 0),
  credited_halalas bigint not null default 0 check (credited_halalas >= 0),
  issue_date date,
  due_date date,
  issued_at timestamptz,
  paid_at timestamptz,
  overdue_since date,
  supplier_snapshot jsonb,
  platform_snapshot jsonb,
  order_refs jsonb not null default '[]'::jsonb,
  snapshot_sha256 text,
  zatca_qr_tlv text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (supplier_id, period_month)
);
create index if not exists commission_invoices_status_idx on public.commission_invoices(status, due_date);
alter table public.commission_invoices enable row level security;
revoke all on public.commission_invoices from public, anon, authenticated;
grant select on public.commission_invoices to authenticated;
create policy commission_invoices_read on public.commission_invoices for select to authenticated
  using ((private.owns_supplier(supplier_id) and status <> 'draft') or (select private.is_platform_operator()));

create table if not exists public.commission_entries (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id),
  order_id uuid not null references public.orders(id),
  order_item_id uuid references public.order_items(id),
  kind text not null check (kind in ('accrual','reversal')),
  period_month date not null,
  gross_original_halalas bigint not null,
  sale_net_halalas bigint not null default 0,
  base_commission_halalas bigint not null,
  markup_commission_halalas bigint not null,
  total_commission_halalas bigint generated always as (base_commission_halalas + markup_commission_halalas) stored,
  refund_id uuid references public.order_refunds(id),
  invoice_id uuid references public.commission_invoices(id),
  credit_note_id uuid,
  created_at timestamptz not null default now()
);
create unique index if not exists commission_one_accrual_per_line on public.commission_entries(order_item_id) where kind='accrual';
create unique index if not exists commission_one_reversal_per_refund_line on public.commission_entries(refund_id, order_item_id) where kind='reversal';
create index if not exists commission_entries_open_idx on public.commission_entries(supplier_id, period_month) where invoice_id is null and credit_note_id is null;
alter table public.commission_entries enable row level security;
revoke all on public.commission_entries from public, anon, authenticated;
grant select on public.commission_entries to authenticated;
create policy commission_entries_read on public.commission_entries for select to authenticated
  using (private.owns_supplier(supplier_id) or (select private.is_platform_operator()));

create or replace function private.trg_commission_entry_guard() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op = 'DELETE' then raise exception 'commission entries are append-only'; end if;
  if (old.supplier_id, old.order_id, old.order_item_id, old.kind, old.period_month, old.gross_original_halalas, old.base_commission_halalas, old.markup_commission_halalas, old.refund_id)
     is distinct from (new.supplier_id, new.order_id, new.order_item_id, new.kind, new.period_month, new.gross_original_halalas, new.base_commission_halalas, new.markup_commission_halalas, new.refund_id) then
    raise exception 'commission amounts are immutable'; end if;
  if old.invoice_id is not null and new.invoice_id is distinct from old.invoice_id
     and (select status from public.commission_invoices where id = old.invoice_id) <> 'draft' then
    raise exception 'entry already billed on an issued invoice'; end if;
  return new;
end $$;
create trigger commission_entry_guard before update or delete on public.commission_entries for each row execute function private.trg_commission_entry_guard();

create table if not exists public.commission_credit_notes (
  id uuid primary key default gen_random_uuid(),
  credit_note_no text not null unique,
  invoice_id uuid not null references public.commission_invoices(id),
  supplier_id uuid not null references public.suppliers(id),
  amount_halalas bigint not null check (amount_halalas > 0),
  vat_halalas bigint not null default 0 check (vat_halalas >= 0),
  total_halalas bigint generated always as (amount_halalas + vat_halalas) stored,
  reason text not null,
  source text not null check (source in ('refund_after_close','settlement','admin_adjustment')),
  refund_id uuid references public.order_refunds(id),
  issued_by uuid,
  issued_at timestamptz not null default now(),
  snapshot jsonb
);
alter table public.commission_credit_notes enable row level security;
revoke all on public.commission_credit_notes from public, anon, authenticated;
grant select on public.commission_credit_notes to authenticated;
create policy credit_notes_read on public.commission_credit_notes for select to authenticated
  using (private.owns_supplier(supplier_id) or (select private.is_platform_operator()));
create trigger credit_notes_append_only before update or delete on public.commission_credit_notes for each row execute function private.block_mutation();

create table if not exists public.invoice_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.commission_invoices(id),
  supplier_id uuid not null references public.suppliers(id),
  amount_halalas bigint not null check (amount_halalas > 0),
  method text not null default 'bank_transfer' check (method in ('bank_transfer','offset','other')),
  reference text not null check (length(btrim(reference)) between 3 and 120),
  transfer_date date,
  proof_path text,
  status text not null default 'submitted' check (status in ('submitted','verified','rejected')),
  submitted_by uuid,
  submitted_at timestamptz not null default now(),
  verified_by uuid,
  verified_at timestamptz,
  review_note text
);
create unique index if not exists invoice_payment_unique_reference on public.invoice_payments(invoice_id, lower(btrim(reference))) where status <> 'rejected';
alter table public.invoice_payments enable row level security;
revoke all on public.invoice_payments from public, anon, authenticated;
grant select on public.invoice_payments to authenticated;
create policy invoice_payments_read on public.invoice_payments for select to authenticated
  using (private.owns_supplier(supplier_id) or (select private.is_platform_operator()));

-- Issued invoice amounts are frozen; only payment/credit/status bookkeeping may change.
create or replace function private.trg_invoice_guard() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op = 'DELETE' then raise exception 'invoices are never deleted; issue a credit note instead'; end if;
  if old.status <> 'draft' and (old.invoice_no, old.supplier_id, old.period_month, old.order_count, old.gross_original_halalas, old.base_commission_halalas,
      old.markup_commission_halalas, old.adjustments_halalas, old.credits_applied_halalas, old.subtotal_halalas, old.vat_rate_bp, old.vat_halalas, old.total_halalas,
      old.issue_date, old.due_date, old.supplier_snapshot, old.platform_snapshot, old.order_refs, old.snapshot_sha256)
     is distinct from (new.invoice_no, new.supplier_id, new.period_month, new.order_count, new.gross_original_halalas, new.base_commission_halalas,
      new.markup_commission_halalas, new.adjustments_halalas, new.credits_applied_halalas, new.subtotal_halalas, new.vat_rate_bp, new.vat_halalas, new.total_halalas,
      new.issue_date, new.due_date, new.supplier_snapshot, new.platform_snapshot, new.order_refs, new.snapshot_sha256) then
    raise exception 'issued invoice amounts are immutable';
  end if;
  new.updated_at := now();
  return new;
end $$;
create trigger invoice_guard before update or delete on public.commission_invoices for each row execute function private.trg_invoice_guard();

-- ---------------------------------------------------------------- accrual / reversal
create or replace function private.try_accrue_order(p_order uuid) returns integer
language plpgsql security definer set search_path='' as $$
declare o public.orders; n integer := 0; r record;
begin
  select * into o from public.orders where id=p_order;
  if not found or o.payment_mode <> 'supplier_direct' or o.payment_status <> 'paid' or o.status <> 'delivered'
     or o.refund_status = 'full' then return 0; end if;
  if exists(select 1 from public.payment_disputes d where d.order_id=p_order and d.status in ('open','under_review')) then return 0; end if;
  insert into public.commission_entries(supplier_id, order_id, order_item_id, kind, period_month, gross_original_halalas, sale_net_halalas,
    base_commission_halalas, markup_commission_halalas)
  select i.supplier_id, i.order_id, i.id, 'accrual', private.ksa_month(coalesce(o.delivered_at, now())),
    i.supplier_price_halalas::bigint * i.quantity, i.line_net_halalas, i.base_commission_halalas, i.markup_commission_halalas
  from public.order_items i where i.order_id = p_order
  on conflict do nothing;
  get diagnostics n = row_count;
  -- refunds that succeeded before the order became eligible
  for r in select id from public.order_refunds where order_id=p_order and status='succeeded' and not commission_reversed loop
    perform private.reverse_commission_for_refund(r.id);
  end loop;
  return n;
end $$;

create or replace function private.trg_order_accrual() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status = 'delivered' and new.payment_status = 'paid'
     and (old.status is distinct from new.status or old.payment_status is distinct from new.payment_status) then
    perform private.try_accrue_order(new.id);
  end if;
  return null;
end $$;
drop trigger if exists order_accrual on public.orders;
create trigger order_accrual after update of status, payment_status on public.orders for each row execute function private.trg_order_accrual();

create or replace function private.next_doc_no(p_kind text, p_month date) returns text language plpgsql security definer set search_path='' as $$
begin
  return case p_kind when 'invoice' then 'RWA-INV-'||to_char(p_month,'YYYYMM')||'-'||lpad(nextval('private.invoice_seq')::text, 6, '0')
                     else 'RWA-CN-'||to_char(p_month,'YYYYMM')||'-'||lpad(nextval('private.credit_note_seq')::text, 6, '0') end;
end $$;

create or replace function private.issue_credit_note(p_invoice uuid, p_amount bigint, p_reason text, p_source text, p_refund uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare inv public.commission_invoices; v_id uuid; v_vat bigint;
begin
  select * into inv from public.commission_invoices where id=p_invoice for update;
  if not found or inv.status = 'draft' then raise exception 'credit notes apply to issued invoices only'; end if;
  if p_amount <= 0 then raise exception 'credit amount must be positive'; end if;
  v_vat := round(p_amount::numeric * inv.vat_rate_bp / 10000)::bigint;
  insert into public.commission_credit_notes(credit_note_no, invoice_id, supplier_id, amount_halalas, vat_halalas, reason, source, refund_id, issued_by, snapshot)
  values (private.next_doc_no('credit_note', private.ksa_month(now())), p_invoice, inv.supplier_id, p_amount, v_vat, p_reason, p_source, p_refund, auth.uid(),
    jsonb_build_object('invoice_no', inv.invoice_no, 'supplier', inv.supplier_snapshot, 'platform', inv.platform_snapshot))
  returning id into v_id;
  update public.commission_invoices set credited_halalas = credited_halalas + p_amount + v_vat where id = p_invoice;
  perform private.refresh_invoice_status(p_invoice);
  perform private.fin_audit('credit_note', v_id::text, 'issued', null, jsonb_build_object('invoice', inv.invoice_no, 'amount', p_amount, 'vat', v_vat, 'reason', p_reason, 'source', p_source));
  perform private.notify_supplier(inv.supplier_id, 'credit_note', 'إشعار دائن على فاتورة '||inv.invoice_no,
    'تم إصدار إشعار دائن بقيمة '||to_char((p_amount+v_vat)/100.0,'FM999999990.00')||' ر.س — '||p_reason, 'credit_note', v_id::text, null);
  return v_id;
end $$;

create or replace function private.reverse_commission_for_refund(p_refund uuid) returns void
language plpgsql security definer set search_path='' as $$
declare rf public.order_refunds; o public.orders; e record; ratio numeric; v_full boolean; inv_status text;
  rb bigint; rm bigint; rg bigint; rs bigint; per_invoice jsonb := '{}'::jsonb; k text; v_cn uuid;
begin
  select * into rf from public.order_refunds where id=p_refund for update;
  if not found or rf.status <> 'succeeded' or rf.commission_reversed then return; end if;
  select * into o from public.orders where id=rf.order_id;
  if not exists(select 1 from public.commission_entries where order_id=o.id and kind='accrual') then return; end if;  -- nothing accrued yet
  v_full := o.refunded_halalas >= o.payable_halalas;
  ratio := least(1, rf.amount_halalas::numeric / nullif(o.payable_halalas,0));
  for e in select a.*, (select coalesce(sum(r.base_commission_halalas),0) from public.commission_entries r where r.kind='reversal' and r.order_item_id=a.order_item_id) as rev_base,
                       (select coalesce(sum(r.markup_commission_halalas),0) from public.commission_entries r where r.kind='reversal' and r.order_item_id=a.order_item_id) as rev_markup,
                       (select coalesce(sum(r.gross_original_halalas),0) from public.commission_entries r where r.kind='reversal' and r.order_item_id=a.order_item_id) as rev_gross,
                       (select coalesce(sum(r.sale_net_halalas),0) from public.commission_entries r where r.kind='reversal' and r.order_item_id=a.order_item_id) as rev_sale
           from public.commission_entries a where a.order_id=o.id and a.kind='accrual' loop
    if v_full then  -- reverse exactly what remains, avoiding rounding drift
      rb := -(e.base_commission_halalas + e.rev_base); rm := -(e.markup_commission_halalas + e.rev_markup);
      rg := -(e.gross_original_halalas + e.rev_gross); rs := -(e.sale_net_halalas + e.rev_sale);
    else
      rb := -round(e.base_commission_halalas * ratio); rm := -round(e.markup_commission_halalas * ratio);
      rg := -round(e.gross_original_halalas * ratio); rs := -round(e.sale_net_halalas * ratio);
    end if;
    if rb = 0 and rm = 0 and rg = 0 then continue; end if;
    select status into inv_status from public.commission_invoices where id = e.invoice_id;
    if e.invoice_id is not null and inv_status <> 'draft' then
      -- the month is closed and invoiced: settle through a credit note, never by editing the invoice
      per_invoice := jsonb_set(per_invoice, array[e.invoice_id::text], to_jsonb(coalesce((per_invoice->>e.invoice_id::text)::bigint,0) + (-(rb+rm))));
      insert into public.commission_entries(supplier_id, order_id, order_item_id, kind, period_month, gross_original_halalas, sale_net_halalas, base_commission_halalas, markup_commission_halalas, refund_id, credit_note_id)
      values (e.supplier_id, e.order_id, e.order_item_id, 'reversal', private.ksa_month(now()), rg, rs, rb, rm, rf.id, '00000000-0000-0000-0000-000000000000');
    else
      insert into public.commission_entries(supplier_id, order_id, order_item_id, kind, period_month, gross_original_halalas, sale_net_halalas, base_commission_halalas, markup_commission_halalas, refund_id)
      values (e.supplier_id, e.order_id, e.order_item_id, 'reversal', private.ksa_month(now()), rg, rs, rb, rm, rf.id);
    end if;
  end loop;
  for k in select jsonb_object_keys(per_invoice) loop
    if (per_invoice->>k)::bigint > 0 then
      v_cn := private.issue_credit_note(k::uuid, (per_invoice->>k)::bigint, 'استرجاع بعد إغلاق الشهر — طلب '||left(o.id::text,8), 'refund_after_close', rf.id);
      update public.commission_entries set credit_note_id = v_cn where refund_id = rf.id and credit_note_id = '00000000-0000-0000-0000-000000000000'
        and order_item_id in (select a.order_item_id from public.commission_entries a where a.invoice_id = k::uuid and a.kind='accrual');
    end if;
  end loop;
  update public.order_refunds set commission_reversed = true where id = rf.id;
end $$;

-- ---------------------------------------------------------------- invoice computation, issuing, status
create or replace function private.supplier_available_credit(p_supplier uuid, p_exclude uuid) returns bigint
language sql stable security definer set search_path='' as $$
  select greatest(0,
    coalesce((select sum(i.credit_generated_halalas + greatest(0, i.paid_halalas + i.credited_halalas - i.total_halalas))
              from public.commission_invoices i where i.supplier_id=p_supplier and i.status <> 'draft' and i.id is distinct from p_exclude),0)
    - coalesce((select sum(i.credits_applied_halalas) from public.commission_invoices i where i.supplier_id=p_supplier and i.status <> 'draft' and i.id is distinct from p_exclude),0)) $$;

create or replace function private.recompute_invoice(p_invoice uuid) returns void
language plpgsql security definer set search_path='' as $$
declare inv public.commission_invoices; s private.finance_settings := private.fin(); a record; v_sub bigint; v_vat bigint; v_credit bigint; v_raw bigint;
begin
  select * into inv from public.commission_invoices where id=p_invoice for update;
  if inv.status <> 'draft' then return; end if;
  select count(distinct order_id) filter (where kind='accrual') as orders,
         coalesce(sum(gross_original_halalas) filter (where kind='accrual'),0) as gross,
         coalesce(sum(base_commission_halalas) filter (where kind='accrual'),0) as base,
         coalesce(sum(markup_commission_halalas) filter (where kind='accrual'),0) as markup,
         coalesce(sum(total_commission_halalas) filter (where kind='reversal'),0) as adj,
         coalesce(jsonb_agg(distinct left(order_id::text,8)),'[]'::jsonb) as refs
  into a from public.commission_entries where invoice_id=p_invoice;
  v_sub := a.base + a.markup + a.adj;
  v_vat := case when s.platform_vat_registered then round(greatest(v_sub,0)::numeric * s.vat_rate_bp / 10000)::bigint else 0 end;
  v_credit := least(private.supplier_available_credit(inv.supplier_id, p_invoice), greatest(v_sub + v_vat, 0));
  v_raw := v_sub + v_vat - v_credit;
  update public.commission_invoices set order_count=a.orders, gross_original_halalas=a.gross, base_commission_halalas=a.base, markup_commission_halalas=a.markup,
    adjustments_halalas=a.adj, subtotal_halalas=v_sub, vat_rate_bp=case when s.platform_vat_registered then s.vat_rate_bp else 0 end, vat_halalas=v_vat,
    credits_applied_halalas=v_credit, total_halalas=greatest(v_raw,0), credit_generated_halalas=greatest(-v_raw,0), order_refs=a.refs
  where id=p_invoice;
end $$;

create or replace function private.refresh_invoice_status(p_invoice uuid) returns text
language plpgsql security definer set search_path='' as $$
declare inv public.commission_invoices; v_bal bigint; v_new text;
begin
  select * into inv from public.commission_invoices where id=p_invoice for update;
  if inv.status in ('draft','cancelled') then return inv.status; end if;
  v_bal := inv.total_halalas - inv.paid_halalas - inv.credited_halalas;
  if v_bal <= 0 then
    v_new := case when inv.paid_halalas = 0 and inv.total_halalas > 0 and inv.credited_halalas >= inv.total_halalas then 'cancelled' else 'paid' end;
  elsif private.ksa_today() > inv.due_date then v_new := 'overdue';
  elsif inv.paid_halalas > 0 or inv.credited_halalas > 0 then v_new := 'partially_paid';
  else v_new := 'issued'; end if;
  update public.commission_invoices set status=v_new,
    paid_at=case when v_new='paid' then coalesce(paid_at, now()) else paid_at end,
    overdue_since=case when v_new='overdue' then coalesce(overdue_since, private.ksa_today()) when v_new in ('paid','cancelled') then overdue_since else overdue_since end
  where id=p_invoice;
  if v_new is distinct from inv.status then
    perform private.fin_audit('invoice', p_invoice::text, 'status_'||v_new, jsonb_build_object('status',inv.status), jsonb_build_object('status',v_new,'balance',v_bal));
  end if;
  return v_new;
end $$;

create or replace function private.zatca_tlv(p_seller text, p_vat text, p_ts timestamptz, p_total text, p_vat_amount text) returns text
language plpgsql immutable set search_path='' as $$
declare out bytea := ''::bytea; vals text[] := array[p_seller, p_vat, to_char(p_ts at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'), p_total, p_vat_amount]; i int; b bytea;
begin
  for i in 1..5 loop
    b := convert_to(coalesce(vals[i],''), 'UTF8');
    out := out || decode(lpad(to_hex(i),2,'0'),'hex') || decode(lpad(to_hex(length(b)),2,'0'),'hex') || b;
  end loop;
  return encode(out, 'base64');
end $$;

create or replace function private.issue_invoice(p_invoice uuid) returns text
language plpgsql security definer set search_path='' as $$
declare inv public.commission_invoices; s private.finance_settings := private.fin(); pp public.supplier_payment_profiles; sup public.suppliers;
  v_no text; v_due date; v_sup jsonb; v_plat jsonb; v_now timestamptz := now();
begin
  perform private.recompute_invoice(p_invoice);
  select * into inv from public.commission_invoices where id=p_invoice for update;
  if inv.status <> 'draft' then return inv.status; end if;
  if s.platform_iban is null or s.platform_bank_name is null or s.platform_account_holder is null then
    raise exception 'set the platform bank account (IBAN, bank, account holder) in finance settings before issuing invoices'; end if;
  select * into sup from public.suppliers where id=inv.supplier_id;
  select * into pp from public.supplier_payment_profiles where supplier_id=inv.supplier_id;
  v_no := private.next_doc_no('invoice', inv.period_month);
  v_due := (inv.period_month + interval '1 month')::date + (s.invoice_due_day - 1);
  v_sup := jsonb_build_object('name', sup.name, 'legal_name', coalesce(pp.legal_name, sup.name), 'cr_number', pp.cr_number, 'vat_number', pp.tax_number,
    'entity_type', coalesce(pp.entity_type, sup.entity_type), 'address', sup.national_address, 'iban_masked', private.mask_iban(pp.iban));
  v_plat := jsonb_build_object('legal_name', s.platform_legal_name, 'cr_number', s.platform_cr_number, 'vat_registered', s.platform_vat_registered,
    'vat_number', s.platform_vat_number, 'address', s.platform_address, 'bank_name', s.platform_bank_name, 'iban', s.platform_iban, 'account_holder', s.platform_account_holder);
  update public.commission_invoices set invoice_no=v_no, status='issued', issue_date=private.ksa_today(), due_date=v_due, issued_at=v_now,
    supplier_snapshot=v_sup, platform_snapshot=v_plat,
    snapshot_sha256=encode(sha256(convert_to(jsonb_build_object('no',v_no,'supplier',v_sup,'platform',v_plat,'period',inv.period_month,'total',inv.total_halalas,
      'vat',inv.vat_halalas,'base',inv.base_commission_halalas,'markup',inv.markup_commission_halalas,'adj',inv.adjustments_halalas,'refs',inv.order_refs)::text,'UTF8')),'hex'),
    zatca_qr_tlv=case when s.platform_vat_registered then private.zatca_tlv(s.platform_legal_name, s.platform_vat_number, v_now,
      to_char(inv.total_halalas/100.0,'FM9999999990.00'), to_char(inv.vat_halalas/100.0,'FM9999999990.00')) end
  where id=p_invoice;
  perform private.refresh_invoice_status(p_invoice);
  perform private.fin_audit('invoice', p_invoice::text, 'issued', null, jsonb_build_object('invoice_no', v_no, 'total', inv.total_halalas, 'due_date', v_due));
  perform private.notify_supplier(inv.supplier_id, 'invoice_issued', 'فاتورة عمولات جديدة '||v_no,
    'صدرت فاتورة عمولات شهر '||to_char(inv.period_month,'YYYY-MM')||' بمبلغ '||to_char(inv.total_halalas/100.0,'FM9999999990.00')||' ر.س، تاريخ الاستحقاق '||v_due,
    'invoice', p_invoice::text, 'issued:'||p_invoice);
  return 'issued';
end $$;

-- Close a calendar month: one invoice per supplier per period (unique), never duplicated.
create or replace function private.close_billing_period(p_month date, p_issue boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_month date := date_trunc('month', p_month)::date; r record; v_inv uuid; v_status text; n_created int := 0; n_issued int := 0; v_err text; errs jsonb := '[]'::jsonb;
begin
  if v_month >= private.ksa_month(now()) then raise exception 'only completed months can be closed'; end if;
  perform pg_advisory_xact_lock(hashtextextended('close-period:'||v_month::text, 0));
  for r in select distinct supplier_id from public.commission_entries
           where invoice_id is null and credit_note_id is null and period_month <= v_month loop
    select id, status into v_inv, v_status from public.commission_invoices where supplier_id=r.supplier_id and period_month=v_month;
    if v_inv is null then
      insert into public.commission_invoices(supplier_id, period_month, period_start, period_end)
      values (r.supplier_id, v_month, v_month, (v_month + interval '1 month - 1 day')::date) returning id into v_inv;
      v_status := 'draft'; n_created := n_created + 1;
    end if;
    if v_status = 'draft' then
      update public.commission_entries set invoice_id=v_inv
       where supplier_id=r.supplier_id and invoice_id is null and credit_note_id is null and period_month <= v_month;
      perform private.recompute_invoice(v_inv);
    end if;
  end loop;
  if p_issue then
    for r in select id from public.commission_invoices where period_month=v_month and status='draft' loop
      begin perform private.issue_invoice(r.id); n_issued := n_issued + 1;
      exception when others then v_err := sqlerrm; errs := errs || jsonb_build_object('invoice', r.id, 'error', v_err);
        perform private.raise_finance_alert('invoice_issue_failed','critical',null,null,r.id,'تعذّر إصدار فاتورة: '||v_err,null,'issuefail:'||r.id);
      end;
    end loop;
  end if;
  return jsonb_build_object('month', v_month, 'created', n_created, 'issued', n_issued, 'errors', errs);
end $$;

-- Daily, idempotent billing job: close last month, update statuses, reminders, overdue warnings.
create or replace function private.run_billing_jobs() returns jsonb
language plpgsql security definer set search_path='' as $$
declare s private.finance_settings := private.fin(); v_prev date := (private.ksa_month(now()) - interval '1 month')::date; r record; v_close jsonb;
  n_due int := 0; n_overdue int := 0; v_status text; v_days int;
begin
  v_close := private.close_billing_period(v_prev, s.auto_issue_invoices);
  for r in select * from public.commission_invoices where status in ('issued','partially_paid','overdue') loop
    v_status := private.refresh_invoice_status(r.id);
    if v_status in ('issued','partially_paid') and r.due_date - private.ksa_today() between 0 and s.reminder_days_before then
      perform private.notify_supplier(r.supplier_id, 'invoice_due_soon', 'تذكير: استحقاق فاتورة '||r.invoice_no,
        'يستحق سداد الفاتورة '||r.invoice_no||' في '||r.due_date||'. المتبقي '||to_char((r.total_halalas-r.paid_halalas-r.credited_halalas)/100.0,'FM9999999990.00')||' ر.س.',
        'invoice', r.id::text, 'due:'||r.id); n_due := n_due + 1;
    elsif v_status = 'overdue' then
      v_days := private.ksa_today() - r.due_date;
      perform private.notify_supplier(r.supplier_id, 'invoice_overdue', 'إنذار: فاتورة متأخرة '||r.invoice_no,
        'تجاوزت الفاتورة '||r.invoice_no||' تاريخ استحقاقها ('||r.due_date||'). وفق عقد المورد يحق للمنصة تعليق استقبال الطلبات الجديدة بعد '||s.suspension_grace_days||' يوماً من الاستحقاق دون المساس بالطلبات القائمة.',
        'invoice', r.id::text, 'overdue:'||r.id);
      perform private.raise_finance_alert('invoice_overdue','warning',r.supplier_id,null,r.id,'فاتورة متأخرة '||r.invoice_no,null,'overdue:'||r.id);
      if v_days >= s.suspension_grace_days then
        perform private.raise_finance_alert('suspension_eligible','critical',r.supplier_id,null,r.id,
          'مورد متأخر تجاوز مهلة الإنذار — يمكن تعليق استقبال الطلبات الجديدة',jsonb_build_object('days_overdue',v_days),'suspend:'||r.id);
      end if;
      n_overdue := n_overdue + 1;
    end if;
  end loop;
  return jsonb_build_object('close', v_close, 'due_reminders', n_due, 'overdue', n_overdue, 'ran_at', now());
end $$;

-- ---------------------------------------------------------------- supplier RPCs
create or replace function public.supplier_finance_summary(p_supplier uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_month date := private.ksa_month(now()); s private.finance_settings := private.fin();
begin
  perform private.require_supplier_owner(p_supplier);
  return jsonb_build_object(
    'commission_rate_bp', s.commission_rate_bp, 'commission_on_markup', s.commission_on_markup, 'due_day', s.invoice_due_day,
    'current_month', v_month,
    'month', (select jsonb_build_object('orders', count(distinct order_id) filter (where kind='accrual'),
        'original_sales_halalas', coalesce(sum(gross_original_halalas),0), 'sales_net_halalas', coalesce(sum(sale_net_halalas),0),
        'base_commission_halalas', coalesce(sum(base_commission_halalas),0), 'markup_commission_halalas', coalesce(sum(markup_commission_halalas),0),
        'total_commission_halalas', coalesce(sum(total_commission_halalas),0))
      from public.commission_entries where supplier_id=p_supplier and period_month=v_month),
    'unbilled_commission_halalas', (select coalesce(sum(total_commission_halalas),0) from public.commission_entries
      where supplier_id=p_supplier and invoice_id is null and credit_note_id is null),
    'completed_sales', (select jsonb_build_object('orders', count(*), 'total_halalas', coalesce(sum(payable_halalas - refunded_halalas),0))
      from public.orders where supplier_id=p_supplier and status='delivered' and payment_status='paid'),
    'paid_orders_pending_delivery', (select count(*) from public.orders where supplier_id=p_supplier and payment_status='paid' and status not in ('delivered','cancelled')),
    'outstanding_halalas', (select coalesce(sum(greatest(total_halalas-paid_halalas-credited_halalas,0)),0) from public.commission_invoices
      where supplier_id=p_supplier and status in ('issued','partially_paid','overdue')),
    'overdue_halalas', (select coalesce(sum(greatest(total_halalas-paid_halalas-credited_halalas,0)),0) from public.commission_invoices
      where supplier_id=p_supplier and status='overdue'),
    'available_credit_halalas', private.supplier_available_credit(p_supplier, null),
    'orders_suspended', (select orders_suspended from public.suppliers where id=p_supplier),
    'unread_notifications', (select count(*) from public.supplier_notifications where supplier_id=p_supplier and read_at is null));
end $$;

create or replace function public.supplier_invoices(p_supplier uuid) returns setof public.commission_invoices
language plpgsql stable security definer set search_path='' as $$
begin perform private.require_supplier_owner(p_supplier);
  return query select * from public.commission_invoices where supplier_id=p_supplier and status<>'draft' order by period_month desc; end $$;

create or replace function public.supplier_commission_lines(p_supplier uuid, p_month date default null) returns table(
  order_id uuid, order_ref text, delivered_at timestamptz, product_name text, quantity integer, original_unit_halalas integer, sale_unit_halalas integer,
  kind text, gross_original_halalas bigint, base_commission_halalas bigint, markup_commission_halalas bigint, total_commission_halalas bigint, period_month date, invoice_no text)
language plpgsql stable security definer set search_path='' as $$
begin
  perform private.require_supplier_owner(p_supplier);
  return query select e.order_id, left(e.order_id::text,8), o.delivered_at, i.product_name, i.quantity, i.supplier_price_halalas, i.unit_price_halalas,
    e.kind, e.gross_original_halalas, e.base_commission_halalas, e.markup_commission_halalas, e.total_commission_halalas, e.period_month,
    (select inv.invoice_no from public.commission_invoices inv where inv.id=e.invoice_id)
  from public.commission_entries e join public.orders o on o.id=e.order_id left join public.order_items i on i.id=e.order_item_id
  where e.supplier_id=p_supplier and (p_month is null or e.period_month=date_trunc('month',p_month)::date)
  order by e.created_at desc limit 1000;
end $$;

create or replace function public.supplier_payments_and_credits(p_supplier uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin perform private.require_supplier_owner(p_supplier);
  return jsonb_build_object(
    'payments', (select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('invoice_no',(select invoice_no from public.commission_invoices i where i.id=p.invoice_id)) order by p.submitted_at desc),'[]'::jsonb)
                 from public.invoice_payments p where p.supplier_id=p_supplier),
    'credit_notes', (select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('invoice_no',(select invoice_no from public.commission_invoices i where i.id=c.invoice_id)) order by c.issued_at desc),'[]'::jsonb)
                 from public.commission_credit_notes c where c.supplier_id=p_supplier));
end $$;

create or replace function public.supplier_submit_invoice_payment(p_invoice uuid, p_amount_halalas bigint, p_reference text, p_transfer_date date, p_proof_path text)
returns uuid language plpgsql security definer set search_path='' as $$
declare inv public.commission_invoices; v_id uuid;
begin
  select * into inv from public.commission_invoices where id=p_invoice;
  if not found then raise exception 'invoice not found'; end if;
  perform private.require_supplier_owner(inv.supplier_id);
  if inv.status not in ('issued','partially_paid','overdue') then raise exception 'invoice is not awaiting payment'; end if;
  if p_amount_halalas is null or p_amount_halalas <= 0 then raise exception 'invalid amount'; end if;
  if p_proof_path is not null and (storage.foldername(p_proof_path))[1] is distinct from auth.uid()::text then raise exception 'invalid proof file'; end if;
  insert into public.invoice_payments(invoice_id, supplier_id, amount_halalas, method, reference, transfer_date, proof_path, submitted_by)
  values (p_invoice, inv.supplier_id, p_amount_halalas, 'bank_transfer', btrim(p_reference), p_transfer_date, nullif(p_proof_path,''), auth.uid()) returning id into v_id;
  perform private.raise_finance_alert('payment_submitted','info',inv.supplier_id,null,p_invoice,'إشعار تحويل بانتظار التحقق للفاتورة '||inv.invoice_no,
    jsonb_build_object('payment',v_id,'amount',p_amount_halalas),'pay:'||v_id);
  return v_id;
end $$;

create or replace function public.supplier_mark_notifications_read(p_supplier uuid) returns void
language plpgsql security definer set search_path='' as $$
begin perform private.require_supplier_owner(p_supplier);
  update public.supplier_notifications set read_at=now() where supplier_id=p_supplier and read_at is null; end $$;

-- Full invoice document for printing/PDF (supplier owner or operator).
create or replace function public.invoice_document(p_invoice uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare inv public.commission_invoices;
begin
  select * into inv from public.commission_invoices where id=p_invoice;
  if not found then raise exception 'invoice not found'; end if;
  if not private.is_platform_operator() then
    perform private.require_supplier_owner(inv.supplier_id);
    if inv.status = 'draft' then raise exception 'invoice not issued'; end if;
  end if;
  return jsonb_build_object('invoice', to_jsonb(inv),
    'balance_halalas', inv.total_halalas - inv.paid_halalas - inv.credited_halalas,
    'orders', (select coalesce(jsonb_agg(x order by x->>'delivered_at'),'[]'::jsonb) from (
       select jsonb_build_object('order_ref', left(e.order_id::text,8), 'delivered_at', max(o.delivered_at),
         'original_halalas', sum(e.gross_original_halalas) filter (where e.kind='accrual'),
         'base_halalas', sum(e.base_commission_halalas) filter (where e.kind='accrual'),
         'markup_halalas', sum(e.markup_commission_halalas) filter (where e.kind='accrual'),
         'adjustment_halalas', coalesce(sum(e.total_commission_halalas) filter (where e.kind='reversal'),0)) x
       from public.commission_entries e join public.orders o on o.id=e.order_id where e.invoice_id=p_invoice group by e.order_id) t),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('amount_halalas',amount_halalas,'reference',reference,'transfer_date',transfer_date,'verified_at',verified_at) order by verified_at),'[]'::jsonb)
                 from public.invoice_payments where invoice_id=p_invoice and status='verified'),
    'credit_notes', (select coalesce(jsonb_agg(jsonb_build_object('no',credit_note_no,'total_halalas',total_halalas,'reason',reason,'issued_at',issued_at) order by issued_at),'[]'::jsonb)
                 from public.commission_credit_notes where invoice_id=p_invoice));
end $$;

-- ---------------------------------------------------------------- admin RPCs
create or replace function public.admin_invoices(p_status text default null, p_month date default null) returns table(invoice jsonb, supplier_name text, balance_halalas bigint, days_overdue integer)
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select to_jsonb(i), s.name, i.total_halalas - i.paid_halalas - i.credited_halalas,
    case when i.status='overdue' then private.ksa_today() - i.due_date else 0 end
  from public.commission_invoices i join public.suppliers s on s.id=i.supplier_id
  where (p_status is null or i.status=p_status) and (p_month is null or i.period_month=date_trunc('month',p_month)::date)
  order by i.period_month desc, s.name;
end $$;

create or replace function public.admin_close_period(p_month date, p_issue boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v jsonb;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  v := private.close_billing_period(p_month, p_issue);
  perform private.admin_log('billing_close_period', 'period', p_month::text);
  return v;
end $$;

create or replace function public.admin_issue_invoice(p_invoice uuid) returns text
language plpgsql security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  perform private.admin_log('invoice_issue', 'invoice', p_invoice::text);
  return private.issue_invoice(p_invoice);
end $$;

create or replace function public.admin_review_invoice_payment(p_payment uuid, p_approve boolean, p_note text default null) returns text
language plpgsql security definer set search_path='' as $$
declare p public.invoice_payments; inv public.commission_invoices; v_status text;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into p from public.invoice_payments where id=p_payment for update;
  if not found or p.status <> 'submitted' then raise exception 'payment not awaiting review'; end if;
  if not p_approve and nullif(btrim(p_note),'') is null then raise exception 'rejection reason required'; end if;
  update public.invoice_payments set status=case when p_approve then 'verified' else 'rejected' end, verified_by=auth.uid(), verified_at=now(), review_note=p_note where id=p_payment;
  select * into inv from public.commission_invoices where id=p.invoice_id for update;
  if p_approve then
    update public.commission_invoices set paid_halalas = paid_halalas + p.amount_halalas where id=p.invoice_id;
    v_status := private.refresh_invoice_status(p.invoice_id);
  end if;
  perform private.fin_audit('payment', p_payment::text, case when p_approve then 'verified' else 'rejected' end, null,
    jsonb_build_object('invoice', inv.invoice_no, 'amount', p.amount_halalas, 'reference', p.reference, 'note', p_note));
  perform private.notify_supplier(p.supplier_id, case when p_approve then 'payment_verified' else 'payment_rejected' end,
    case when p_approve then 'تم اعتماد سدادك للفاتورة '||inv.invoice_no else 'تعذّر اعتماد التحويل للفاتورة '||inv.invoice_no end,
    case when p_approve then 'تم التحقق من التحويل بمبلغ '||to_char(p.amount_halalas/100.0,'FM9999999990.00')||' ر.س.' else coalesce(p_note,'') end,
    'invoice', p.invoice_id::text, null);
  update private.finance_alerts set resolved_at=now(), resolved_by=auth.uid() where dedupe_key='pay:'||p_payment;
  return coalesce(v_status, inv.status);
end $$;

-- Admin-recorded payment (e.g. matched against a bank statement); verified on entry.
create or replace function public.admin_record_invoice_payment(p_invoice uuid, p_amount_halalas bigint, p_reference text, p_transfer_date date) returns text
language plpgsql security definer set search_path='' as $$
declare inv public.commission_invoices; v_id uuid;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into inv from public.commission_invoices where id=p_invoice for update;
  if not found or inv.status not in ('issued','partially_paid','overdue') then raise exception 'invoice is not awaiting payment'; end if;
  insert into public.invoice_payments(invoice_id, supplier_id, amount_halalas, method, reference, transfer_date, status, submitted_by, verified_by, verified_at, review_note)
  values (p_invoice, inv.supplier_id, p_amount_halalas, 'bank_transfer', btrim(p_reference), p_transfer_date, 'verified', auth.uid(), auth.uid(), now(), 'مطابقة إدارية')
  returning id into v_id;
  update public.commission_invoices set paid_halalas = paid_halalas + p_amount_halalas where id=p_invoice;
  perform private.fin_audit('payment', v_id::text, 'recorded_verified', null, jsonb_build_object('invoice', inv.invoice_no, 'amount', p_amount_halalas, 'reference', p_reference));
  perform private.notify_supplier(inv.supplier_id, 'payment_verified', 'تم تسجيل سداد للفاتورة '||inv.invoice_no,
    'تم اعتماد مبلغ '||to_char(p_amount_halalas/100.0,'FM9999999990.00')||' ر.س.', 'invoice', p_invoice::text, null);
  return private.refresh_invoice_status(p_invoice);
end $$;

create or replace function public.admin_issue_credit_note(p_invoice uuid, p_amount_halalas bigint, p_reason text, p_source text default 'settlement') returns uuid
language plpgsql security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_source not in ('settlement','admin_adjustment') then raise exception 'invalid credit note source'; end if;
  if nullif(btrim(p_reason),'') is null then raise exception 'reason required'; end if;
  return private.issue_credit_note(p_invoice, p_amount_halalas, btrim(p_reason), p_source, null);
end $$;

create or replace function public.admin_set_orders_suspended(p_supplier uuid, p_suspend boolean, p_reason text, p_force boolean default false) returns void
language plpgsql security definer set search_path='' as $$
declare s private.finance_settings := private.fin(); v_eligible boolean;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if p_suspend then
    if nullif(btrim(p_reason),'') is null then raise exception 'suspension reason required'; end if;
    v_eligible := exists(select 1 from public.commission_invoices i where i.supplier_id=p_supplier and i.status='overdue'
      and private.ksa_today() - i.due_date >= s.suspension_grace_days
      and exists(select 1 from public.supplier_notifications n where n.dedupe_key='overdue:'||i.id));
    if not v_eligible and not p_force then
      raise exception 'supplier has no overdue invoice past the warning period (% days); use force with a documented reason', s.suspension_grace_days; end if;
  end if;
  update public.suppliers set orders_suspended=p_suspend, orders_suspended_reason=case when p_suspend then btrim(p_reason) end,
    orders_suspended_at=case when p_suspend then now() end where id=p_supplier;
  perform private.fin_audit('supplier', p_supplier::text, case when p_suspend then 'orders_suspended' else 'orders_resumed' end, null,
    jsonb_build_object('reason', p_reason, 'forced', p_force));
  perform private.notify_supplier(p_supplier, case when p_suspend then 'orders_suspended' else 'orders_resumed' end,
    case when p_suspend then 'تم تعليق استقبال الطلبات الجديدة' else 'تم استئناف استقبال الطلبات' end,
    case when p_suspend then 'السبب: '||p_reason||'. الطلبات القائمة وسجلاتك المالية غير متأثرة.' else 'يمكن للعملاء الطلب منك مجدداً.' end, 'supplier', p_supplier::text, null);
end $$;

create or replace function public.admin_finance_alerts(p_include_resolved boolean default false) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select to_jsonb(a) || jsonb_build_object('supplier_name',(select s.name from public.suppliers s where s.id=a.supplier_id))
  from private.finance_alerts a where p_include_resolved or a.resolved_at is null order by a.created_at desc limit 500;
end $$;

create or replace function public.admin_resolve_finance_alert(p_alert uuid, p_note text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  update private.finance_alerts set resolved_at=now(), resolved_by=auth.uid(), resolution_note=p_note where id=p_alert and resolved_at is null;
end $$;

create or replace function public.admin_invoice_payments(p_status text default 'submitted') returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select to_jsonb(p) || jsonb_build_object('invoice_no', i.invoice_no, 'supplier_name', s.name, 'invoice_balance', i.total_halalas-i.paid_halalas-i.credited_halalas)
  from public.invoice_payments p join public.commission_invoices i on i.id=p.invoice_id join public.suppliers s on s.id=p.supplier_id
  where p_status is null or p.status=p_status order by p.submitted_at desc limit 500;
end $$;

create or replace function public.admin_finance_report(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return jsonb_build_object(
    'by_month', (select coalesce(jsonb_agg(x order by x->>'month'),'[]'::jsonb) from (
      select jsonb_build_object('month', e.period_month,
        'orders', count(distinct e.order_id) filter (where e.kind='accrual'),
        'original_sales_halalas', sum(e.gross_original_halalas), 'sales_net_halalas', sum(e.sale_net_halalas),
        'base_commission_halalas', sum(e.base_commission_halalas), 'markup_commission_halalas', sum(e.markup_commission_halalas),
        'total_commission_halalas', sum(e.total_commission_halalas)) x
      from public.commission_entries e where e.period_month between date_trunc('month',p_from)::date and date_trunc('month',p_to)::date group by e.period_month) m),
    'by_supplier', (select coalesce(jsonb_agg(x),'[]'::jsonb) from (
      select jsonb_build_object('supplier', s.name, 'supplier_id', s.id,
        'total_commission_halalas', coalesce(sum(e.total_commission_halalas),0),
        'outstanding_halalas', (select coalesce(sum(greatest(i.total_halalas-i.paid_halalas-i.credited_halalas,0)),0) from public.commission_invoices i
                                where i.supplier_id=s.id and i.status in ('issued','partially_paid','overdue'))) x
      from public.suppliers s left join public.commission_entries e on e.supplier_id=s.id
        and e.period_month between date_trunc('month',p_from)::date and date_trunc('month',p_to)::date
      group by s.id, s.name) t),
    'invoices', (select jsonb_build_object('issued_halalas', coalesce(sum(total_halalas),0), 'paid_halalas', coalesce(sum(paid_halalas),0),
        'credited_halalas', coalesce(sum(credited_halalas),0), 'outstanding_halalas', coalesce(sum(greatest(total_halalas-paid_halalas-credited_halalas,0)),0),
        'overdue_count', count(*) filter (where status='overdue'))
      from public.commission_invoices where status<>'draft' and period_month between date_trunc('month',p_from)::date and date_trunc('month',p_to)::date),
    'refunds_halalas', (select coalesce(sum(amount_halalas),0) from public.order_refunds where status='succeeded' and processed_at::date between p_from and p_to));
end $$;

create or replace function public.admin_disputes(p_open_only boolean default true) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select to_jsonb(d) || jsonb_build_object('supplier_name',(select s.name from public.suppliers s where s.id=d.supplier_id),
    'order_total',(select o.payable_halalas from public.orders o where o.id=d.order_id))
  from public.payment_disputes d where not p_open_only or d.status in ('open','under_review') order by d.created_at desc;
end $$;

create or replace function public.run_billing_jobs() returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'') <> 'service_role' and not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return private.run_billing_jobs();
end $$;

revoke all on function public.supplier_finance_summary(uuid), public.supplier_invoices(uuid), public.supplier_commission_lines(uuid,date),
  public.supplier_payments_and_credits(uuid), public.supplier_submit_invoice_payment(uuid,bigint,text,date,text), public.supplier_mark_notifications_read(uuid),
  public.invoice_document(uuid), public.admin_invoices(text,date), public.admin_close_period(date,boolean), public.admin_issue_invoice(uuid),
  public.admin_review_invoice_payment(uuid,boolean,text), public.admin_record_invoice_payment(uuid,bigint,text,date), public.admin_issue_credit_note(uuid,bigint,text,text),
  public.admin_set_orders_suspended(uuid,boolean,text,boolean), public.admin_finance_alerts(boolean), public.admin_resolve_finance_alert(uuid,text),
  public.admin_invoice_payments(text), public.admin_finance_report(date,date), public.admin_disputes(boolean), public.run_billing_jobs() from public, anon;
grant execute on function public.supplier_finance_summary(uuid), public.supplier_invoices(uuid), public.supplier_commission_lines(uuid,date),
  public.supplier_payments_and_credits(uuid), public.supplier_submit_invoice_payment(uuid,bigint,text,date,text), public.supplier_mark_notifications_read(uuid),
  public.invoice_document(uuid), public.admin_invoices(text,date), public.admin_close_period(date,boolean), public.admin_issue_invoice(uuid),
  public.admin_review_invoice_payment(uuid,boolean,text), public.admin_record_invoice_payment(uuid,bigint,text,date), public.admin_issue_credit_note(uuid,bigint,text,text),
  public.admin_set_orders_suspended(uuid,boolean,text,boolean), public.admin_finance_alerts(boolean), public.admin_resolve_finance_alert(uuid,text),
  public.admin_invoice_payments(text), public.admin_finance_report(date,date), public.admin_disputes(boolean) to authenticated;
grant execute on function public.run_billing_jobs() to authenticated, service_role;

-- Schedule the daily billing job where pg_cron is available (Supabase: enable the extension).
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('rawaa-billing-daily', '15 21 * * *', 'select private.run_billing_jobs()');  -- 00:15 Asia/Riyadh
  end if;
end $$;
