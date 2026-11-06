-- Roles are provisioned by trusted operators, never by editable user metadata.
create table private.platform_operators(user_id uuid primary key references auth.users(id));
alter table private.platform_operators enable row level security;
revoke all on private.platform_operators from public,anon,authenticated;
create function private.is_platform_operator() returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from private.platform_operators where user_id=auth.uid())$$;
create function private.portal_access() returns jsonb language sql stable security definer set search_path='' as $$select jsonb_build_object('is_admin',private.is_platform_operator(),'is_supplier',auth.uid() is not null and exists(select 1 from public.suppliers where owner_id=auth.uid() and approval_status='approved'))$$;
create function public.my_portal_access() returns jsonb language sql security invoker set search_path='' as $$select private.portal_access()$$;
create function private.owns_supplier(p_supplier_id uuid) returns boolean language sql stable security definer set search_path='' as $$select auth.uid() is not null and exists(select 1 from public.suppliers where id=p_supplier_id and owner_id=auth.uid() and approval_status='approved')$$;
create policy operator_orders_read on public.orders for select to authenticated using((select private.is_platform_operator()));
create policy operator_items_read on public.order_items for select to authenticated using((select private.is_platform_operator()));
create policy operator_seller_read on public.seller_applications for select to authenticated using((select private.is_platform_operator()));
create policy operator_supplier_read on public.suppliers for select to authenticated using((select private.is_platform_operator()));
create policy operator_products_read on public.products for select to authenticated using((select private.is_platform_operator()) or private.owns_supplier(supplier_id));
create policy operator_quotes_read on public.quote_requests for select to authenticated using((select private.is_platform_operator()));
create policy operator_documents_read on storage.objects for select to authenticated using(bucket_id='seller-documents' and (select private.is_platform_operator()));
create function private.supplier_products() returns setof public.products language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 return query select p.* from public.products p join public.suppliers s on s.id=p.supplier_id where s.owner_id=auth.uid() and s.approval_status='approved' order by p.created_at desc;
end$$;
create function public.supplier_products() returns setof public.products language sql security invoker set search_path='' as $$select * from private.supplier_products()$$;
create function private.supplier_order_summaries() returns table(id uuid,created_at timestamptz,status text,city text,item_total_halalas bigint,quantity bigint,print_name boolean,beneficiary_name text)
language plpgsql stable security definer set search_path='' as $$begin
 if auth.uid() is null then raise exception 'authenticated user required' using errcode='42501';end if;
 return query select o.id,o.created_at,o.status,o.city,sum(i.unit_price_halalas::bigint*i.quantity)::bigint,sum(i.quantity)::bigint,o.print_name,case when o.print_name then o.beneficiary_name else null end
 from public.orders o join public.order_items i on i.order_id=o.id join public.products p on p.id=i.product_id join public.suppliers s on s.id=p.supplier_id
 where s.owner_id=auth.uid() and s.approval_status='approved'
 group by o.id order by o.created_at desc;
end$$;
create function public.supplier_order_summaries() returns table(id uuid,created_at timestamptz,status text,city text,item_total_halalas bigint,quantity bigint,print_name boolean,beneficiary_name text)
language sql security invoker set search_path='' as $$select * from private.supplier_order_summaries()$$;
create function private.set_printing_service_price(p_price_halalas integer) returns void language plpgsql security definer set search_path='' as $$begin
 if not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501';end if;
 if p_price_halalas is null or p_price_halalas not between 0 and 100000 then raise exception 'invalid printing price';end if;
 update public.checkout_services set price_halalas=p_price_halalas where code='name_printing';
end$$;
create function public.set_printing_service_price(p_price_halalas integer) returns void language sql security invoker set search_path='' as $$select private.set_printing_service_price(p_price_halalas)$$;
revoke all on function private.is_platform_operator(),private.portal_access(),private.owns_supplier(uuid),private.supplier_products(),private.supplier_order_summaries(),private.set_printing_service_price(integer) from public,anon;
grant execute on function private.is_platform_operator(),private.portal_access(),private.owns_supplier(uuid),private.supplier_products(),private.supplier_order_summaries(),private.set_printing_service_price(integer) to authenticated;
revoke all on function public.my_portal_access(),public.supplier_products(),public.supplier_order_summaries(),public.set_printing_service_price(integer) from public,anon;
grant execute on function public.my_portal_access(),public.supplier_products(),public.supplier_order_summaries(),public.set_printing_service_price(integer) to authenticated;
