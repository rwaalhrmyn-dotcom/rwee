-- Payment confirmation is a trusted operations action. This records a verified
-- external payment; it never charges a card or trusts a browser redirect.
alter table public.orders
 add column payment_status text not null default 'unpaid' check(payment_status in ('unpaid','paid')),
 add column paid_at timestamptz,
 add constraint payment_timestamp_consistent check((payment_status='paid' and paid_at is not null) or (payment_status='unpaid' and paid_at is null));
create table private.order_payments (
 order_id uuid primary key references public.orders(id),
 reference text not null unique check(length(btrim(reference)) between 6 and 160),
 amount_halalas bigint not null check(amount_halalas>0),
 verified_by uuid not null references auth.users(id),
 verified_at timestamptz not null default now()
);
create index order_payments_verifier_idx on private.order_payments(verified_by);
alter table private.order_payments enable row level security;
revoke all on private.order_payments from public,anon,authenticated;

create function private.delivery_has_video(p_delivery_id uuid) returns boolean
language sql stable security invoker set search_path='' as $$
 select exists(
  select 1 from public.delivery_evidence e
  join public.deliveries d on d.id=e.delivery_id
  join storage.objects f on f.bucket_id='delivery-evidence' and f.name=e.object_path and f.owner_id=e.uploaded_by::text
  where d.id=p_delivery_id and e.uploaded_by=d.courier_id and split_part(e.object_path,'/',1)=d.order_id::text and e.object_path ~ '[.](mp4|webm)$'
 )
$$;

create function private.require_paid_receipt() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and old.payment_status='paid' and (
  new.payment_status<>'paid' or new.paid_at is distinct from old.paid_at or
  new.subtotal_halalas+new.customization_fee_halalas-new.loyalty_discount_halalas+coalesce(new.delivery_halalas,0) <> old.total_halalas+coalesce(old.delivery_halalas,0)
 ) then raise exception 'verified payment is immutable'; end if;
 if new.payment_status='paid' and not exists(select 1 from private.order_payments p where p.order_id=new.id and p.verified_at=new.paid_at and p.amount_halalas=new.subtotal_halalas+new.customization_fee_halalas-new.loyalty_discount_halalas+coalesce(new.delivery_halalas,0)) then
  raise exception 'verified payment required';
 end if;
 if new.status='delivered' then
  if new.payment_status<>'paid' then raise exception 'payment required before delivery completion'; end if;
  if not exists(select 1 from public.deliveries d where d.order_id=new.id and d.status='approved' and d.recipient_confirmed_at is not null and d.reviewed_at is not null and private.delivery_has_video(d.id)) then
   raise exception 'documented receipt required before completion';
  end if;
 end if;
 return new;
end $$;
create trigger require_paid_receipt before insert or update on public.orders for each row execute function private.require_paid_receipt();

create function private.record_verified_payment(p_order_id uuid,p_reference text) returns void
language plpgsql security definer set search_path='' as $$
declare v_order public.orders%rowtype; v_reference text:=btrim(p_reference); v_time timestamptz:=now(); v_existing text;
begin
 if auth.uid() is null or not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501'; end if;
 if v_reference is null or length(v_reference) not between 6 and 160 then raise exception 'invalid payment reference'; end if;
 select * into v_order from public.orders where id=p_order_id for update;
 if not found or v_order.status='cancelled' then raise exception 'order unavailable for payment confirmation'; end if;
 select reference into v_existing from private.order_payments where order_id=p_order_id;
 if v_existing is not null then
  if v_existing=v_reference then return; end if;
  raise exception 'payment already recorded';
 end if;
 insert into private.order_payments(order_id,reference,amount_halalas,verified_by,verified_at)
 values(p_order_id,v_reference,v_order.total_halalas+coalesce(v_order.delivery_halalas,0),auth.uid(),v_time);
 update public.orders set payment_status='paid',paid_at=v_time where id=p_order_id;
end $$;
create function public.record_verified_payment(p_order_id uuid,p_reference text) returns void
language sql security invoker set search_path='' as $$ select private.record_verified_payment(p_order_id,p_reference) $$;

