-- Marketer registration no longer requires an e-mail verification code: the marketer signs in
-- like the rest of the site (mobile OTP or Google) and the e-mail is an ordinary contact field.
create or replace function public.affiliate_register(p jsonb, p_contract_version text, p_contract_hash text, p_signer_name text, p_agreed boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.affiliate_contract_versions; a public.affiliates; s private.finance_settings := private.fin();
  v_iban text := nullif(private.normalize_iban(p->>'iban'),''); v_phone text := nullif(regexp_replace(coalesce(p->>'phone',''), '\D', '', 'g'),'');
  v_email text;
begin
  if auth.uid() is null or not private.has_verified_session() then raise exception 'login required' using errcode='42501'; end if;
  v_email := lower(btrim(coalesce(nullif(p->>'email',''), (select u.email::text from auth.users u where u.id=auth.uid()), '')));
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 200 then raise exception 'a valid e-mail address is required'; end if;
  if coalesce(p_agreed,false) is not true then raise exception 'explicit agreement to the marketer contract is required'; end if;
  select * into v from public.affiliate_contract_versions where is_current;
  if v.version_id is null or v.version_id <> p_contract_version or v.body_sha256 <> p_contract_hash then
    raise exception 'contract version changed; reload and read the current contract';
  end if;
  if length(btrim(coalesce(p_signer_name,''))) < 3 or btrim(p_signer_name) <> btrim(coalesce(p->>'full_name','')) then
    raise exception 'signer name must match the full name';
  end if;
  if v_phone ~ '^9665[0-9]{8}$' then v_phone := '0' || substr(v_phone, 4); end if;
  if v_iban is not null and not private.is_valid_sa_iban(v_iban) then raise exception 'invalid IBAN'; end if;
  if exists(select 1 from public.affiliates where user_id=auth.uid()) then raise exception 'already registered as a marketer'; end if;
  if v_phone is not null and v_phone !~ '^05[0-9]{8}$' then raise exception 'invalid mobile number'; end if;
  insert into public.affiliates(user_id, email, code, full_name, phone, city, channels, bank_name, iban, account_holder_name, sales_rate_bp, supplier_rate_bp, contract_version)
  values (auth.uid(), lower(v_email), private.new_affiliate_code(), btrim(p->>'full_name'), v_phone, nullif(btrim(coalesce(p->>'city','')),''),
    nullif(btrim(coalesce(p->>'channels','')),''), nullif(btrim(coalesce(p->>'bank_name','')),''), v_iban,
    nullif(btrim(coalesce(p->>'account_holder_name','')),''), s.affiliate_default_rate_bp, s.affiliate_default_supplier_rate_bp, v.version_id)
  returning * into a;
  insert into private.affiliate_contract_acceptances(affiliate_id, user_id, version_id, body_sha256, signer_full_name, session_id, user_agent, ip)
  values (a.id, auth.uid(), v.version_id, v.body_sha256, btrim(p_signer_name), nullif(auth.jwt()->>'session_id','')::uuid,
    left(private.request_header('user-agent'), 300), left(split_part(coalesce(private.request_header('x-forwarded-for'),''), ',', 1), 64));
  perform private.raise_finance_alert('affiliate_application','info',null,null,null,'طلب انضمام مسوّق بالعمولة: '||a.full_name, jsonb_build_object('affiliate_id',a.id), 'affapp:'||a.id);
  return jsonb_build_object('id', a.id, 'status', a.status, 'code', a.code);
end $$;

