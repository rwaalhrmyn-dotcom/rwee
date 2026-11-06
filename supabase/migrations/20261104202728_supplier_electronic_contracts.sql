-- Additive supplier contract acceptance. No payment, inventory, supplier access
-- gate or existing records are changed. Contract versions and receipts are
-- append-only through these authenticated entry points.
create table public.supplier_contract_versions (
 version_id text primary key check(version_id ~ '^[a-z0-9-]{6,80}$'),
 body_ar text not null check(length(body_ar) between 100 and 20000),
 body_sha256 text not null check(body_sha256=encode(sha256(convert_to(body_ar,'UTF8')),'hex')),
 published boolean not null default false,
 is_current boolean not null default false,
 published_at timestamptz,
 unique(version_id,body_sha256),
 check(not is_current or published),
 check(not published or published_at is not null)
);
create unique index supplier_contract_one_current on public.supplier_contract_versions(is_current) where is_current;
alter table public.supplier_contract_versions enable row level security;
revoke all on public.supplier_contract_versions from public,anon,authenticated,service_role;
grant select on public.supplier_contract_versions to anon,authenticated;
create policy published_contract_read on public.supplier_contract_versions for select to anon,authenticated using(published);

create table private.supplier_contract_acceptances (
 id uuid primary key default gen_random_uuid(),
 supplier_id uuid not null references public.suppliers(id),
 version_id text not null,
 body_sha256 text not null check(body_sha256 ~ '^[0-9a-f]{64}$'),
 signer_id uuid not null references auth.users(id),
 signer_full_name text not null check(length(btrim(signer_full_name)) between 3 and 160 and signer_full_name !~ '[[:cntrl:]]'),
 session_id uuid not null, -- audit only; no FK preventing session revocation
 request_id uuid not null,
 accepted_at timestamptz not null default now(),
 unique(supplier_id,version_id,signer_id),
 unique(signer_id,request_id),
 foreign key(version_id,body_sha256) references public.supplier_contract_versions(version_id,body_sha256)
);
create index supplier_contract_acceptances_version_idx on private.supplier_contract_acceptances(version_id);
create index supplier_contract_acceptances_signer_idx on private.supplier_contract_acceptances(signer_id,accepted_at desc);
alter table private.supplier_contract_acceptances enable row level security;
revoke all on private.supplier_contract_acceptances from public,anon,authenticated,service_role;

create function private.lock_published_contract() returns trigger language plpgsql set search_path='' as $$begin
 if old.published and (tg_op='DELETE' or new.version_id is distinct from old.version_id or new.body_ar is distinct from old.body_ar or new.body_sha256 is distinct from old.body_sha256 or not new.published or new.published_at is distinct from old.published_at) then
  raise exception 'published contract text is immutable';
 end if;
 if tg_op='DELETE' then return old;end if;return new;
end $$;
create trigger lock_published_contract before update or delete on public.supplier_contract_versions for each row execute function private.lock_published_contract();
create function private.lock_contract_acceptance() returns trigger language plpgsql set search_path='' as $$begin
 raise exception 'contract acceptance is append only';
end $$;
create trigger lock_contract_acceptance before update or delete on private.supplier_contract_acceptances for each row execute function private.lock_contract_acceptance();

create function private.supplier_contract_receipt(a private.supplier_contract_acceptances) returns jsonb language sql immutable security invoker set search_path='' as $$
 select jsonb_build_object('id',a.id,'supplier_id',a.supplier_id,'version_id',a.version_id,'body_sha256',a.body_sha256,'signer_full_name',a.signer_full_name,'accepted_at',a.accepted_at)
