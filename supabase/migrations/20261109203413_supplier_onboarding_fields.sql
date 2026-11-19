-- Applied to production via MCP apply_migration; exported from session history for repo parity.
-- Expanded supplier onboarding fields (manager, national address, tax, extra docs).
alter table public.seller_applications
  add column if not exists manager_name text,
  add column if not exists manager_title text,
  add column if not exists email text,
  add column if not exists national_address text,
  add column if not exists tax_number text,
  add column if not exists authorization_doc_path text,
  add column if not exists license_doc_path text;

-- Supplier record carries its warehouse national address + tax number after approval.
alter table public.suppliers
  add column if not exists national_address text,
  add column if not exists tax_number text,
  add column if not exists warehouse_city text;

-- Per-supplier warehouse (their own isolated stock space, controlled from the supplier dashboard).
create table if not exists public.warehouses (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  name text not null default 'المستودع الرئيسي',
  national_address text,
  city text,
  created_at timestamptz not null default now()
);
alter table public.warehouses enable row level security;
create index if not exists warehouses_supplier_idx on public.warehouses(supplier_id);

-- Supplier manages only their own warehouse(s); operators can read all.
drop policy if exists warehouse_owner_all on public.warehouses;
create policy warehouse_owner_all on public.warehouses for all to authenticated
  using (private.owns_supplier(supplier_id) or (select private.is_platform_operator()))
  with check (private.owns_supplier(supplier_id));
drop policy if exists warehouse_verified on public.warehouses;
create policy warehouse_verified on public.warehouses as restrictive for all to authenticated
  using ((select private.has_verified_session())) with check ((select private.has_verified_session()));
