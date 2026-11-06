-- Loyalty is earned on delivered net product value, never on supplier services.
-- Balances are server-owned; redemption and order placement share a transaction.
create table public.loyalty_settings (
 id boolean primary key default true check(id),
 enabled boolean not null default true
);
insert into public.loyalty_settings(id,enabled) values(true,true);
alter table public.loyalty_settings enable row level security;
revoke all on public.loyalty_settings from public,anon,authenticated;
grant select on public.loyalty_settings to anon,authenticated;
create policy loyalty_settings_read on public.loyalty_settings for select to anon,authenticated using(true);

create table private.loyalty_accounts (
 customer_id uuid primary key references auth.users(id),
 balance bigint not null default 0,
 lifetime bigint not null default 0 check(lifetime>=0)
);
create table private.loyalty_transactions (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id),
 order_id uuid not null references public.orders(id),
 kind text not null check(kind in ('earn','redeem','refund','reverse')),
 points bigint not null check(points<>0),
 created_at timestamptz not null default now(),
 unique(order_id,kind),
 check((kind in ('earn','refund') and points>0) or (kind in ('redeem','reverse') and points<0))
);
create index loyalty_transactions_customer_created_idx on private.loyalty_transactions(customer_id,created_at desc,id desc);
alter table private.loyalty_accounts enable row level security;
alter table private.loyalty_transactions enable row level security;
revoke all on private.loyalty_accounts,private.loyalty_transactions from public,anon,authenticated;

alter table public.orders
 add column loyalty_discount_halalas bigint not null default 0 check(loyalty_discount_halalas>=0 and loyalty_discount_halalas*4<=subtotal_halalas),
 add column loyalty_eligible boolean not null default false,
 drop column total_halalas;
alter table public.orders add column total_halalas bigint generated always as (subtotal_halalas+customization_fee_halalas-loyalty_discount_halalas) stored;

create function private.prepare_loyalty_order() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='INSERT' then
  new.loyalty_eligible := coalesce((select enabled from public.loyalty_settings where id),false);
 elsif old.status='cancelled' and new.status<>'cancelled' then
  raise exception 'cancelled order cannot be reopened';
 end if;
 return new;
end $$;
create trigger prepare_loyalty_order before insert or update of status on public.orders for each row execute function private.prepare_loyalty_order();

create function private.apply_order_loyalty() returns trigger
language plpgsql security definer set search_path='' as $$
declare v_points bigint; v_redeemed bigint; v_id uuid;
begin
 if new.status=old.status then return new; end if;
 if new.status not in ('delivered','cancelled') then return new; end if;
 insert into private.loyalty_accounts(customer_id) values(new.customer_id) on conflict do nothing;
 -- Serialize all balance changes for a customer, including concurrent orders.
 perform 1 from private.loyalty_accounts where customer_id=new.customer_id for update;
 if new.status='delivered' and new.loyalty_eligible and coalesce((select enabled from public.loyalty_settings where id),false) then
  v_points := (new.subtotal_halalas-new.loyalty_discount_halalas)/100;
  if v_points>0 then
   insert into private.loyalty_transactions(customer_id,order_id,kind,points) values(new.customer_id,new.id,'earn',v_points) on conflict(order_id,kind) do nothing returning id into v_id;
   if v_id is not null then update private.loyalty_accounts set balance=balance+v_points,lifetime=lifetime+v_points where customer_id=new.customer_id; end if;
  end if;
 elsif new.status='cancelled' then
  select points into v_points from private.loyalty_transactions where order_id=new.id and kind='earn';
  if coalesce(v_points,0)>0 then
   v_id:=null;
   insert into private.loyalty_transactions(customer_id,order_id,kind,points) values(new.customer_id,new.id,'reverse',-v_points) on conflict(order_id,kind) do nothing returning id into v_id;
   if v_id is not null then update private.loyalty_accounts set balance=balance-v_points,lifetime=greatest(0,lifetime-v_points) where customer_id=new.customer_id; end if;
  end if;
  select -points into v_redeemed from private.loyalty_transactions where order_id=new.id and kind='redeem';
  if coalesce(v_redeemed,0)>0 then
   v_id:=null;
   insert into private.loyalty_transactions(customer_id,order_id,kind,points) values(new.customer_id,new.id,'refund',v_redeemed) on conflict(order_id,kind) do nothing returning id into v_id;
   if v_id is not null then update private.loyalty_accounts set balance=balance+v_redeemed where customer_id=new.customer_id; end if;
  end if;
 end if;
 return new;
