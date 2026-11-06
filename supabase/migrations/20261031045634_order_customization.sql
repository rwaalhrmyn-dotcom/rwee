-- Optional purchase personalization. This is a product/service order, not a
-- fundraising balance or payment transaction. Price is authoritative in SQL.
create table public.checkout_services (
 code text primary key check(code='name_printing'),
 price_halalas integer not null check(price_halalas>=0),
 active boolean not null default true
);
insert into public.checkout_services(code,price_halalas) values('name_printing',1000);
alter table public.checkout_services enable row level security;
revoke all on public.checkout_services from anon,authenticated;
grant select on public.checkout_services to anon,authenticated;
create policy service_price_read on public.checkout_services for select to anon,authenticated using(active);

alter table public.orders
 add column intent text not null default 'standard' check(intent in ('standard','sadaqah')),
 add column beneficiary_name text check(length(beneficiary_name) between 1 and 100),
 add column print_name boolean not null default false,
 add column print_phrase_key text check(print_phrase_key in ('on_behalf','prayer','gift','custom')),
 add column print_custom_phrase text check(length(print_custom_phrase) between 1 and 160),
 add column print_language text check(print_language in ('ar','en','ur','id')),
 add column customization_fee_halalas integer not null default 0 check(customization_fee_halalas>=0),
 add column total_halalas bigint generated always as (subtotal_halalas+customization_fee_halalas) stored,
 add constraint valid_print_customization check(
  (not print_name and customization_fee_halalas=0 and print_phrase_key is null and print_custom_phrase is null and print_language is null)
  or (print_name and intent='sadaqah' and beneficiary_name is not null and print_phrase_key is not null and print_language is not null and (print_phrase_key<>'custom' or print_custom_phrase is not null))
 );

create function private.place_customized_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid,p_customization jsonb) returns uuid
language plpgsql security definer set search_path='' as $$
declare
 v_user uuid:=auth.uid();v_id uuid;v_intent text;v_name text;v_print boolean;v_phrase text;v_custom text;v_language text;v_fee integer:=0;
begin
 if v_user is null then raise exception 'authenticated user required' using errcode='42501';end if;
 if p_request_id is null then raise exception 'request id required';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||p_request_id::text,0));
 select id into v_id from public.orders where customer_id=v_user and request_id=p_request_id;
 if v_id is not null then return v_id;end if;
 if p_customization is null or jsonb_typeof(p_customization)<>'object' then raise exception 'invalid customization';end if;
 v_intent:=coalesce(p_customization->>'intent','standard');
 if v_intent not in ('standard','sadaqah') then raise exception 'invalid order intent';end if;
 if p_customization ? 'print_name' and jsonb_typeof(p_customization->'print_name')<>'boolean' then raise exception 'invalid print option';end if;
 v_print:=coalesce((p_customization->>'print_name')::boolean,false);
 if p_customization ? 'beneficiary_name' and jsonb_typeof(p_customization->'beneficiary_name') not in ('string','null') then raise exception 'invalid beneficiary name';end if;
 v_name:=nullif(btrim(p_customization->>'beneficiary_name'),'');
 if length(v_name)>100 then raise exception 'beneficiary name too long';end if;
 if v_intent='standard' then
  if v_print then raise exception 'printing requires sadaqah purchase';end if;
  v_name:=null;
 end if;
 if v_print then
  if v_name is null then raise exception 'beneficiary name required for printing';end if;
  v_phrase:=p_customization->>'phrase_key';v_language:=p_customization->>'print_language';
  if v_phrase is null or v_phrase not in ('on_behalf','prayer','gift','custom') then raise exception 'invalid print phrase';end if;
  if v_language is null or v_language not in ('ar','en','ur','id') then raise exception 'invalid print language';end if;
  if v_phrase='custom' then
   if jsonb_typeof(p_customization->'custom_phrase')<>'string' then raise exception 'invalid custom phrase';end if;
   v_custom:=nullif(btrim(p_customization->>'custom_phrase'),'');
   if v_custom is null or length(v_custom)>160 then raise exception 'custom phrase required (1-160 characters)';end if;
  end if;
  select price_halalas into v_fee from public.checkout_services where code='name_printing' and active for share;
  if not found then raise exception 'printing service unavailable';end if;
 end if;
 v_id:=private.place_order(p_items,p_city,p_address,p_recipient_name,p_phone,p_request_id);
 update public.orders set intent=v_intent,beneficiary_name=v_name,print_name=v_print,print_phrase_key=v_phrase,print_custom_phrase=v_custom,print_language=v_language,customization_fee_halalas=v_fee where id=v_id;
 return v_id;
end $$;
create function public.place_order(p_items jsonb,p_city text,p_address text,p_recipient_name text,p_phone text,p_request_id uuid,p_customization jsonb) returns uuid
language sql security invoker set search_path='' as $$ select private.place_customized_order(p_items,p_city,p_address,p_recipient_name,p_phone,p_request_id,p_customization) $$;
revoke all on function private.place_customized_order(jsonb,text,text,text,text,uuid,jsonb) from public,anon;
grant execute on function private.place_customized_order(jsonb,text,text,text,text,uuid,jsonb) to authenticated;
revoke all on function public.place_order(jsonb,text,text,text,text,uuid,jsonb) from public,anon;
grant execute on function public.place_order(jsonb,text,text,text,text,uuid,jsonb) to authenticated;
