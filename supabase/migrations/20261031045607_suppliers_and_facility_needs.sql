-- Private commercial procurement planning, never a public donation request.
create table public.facility_needs (
 id uuid primary key default gen_random_uuid(),
 manager_id uuid not null references auth.users(id),
 facility_name text not null check(length(facility_name) between 2 and 160),
 city text not null check(city in ('makkah','madinah')),
 category text not null check(category in ('water','quran','supplies','food','equipment')),
 description text not null check(length(description) between 2 and 1000),
 quantity integer not null check(quantity between 1 and 10000),
 status text not null default 'open' check(status in ('open','fulfilled')),
 created_at timestamptz not null default now()
);
create index facility_needs_manager_idx on public.facility_needs(manager_id,created_at desc);
alter table public.facility_needs enable row level security;
revoke all on public.facility_needs from anon,authenticated;
grant select on public.facility_needs to authenticated;
grant insert(manager_id,facility_name,city,category,description,quantity) on public.facility_needs to authenticated;
grant update(quantity,status) on public.facility_needs to authenticated;
create policy need_read on public.facility_needs for select to authenticated using(manager_id=(select auth.uid()));
create policy need_create on public.facility_needs for insert to authenticated with check(manager_id=(select auth.uid()) and status='open');
create policy need_update on public.facility_needs for update to authenticated using(manager_id=(select auth.uid())) with check(manager_id=(select auth.uid()));