$$;
create function private.my_supplier_contract(p_supplier uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.supplier_contract_versions%rowtype;a private.supplier_contract_acceptances%rowtype;
begin
 perform private.assert_account_session();
 if not exists(select 1 from public.suppliers where id=p_supplier and owner_id=auth.uid() and approval_status='approved') then raise exception 'permission denied' using errcode='42501';end if;
 select * into c from public.supplier_contract_versions where published and is_current;
 if not found then raise exception 'supplier contract unavailable';end if;
 select * into a from private.supplier_contract_acceptances where supplier_id=p_supplier and version_id=c.version_id and signer_id=auth.uid();
 return jsonb_build_object('contract',to_jsonb(c),'acceptance',case when a.id is null then null else private.supplier_contract_receipt(a) end);
end $$;

create function private.accept_supplier_contract(p_supplier uuid,p_version text,p_hash text,p_signer_name text,p_request uuid,p_agreed boolean) returns jsonb
language plpgsql security definer set search_path='' as $$
declare c public.supplier_contract_versions%rowtype;a private.supplier_contract_acceptances%rowtype;v_user uuid:=auth.uid();v_name text:=btrim(p_signer_name);
begin
 perform private.assert_account_session();
 if p_agreed is distinct from true or p_request is null or v_name is null or length(v_name) not between 3 and 160 or v_name ~ '[[:cntrl:]]' then raise exception 'explicit contract consent and signer name required';end if;
 perform 1 from public.suppliers where id=p_supplier and owner_id=v_user and approval_status='approved' for share;
 if not found then raise exception 'permission denied' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('contract-request:'||v_user::text||':'||p_request::text,0));
 perform pg_advisory_xact_lock(hashtextextended('contract-supplier:'||p_supplier::text||':'||v_user::text,0));
 select * into c from public.supplier_contract_versions where version_id=p_version and published and is_current for share;
 if not found or p_hash is distinct from c.body_sha256 then raise exception 'contract version changed; reload before accepting' using errcode='40001';end if;
 select * into a from private.supplier_contract_acceptances where signer_id=v_user and request_id=p_request;
 if found then
  if a.supplier_id<>p_supplier or a.version_id<>p_version or a.body_sha256<>p_hash or a.signer_full_name<>v_name then raise exception 'contract request conflict';end if;
  return private.supplier_contract_receipt(a);
 end if;
 select * into a from private.supplier_contract_acceptances where supplier_id=p_supplier and version_id=p_version and signer_id=v_user;
 if found then
  if a.signer_full_name<>v_name then raise exception 'contract already accepted with different signer details';end if;
  return private.supplier_contract_receipt(a);
 end if;
 insert into private.supplier_contract_acceptances(supplier_id,version_id,body_sha256,signer_id,signer_full_name,session_id,request_id)
 values(p_supplier,c.version_id,c.body_sha256,v_user,v_name,(auth.jwt()->>'session_id')::uuid,p_request) returning * into a;
 return private.supplier_contract_receipt(a);
end $$;

create function private.admin_supplier_contract_acceptances() returns table(id uuid,supplier_id uuid,supplier_name text,version_id text,body_sha256 text,signer_full_name text,accepted_at timestamptz)
language plpgsql stable security definer set search_path='' as $$begin
 perform private.assert_account_session();
 if not private.is_platform_operator() then raise exception 'permission denied' using errcode='42501';end if;
 return query select a.id,a.supplier_id,s.name,a.version_id,a.body_sha256,a.signer_full_name,a.accepted_at from private.supplier_contract_acceptances a join public.suppliers s on s.id=a.supplier_id order by a.accepted_at desc,a.id;
end $$;
create function public.my_supplier_contract(p_supplier uuid) returns jsonb language sql stable security invoker set search_path='' as $$select private.my_supplier_contract(p_supplier)$$;
create function public.accept_supplier_contract(p_supplier uuid,p_version text,p_hash text,p_signer_name text,p_request uuid,p_agreed boolean) returns jsonb language sql security invoker set search_path='' as $$select private.accept_supplier_contract(p_supplier,p_version,p_hash,p_signer_name,p_request,p_agreed)$$;
create function public.admin_supplier_contract_acceptances() returns table(id uuid,supplier_id uuid,supplier_name text,version_id text,body_sha256 text,signer_full_name text,accepted_at timestamptz) language sql stable security invoker set search_path='' as $$select * from private.admin_supplier_contract_acceptances()$$;
revoke all on function private.lock_published_contract(),private.lock_contract_acceptance(),private.supplier_contract_receipt(private.supplier_contract_acceptances),private.my_supplier_contract(uuid),private.accept_supplier_contract(uuid,text,text,text,uuid,boolean),private.admin_supplier_contract_acceptances(),public.my_supplier_contract(uuid),public.accept_supplier_contract(uuid,text,text,text,uuid,boolean),public.admin_supplier_contract_acceptances() from public,anon,authenticated;
grant execute on function private.my_supplier_contract(uuid),private.accept_supplier_contract(uuid,text,text,text,uuid,boolean),private.admin_supplier_contract_acceptances(),public.my_supplier_contract(uuid),public.accept_supplier_contract(uuid,text,text,text,uuid,boolean),public.admin_supplier_contract_acceptances() to authenticated;

