-- Applied to production via MCP apply_migration; exported from session history for repo parity.
-- supplier opt-in to self-delivery
alter table public.suppliers add column if not exists accepts_delivery boolean not null default false;
alter table public.seller_applications add column if not exists accepts_delivery boolean not null default false;

-- order delivery method
alter table public.orders add column if not exists delivery_method text;
do $$ begin
  if not exists (select 1 from pg_constraint where conname='orders_delivery_method_chk') then
    alter table public.orders add constraint orders_delivery_method_chk
      check (delivery_method is null or delivery_method in ('supplier','oto'));
  end if;
end $$;

-- configurable delivery fees (single row), halalas
create table if not exists private.delivery_settings (
  id boolean primary key default true,
  supplier_delivery_halalas int not null default 25,
  oto_waybill_halalas int not null default 800,
  updated_at timestamptz not null default now(),
  constraint delivery_settings_singleton check (id)
);
insert into private.delivery_settings(id) values(true) on conflict do nothing;