end $$;
create trigger apply_order_loyalty after update of status on public.orders for each row execute function private.apply_order_loyalty();

create function private.loyalty_wallet() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_wallet jsonb;
begin
 if v_user is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select jsonb_build_object('balance',a.balance,'lifetime',a.lifetime) into v_wallet from private.loyalty_accounts a where a.customer_id=v_user;
 return coalesce(v_wallet,jsonb_build_object('balance',0,'lifetime',0)) || jsonb_build_object('transactions',coalesce((
  select jsonb_agg(row_to_json(x) order by x.created_at desc,x.id desc) from (
   select id,order_id,kind,points,created_at from private.loyalty_transactions where customer_id=v_user order by created_at desc,id desc limit 20
  ) x
 ),'[]'::jsonb));
end $$;
create function public.my_loyalty_wallet() returns jsonb language sql stable security invoker set search_path='' as $$ select private.loyalty_wallet() $$;

create function private.set_loyalty_enabled(p_enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501'; end if;
 if p_enabled is null then raise exception 'enabled is required'; end if;
 update public.loyalty_settings set enabled=p_enabled where id;
end $$;
create function public.set_loyalty_enabled(p_enabled boolean) returns void language sql security invoker set search_path='' as $$ select private.set_loyalty_enabled(p_enabled) $$;

create function private.place_loyalty_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid,p_customization jsonb,p_loyalty_points integer) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_id uuid; v_subtotal bigint; v_balance bigint; v_enabled boolean;
begin
 if v_user is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 if p_request_id is null then raise exception 'request id required'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||p_request_id::text,0));
 select id into v_id from public.orders where customer_id=v_user and request_id=p_request_id;
 if v_id is not null then return v_id; end if;
 if p_loyalty_points is null or p_loyalty_points not in (0,100,300,500) then raise exception 'invalid loyalty reward'; end if;
 select enabled into v_enabled from public.loyalty_settings where id for share;
 if p_loyalty_points>0 and not coalesce(v_enabled,false) then raise exception 'loyalty program paused'; end if;
 v_id := private.place_customized_order(p_items,p_city,p_address,p_recipient_name,p_phone,p_request_id,p_customization);
 if p_loyalty_points>0 then
  select subtotal_halalas into v_subtotal from public.orders where id=v_id;
  if p_loyalty_points::bigint*5*4>v_subtotal then raise exception 'loyalty discount exceeds product limit'; end if;
  insert into private.loyalty_accounts(customer_id) values(v_user) on conflict do nothing;
  select balance into v_balance from private.loyalty_accounts where customer_id=v_user for update;
  if v_balance<p_loyalty_points then raise exception 'insufficient loyalty points'; end if;
  update private.loyalty_accounts set balance=balance-p_loyalty_points where customer_id=v_user;
  insert into private.loyalty_transactions(customer_id,order_id,kind,points) values(v_user,v_id,'redeem',-p_loyalty_points);
  update public.orders set loyalty_discount_halalas=p_loyalty_points::bigint*5 where id=v_id;
 end if;
 return v_id;
end $$;
create function public.place_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid,p_customization jsonb,p_loyalty_points integer) returns uuid
language sql security invoker set search_path='' as $$ select private.place_loyalty_order(p_items,p_city,p_address,p_recipient_name,p_phone,p_request_id,p_customization,p_loyalty_points) $$;

-- Trigger functions are internal only. Public RPCs are invoker wrappers; every
-- private entrypoint checks the caller or operates on a trusted order trigger.
revoke all on function private.prepare_loyalty_order(),private.apply_order_loyalty() from public,anon,authenticated;
revoke all on function private.loyalty_wallet(),private.set_loyalty_enabled(boolean),private.place_loyalty_order(jsonb,text,text,text,text,uuid,jsonb,integer) from public,anon;
grant execute on function private.loyalty_wallet(),private.set_loyalty_enabled(boolean),private.place_loyalty_order(jsonb,text,text,text,text,uuid,jsonb,integer) to authenticated;
revoke all on function public.my_loyalty_wallet(),public.set_loyalty_enabled(boolean),public.place_order(jsonb,text,text,text,text,uuid,jsonb,integer) from public,anon;
grant execute on function public.my_loyalty_wallet(),public.set_loyalty_enabled(boolean),public.place_order(jsonb,text,text,text,text,uuid,jsonb,integer) to authenticated;