insert into public.supplier_contract_versions(version_id,body_ar,body_sha256,published,is_current,published_at) values('supplier-b2b-2026-11-v1',$contract$عقد المورد الإلكتروني — رواء الحرمين
الإصدار: supplier-b2b-2026-11-v1

١. طبيعة الخدمة والأطراف
رواء الحرمين منصة B2B لعرض المنتجات وطلبات التوريد بين الموردين والجهات المشترية. يقر الموقّع بأنه مخول بقبول هذا العقد عن منشأة المورد المرتبطة بحسابه، وبصحة بيانات المنشأة والمنتجات والمخزون والأسعار التي يقدمها.

٢. المنتجات والتسعير
يلتزم المورد بعرض منتجات مسموح بتداولها، ووصفها وتسعيرها وتحديث مخزونها بدقة، وتنفيذ الطلب المعتمد وفق الكمية والمواصفات المتفق عليها. تُعرض تفاصيل السعر ورسوم الخدمات الاختيارية والشحن والضرائب والخصومات المعتمدة قبل اعتماد الطلب، ولا تُضاف مبالغ مجهولة أو تقديرية بوصفها رسومًا مؤكدة.

٣. الدفع وعمولة المنصة
نموذج المنصة يعتمد تسوية مباشرة للمورد عبر حساب Tap Marketplace مستقل ومعتمد خاص برواء الحرمين، وفق اعتماد المزود ودورة تسويته. عمولة المنصة ٥٪ من إجمالي الطلب، منفصلة عن رسوم معالجة الدفع. لا تمثل اختبارات Sandbox دفعًا أو تسوية فعلية، ولا يثبت ظهور وسيلة الدفع جاهزيتها قبل تفعيلها والتحقق منها.

٤. الطباعة الاختيارية
الطباعة خدمة اختيارية برسوم معروضة يتحملها المشتري للمورد عند اختيارها واعتمادها ضمن الطلب. يشمل ذلك خيار «أهدي من تحب» عند توفره. لا تعني الهدية أو الطباعة جمع تبرعات أو إدارة أرصدة تبرعية.

٥. التنفيذ وتوثيق الاستلام
لا يُعد الطلب مدفوعًا اعتمادًا على رسالة من المتصفح وحدها؛ يعتمد التأكيد على سجل دفع موثوق. بعد الدفع، يلزم فيديو الاستلام وتأكيد المستلم واعتماد المراجع المخول قبل اكتمال دورة التسليم. لا يكفي إشعار الناقل بالتسليم وحده، ويلتزم المورد بصحة الأدلة وعدم انتحال قبول المستلم أو المراجع.

٦. البيانات والخصوصية
تُستخدم بيانات الطلب للغرض اللازم لتنفيذه والتواصل المصرح بشأنه. تبقى أدلة الاستلام في مساحة خاصة ويقتصر الوصول إليها على الأطراف المخولة، ولا تُنشر للعامة. يحافظ المورد على سرية بيانات العملاء وبيانات الدخول والمفاتيح، ولا يشاركها خارج أغراض الطلب المصرح بها.

٧. الإلغاء والمرتجعات والنزاعات
تُعالج الإلغاءات والمرتجعات والنزاعات وفق المتطلبات النظامية والسياسات المعلنة للطلب المعني، مع حفظ المراجع والسجلات. لا يغير هذا العقد حالة دفعة أو يمنح صلاحية استرجاع أو حجز ناقل لمستخدم غير مخول.

٨. القبول الإلكتروني
بإدخال الاسم الكامل والتأكيد الصريح، يقر الموقّع بقراءة هذا الإصدار وقبوله وبصلاحيته لتمثيل المورد. يُحفظ حساب الموقّع والمورد والإصدار وبصمة النص والاسم وتاريخ القبول الخادمي ومرجع الجلسة في سجل خاص. لا يُقبل العقد تلقائيًا ولا تُستبدل موافقة محفوظة عند صدور نسخة جديدة؛ تتطلب النسخة الجديدة قبولًا مستقلًا.
$contract$,'038b1b20963f7c19b564fcd700b09b493410130e3f0d25abb407bdbac6ee1dfe',true,true,now());
