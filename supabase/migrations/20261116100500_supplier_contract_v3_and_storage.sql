-- Supplier agreement v3 ("اتفاقية انضمام المورد والبيع عبر منصة رواء الحرمين").
-- Inserted as an UNPUBLISHED draft pending legal review. It becomes mandatory only when
-- an operator records the legal review and publishes it; suppliers then re-accept
-- (previous acceptance stays valid during contract_reaccept_grace_days).

alter table public.supplier_contract_versions add column if not exists title text;
alter table public.supplier_contract_versions add column if not exists legal_review_status text not null default 'approved'
  check (legal_review_status in ('draft','pending_review','approved'));
alter table public.supplier_contract_versions add column if not exists legal_reviewer text;
alter table public.supplier_contract_versions add column if not exists legal_reviewed_at timestamptz;
alter table public.supplier_contract_versions add column if not exists legal_review_note text;
alter table public.supplier_contract_versions add column if not exists created_at timestamptz not null default now();

insert into public.supplier_contract_versions(version_id, title, body_ar, body_sha256, published, is_current, legal_review_status)
select v.version_id, v.title, v.body, encode(sha256(convert_to(v.body,'UTF8')),'hex'), false, false, 'pending_review'
from (select 'rw-v3-2026-11-direct-pay'::text as version_id,
  'اتفاقية انضمام المورد والبيع عبر منصة رواء الحرمين'::text as title,
$CT$اتفاقية انضمام المورد والبيع عبر منصة رواء الحرمين

تُبرم هذه الاتفاقية إلكترونياً بين منصة «رواء الحرمين» (ويشار إليها بـ«المنصة») والمنشأة المسجلة بصفتها مورداً، سواء كانت مصنعاً أو موزعاً أو تاجراً (ويشار إليها بـ«المورد»).

البند الأول: طبيعة العلاقة
تعمل رواء الحرمين كمنصة إلكترونية وسيطة لتسويق المنتجات وإدارة عمليات البيع والطلبات.
يبقى المورد البائع الفعلي للمنتجات والمسؤول عن ملكيتها ومطابقتها وجودتها والتزاماته النظامية المتعلقة ببيعها.

البند الثاني: أسعار المنتجات
يحدد المورد السعر الأصلي لمنتجاته داخل المنصة.
ويوافق المورد على منح رواء الحرمين صلاحية تحديد سعر العرض النهائي للعميل بإضافة هامش تسويقي أو زيادة سعرية على السعر الأصلي، وفق قواعد التسعير المعتمدة.

البند الثالث: العمولة الأساسية
يلتزم المورد بسداد عمولة أساسية لمنصة رواء الحرمين بنسبة 5% من قيمة المنتجات الأصلية المباعة في العمليات المكتملة والمؤهلة للاستحقاق، قبل ضريبة القيمة المضافة ورسوم الشحن.

البند الرابع: الزيادات السعرية
يقر المورد ويوافق على أن أي مبالغ أو زيادات سعرية تضيفها إدارة رواء الحرمين على سعر المنتج الأصلي، سواء كانت نسبة مئوية أو مبلغاً ثابتاً، تعتبر عمولة تسويقية إضافية مستحقة للمنصة.
وتضاف هذه العمولة إلى نسبة العمولة الأساسية، ولا تعد بديلاً عنها.
ويستلم المورد حصيلة المبيعات وفق آلية الدفع المعتمدة، ثم يلتزم بسداد جميع عمولات المنصة المستحقة عليه.
ولا تُحتسب العمولة الأساسية على الزيادة السعرية مرة ثانية ما لم يُتفق على ذلك صراحةً بموجب تعديل معتمد لهذه الاتفاقية.

البند الخامس: السداد الشهري
يلتزم المورد بسداد كامل العمولات الأساسية والإضافية المستحقة لمنصة رواء الحرمين عن المبيعات المكتملة خلال كل شهر ميلادي.
وتصدر المنصة فاتورة بالمستحقات في بداية الشهر التالي، ويكون آخر موعد للسداد هو اليوم الخامس من ذلك الشهر.
ولا يُعد التحويل البنكي سداداً إلا بعد التحقق منه واعتماده من المنصة.

البند السادس: التأخر عن السداد
في حال عدم السداد خلال المدة المحددة، يحق للمنصة إرسال إشعارات ومطالبات مالية، واتخاذ الإجراءات التعاقدية المناسبة، بما فيها تعليق استقبال طلبات جديدة بعد الإنذار، دون الإخلال بحقوق العملاء أو الطلبات السابقة.

البند السابع: الضرائب والفواتير
يتحمل كل طرف التزاماته الضريبية وفق الأنظمة السعودية وطبيعة التوريدات التي يقدمها.
يصدر المورد فواتير مبيعات المنتجات باسمه وفق وضعه النظامي، وتصدر رواء مستندات عمولاتها باسمها، ولا تضيف ضريبة قيمة مضافة على خدماتها إلا إذا كانت ملزمة بذلك نظاماً.
يجب فصل القيمة الأصلية للمنتج والزيادة السعرية والعمولات والضرائب محاسبياً، وتحديد المعالجة الضريبية النهائية وفق العلاقة التعاقدية الفعلية.

البند الثامن: الإقرار والموافقة الإلكترونية
يقر المورد بأنه قرأ العقد وفهم جميع أحكامه، بما فيها العمولة الأساسية والزيادات السعرية والالتزام بالسداد الشهري.
ولا يُسمح له بإكمال التسجيل إلا بعد الموافقة الصريحة.
وتحتفظ المنصة برقم إصدار العقد وتاريخ ووقت الموافقة ومعرّف المستخدم وسجل التحقق ونسخة العقد المعتمدة.

البند التاسع: التعديلات
أي تعديل على نسبة العمولة أو أساس احتسابها أو الالتزامات المالية التعاقدية يستلزم إشعار المورد والحصول على موافقته الإلكترونية الجديدة عند الحاجة، ولا يطبق بأثر رجعي على الطلبات المكتملة.

البند العاشر: الأنظمة وتسوية النزاعات
تخضع هذه الاتفاقية للأنظمة المعمول بها في المملكة العربية السعودية، وتحدد النسخة النهائية المعتمدة آلية تسوية النزاعات والاختصاص القضائي وفق مراجعة قانونية.$CT$::text as body) v
on conflict (version_id) do nothing;