-- Couriers may only upload evidence for a paid, non-cancelled assigned order.
drop policy evidence_upload on storage.objects;
create policy evidence_upload on storage.objects for insert to authenticated with check(
 bucket_id='delivery-evidence' and name ~ '[.](mp4|webm)$' and exists(
 select 1 from public.deliveries d join public.orders o on o.id=d.order_id
 where d.order_id::text=(storage.foldername(name))[1] and d.courier_id=(select auth.uid()) and d.status in ('scheduled','submitted','changes_requested') and o.payment_status='paid' and o.status<>'cancelled'
 ));

create or replace function private.submit_delivery_evidence(p_delivery_id uuid,p_object_path text) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_delivery public.deliveries%rowtype; v_id uuid;
begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found or v_delivery.courier_id<>auth.uid() or v_delivery.status='approved' then raise exception 'permission denied' using errcode='42501'; end if;
 if not exists(select 1 from public.orders where id=v_delivery.order_id and payment_status='paid' and status<>'cancelled') then raise exception 'verified payment required'; end if;
 if p_object_path is null or p_object_path !~ '[.](mp4|webm)$' or split_part(p_object_path,'/',1)<>v_delivery.order_id::text or not exists(select 1 from storage.objects where bucket_id='delivery-evidence' and name=p_object_path and owner_id=auth.uid()::text) then raise exception 'invalid evidence object'; end if;
 insert into public.delivery_evidence(delivery_id,uploaded_by,object_path) values(p_delivery_id,auth.uid(),p_object_path) returning id into v_id;
 update public.deliveries set status='submitted',recipient_confirmed_at=null,reviewed_at=null where id=p_delivery_id;
 return v_id;
end $$;

create or replace function private.confirm_delivery_receipt(p_delivery_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_delivery public.deliveries%rowtype;
begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found or v_delivery.status<>'submitted' or not exists(select 1 from public.orders o where o.id=v_delivery.order_id and o.customer_id=auth.uid()) then raise exception 'permission denied' using errcode='42501'; end if;
 if not exists(select 1 from public.orders where id=v_delivery.order_id and payment_status='paid' and status<>'cancelled') then raise exception 'verified payment required'; end if;
 if not private.delivery_has_video(p_delivery_id) then raise exception 'delivery video required'; end if;
 update public.deliveries set recipient_confirmed_at=coalesce(recipient_confirmed_at,now()) where id=p_delivery_id;
end $$;

create or replace function private.review_delivery(p_delivery_id uuid,p_decision text) returns void
language plpgsql security definer set search_path='' as $$
declare v_delivery public.deliveries%rowtype;
begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501'; end if;
 select * into v_delivery from public.deliveries where id=p_delivery_id for update;
 if not found or v_delivery.reviewer_id<>auth.uid() or v_delivery.courier_id=auth.uid() or v_delivery.status<>'submitted' then raise exception 'permission denied' using errcode='42501'; end if;
 if p_decision is null or p_decision not in ('approved','changes_requested') then raise exception 'invalid decision'; end if;
 if not exists(select 1 from public.orders where id=v_delivery.order_id and payment_status='paid' and status<>'cancelled') then raise exception 'verified payment required'; end if;
 if not private.delivery_has_video(p_delivery_id) then raise exception 'delivery video required'; end if;
 if p_decision='approved' and v_delivery.recipient_confirmed_at is null then raise exception 'recipient confirmation required'; end if;
 update public.deliveries set status=p_decision,reviewed_at=now() where id=p_delivery_id;
 if p_decision='approved' then update public.orders set status='delivered' where id=v_delivery.order_id; end if;
end $$;

revoke all on function private.delivery_has_video(uuid),private.require_paid_receipt() from public,anon,authenticated;
revoke all on function private.record_verified_payment(uuid,text),public.record_verified_payment(uuid,text) from public,anon;
grant execute on function private.record_verified_payment(uuid,text),public.record_verified_payment(uuid,text) to authenticated;