create or replace function public.admin_contract_versions() returns table(version_id text, title text, published boolean, is_current boolean, published_at timestamptz,
  legal_review_status text, legal_reviewer text, legal_reviewed_at timestamptz, body_sha256 text, acceptances bigint, created_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select v.version_id, v.title, v.published, v.is_current, v.published_at, v.legal_review_status, v.legal_reviewer, v.legal_reviewed_at,
    v.body_sha256, (select count(*) from private.supplier_contract_acceptances a where a.version_id=v.version_id), v.created_at
  from public.supplier_contract_versions v order by v.created_at desc;
end $$;

create or replace function public.admin_contract_text(p_version text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return (select to_jsonb(v) from public.supplier_contract_versions v where v.version_id=p_version);
end $$;

create or replace function public.admin_save_contract_draft(p_version text, p_title text, p_body text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v public.supplier_contract_versions;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into v from public.supplier_contract_versions where version_id=p_version for update;
  if v.published then raise exception 'published contracts are immutable; create a new version'; end if;
  if v.version_id is null then
    insert into public.supplier_contract_versions(version_id, title, body_ar, body_sha256, legal_review_status)
    values (p_version, p_title, p_body, encode(sha256(convert_to(p_body,'UTF8')),'hex'), 'pending_review') returning * into v;
  else
    update public.supplier_contract_versions set title=p_title, body_ar=p_body, body_sha256=encode(sha256(convert_to(p_body,'UTF8')),'hex'),
      legal_review_status='pending_review', legal_reviewer=null, legal_reviewed_at=null where version_id=p_version returning * into v;
  end if;
  perform private.fin_audit('contract', p_version, 'draft_saved', null, jsonb_build_object('sha256', v.body_sha256, 'title', p_title));
  return to_jsonb(v);
end $$;

create or replace function public.admin_record_contract_legal_review(p_version text, p_reviewer text, p_note text) returns void
language plpgsql security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  if length(btrim(coalesce(p_reviewer,''))) < 3 then raise exception 'legal reviewer name required'; end if;
  update public.supplier_contract_versions set legal_review_status='approved', legal_reviewer=btrim(p_reviewer), legal_reviewed_at=now(), legal_review_note=p_note
   where version_id=p_version and not published;
  if not found then raise exception 'draft contract not found'; end if;
  perform private.fin_audit('contract', p_version, 'legal_review_recorded', null, jsonb_build_object('reviewer', p_reviewer, 'note', p_note));
end $$;

create or replace function public.admin_publish_contract(p_version text) returns void
language plpgsql security definer set search_path='' as $$
declare v public.supplier_contract_versions; r record;
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  select * into v from public.supplier_contract_versions where version_id=p_version for update;
  if not found or v.published then raise exception 'unpublished contract version not found'; end if;
  if v.legal_review_status <> 'approved' then raise exception 'record the legal review before publishing this contract'; end if;
  update public.supplier_contract_versions set is_current=false where is_current;
  update public.supplier_contract_versions set published=true, published_at=now(), is_current=true where version_id=p_version;
  perform private.fin_audit('contract', p_version, 'published', null, jsonb_build_object('sha256', v.body_sha256));
  perform private.admin_log('contract_publish', 'contract', p_version);
  for r in select id from public.suppliers where approval_status='approved' loop
    perform private.notify_supplier(r.id, 'contract_update', 'إصدار جديد من اتفاقية المورد',
      'نُشر إصدار جديد من الاتفاقية ('||p_version||'). يلزم مراجعته والموافقة عليه إلكترونياً لاستمرار البيع. لا يُطبَّق بأثر رجعي على الطلبات المكتملة.',
      'contract', p_version, 'contract:'||p_version||':'||r.id);
  end loop;
  perform private.refresh_all_supplier_selling();
end $$;

-- Acceptance with verification record for an approved supplier (keeps the original receipt RPC behaviour).
create or replace function public.admin_contract_acceptances_detail(p_version text default null) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.is_platform_operator() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select jsonb_build_object('supplier', s.name, 'version_id', a.version_id, 'body_sha256', a.body_sha256, 'signer', a.signer_full_name,
    'signer_email', (select u.email::text from auth.users u where u.id=a.signer_id), 'session_id', a.session_id, 'accepted_at', a.accepted_at)
  from private.supplier_contract_acceptances a join public.suppliers s on s.id=a.supplier_id
  where p_version is null or a.version_id=p_version order by a.accepted_at desc;
end $$;

revoke all on function public.admin_contract_versions(), public.admin_contract_text(text), public.admin_save_contract_draft(text,text,text),
  public.admin_record_contract_legal_review(text,text,text), public.admin_publish_contract(text), public.admin_contract_acceptances_detail(text) from public, anon;
grant execute on function public.admin_contract_versions(), public.admin_contract_text(text), public.admin_save_contract_draft(text,text,text),
  public.admin_record_contract_legal_review(text,text,text), public.admin_publish_contract(text), public.admin_contract_acceptances_detail(text) to authenticated;

-- Supplier: signed copy of the contract version(s) the supplier accepted.
create or replace function public.my_signed_contracts(p_supplier uuid) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  perform private.require_supplier_owner(p_supplier);
  return query select jsonb_build_object('version_id', a.version_id, 'title', v.title, 'body_ar', v.body_ar, 'body_sha256', a.body_sha256,
    'signer_full_name', a.signer_full_name, 'accepted_at', a.accepted_at, 'is_current', v.is_current)
  from private.supplier_contract_acceptances a join public.supplier_contract_versions v on v.version_id=a.version_id
  where a.supplier_id=p_supplier and a.signer_id=auth.uid() order by a.accepted_at desc;
end $$;
revoke all on function public.my_signed_contracts(uuid) from public, anon; grant execute on function public.my_signed_contracts(uuid) to authenticated;

-- ---------------------------------------------------------------- storage: transfer receipts (private)
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('invoice-payment-proofs', 'invoice-payment-proofs', false, 10485760, array['application/pdf','image/jpeg','image/png'])
on conflict (id) do nothing;
create policy payment_proof_owner_insert on storage.objects for insert to authenticated
  with check (bucket_id='invoice-payment-proofs' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy payment_proof_owner_read on storage.objects for select to authenticated
  using (bucket_id='invoice-payment-proofs' and ((storage.foldername(name))[1] = (select auth.uid())::text or (select private.is_platform_operator())));
