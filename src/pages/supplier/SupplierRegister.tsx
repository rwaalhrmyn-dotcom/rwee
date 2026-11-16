import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'
import { ENTITY_TYPES, bankFromIban, isValidSaIban, isValidSaVat, normalizeIban } from '../../lib/finance'

const CATS: Record<string, string> = { water: 'مياه', quran: 'مصاحف', supplies: 'مستلزمات', food: 'أغذية', equipment: 'تجهيزات' }

export default function SupplierRegister() {
  const [f, setF] = useState({
    business_name: '', commercial_registration: '', manager_name: '', manager_title: 'المالك',
    phone: '', email: '', national_address: '', tax_number: '', city: 'makkah', category: 'water', iban: '',
    entity_type: '', account_holder_name: '', bank_name: '',
  })
  const [contract, setContract] = useState<{ version_id: string; body_ar: string; body_sha256: string } | null>(null)
  const [signer, setSigner] = useState('')
  const [requestId] = useState(() => crypto.randomUUID())
  const [isOwner, setIsOwner] = useState(true)
  const [acceptsDelivery, setAcceptsDelivery] = useState(false)
  const [crDoc, setCrDoc] = useState<File | null>(null)
  const [authDoc, setAuthDoc] = useState<File | null>(null)
  const [licenseDoc, setLicenseDoc] = useState<File | null>(null)
  const [agree, setAgree] = useState(false)
  const [msg, setMsg] = useState<string | null>(null); const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false)
  const [authed, setAuthed] = useState<boolean | null>(null)
  const set = (k: string, v: string) => setF(p => ({ ...p, [k]: v }))

  useEffect(() => {
    supabase.rpc('current_supplier_contract').then(({ data }) => setContract(Array.isArray(data) ? data[0] ?? null : data))
    supabase.auth.getSession().then(({ data }) => {
      setAuthed(!!data.session)
      const u = data.session?.user
      if (u?.phone) setF(p => ({ ...p, phone: p.phone || '0' + u.phone!.replace(/^\+?966/, '') }))
      if (u?.email) setF(p => ({ ...p, email: p.email || u.email! }))
    })
  }, [])

  const upload = async (uid: string, file: File, label: string) => {
    const ext = file.name.split('.').pop() || 'jpg'
    const path = `${uid}/${label}-${Date.now()}.${ext}`
    const up = await supabase.storage.from('seller-documents').upload(path, file, { upsert: false })
    if (up.error) throw new Error('تعذّر رفع ' + label + ': ' + up.error.message)
    return path
  }

  const submit = async () => {
    setBusy(true); setMsg(null)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) { setBusy(false); setMsg('يلزم تسجيل الدخول برمز التحقق أولاً.'); return }
      if (f.business_name.trim().length < 2) throw new Error('اسم المنشأة التجاري مطلوب ومطابق للسجل.')
      if (!/^[0-9]{10}$/.test(f.commercial_registration)) throw new Error('رقم السجل التجاري يجب أن يكون 10 أرقام.')
      if (f.manager_name.trim().length < 2) throw new Error('اسم المسؤول مطلوب.')
      if (f.manager_title.trim().length < 2) throw new Error('صفة المسؤول مطلوبة.')
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(f.email)) throw new Error('البريد الإلكتروني غير صحيح.')
      if (f.phone.replace(/\D/g, '').length < 9) throw new Error('رقم جوال المسؤول مطلوب.')
      if (f.national_address.trim().length < 4) throw new Error('العنوان الوطني وموقع المستودع مطلوبان قبل البيع.')
      if (!f.entity_type) throw new Error('حدد نوع المنشأة (مصنع / موزع / تاجر).')
      if (!isValidSaVat(f.tax_number)) throw new Error('الرقم الضريبي مطلوب: 15 رقماً يبدأ وينتهي بالرقم 3.')
      if (!isValidSaIban(f.iban)) throw new Error('رقم الآيبان غير صحيح — تحقق من الأرقام (SA + 22 رقماً).')
      if (f.account_holder_name.trim().length < 2) throw new Error('اسم صاحب الحساب البنكي مطلوب.')
      if (!crDoc) throw new Error('صورة السجل التجاري مطلوبة.')
      if (!isOwner && !authDoc) throw new Error('مستند تفويض ممثل المنشأة مطلوب عند عدم كونك صاحب الصلاحية.')
      if (!contract) throw new Error('تعذّر تحميل نص العقد — أعد تحميل الصفحة.')
      if (!agree || signer.trim().length < 3) throw new Error('يلزم الموافقة الصريحة على الاتفاقية وكتابة اسم الموقّع كاملاً.')

      const crPath = await upload(user.id, crDoc, 'cr')
      const authPath = (!isOwner && authDoc) ? await upload(user.id, authDoc, 'authorization') : null
      const licensePath = licenseDoc ? await upload(user.id, licenseDoc, 'license') : null

      // Application + explicit, hash-verified consent to the exact contract text are recorded atomically.
      const { error } = await supabase.rpc('submit_seller_application', {
        p: { business_name: f.business_name.trim(), commercial_registration: f.commercial_registration, entity_type: f.entity_type,
          phone: f.phone, email: f.email.trim(), city: f.city, category: f.category, document_path: crPath, iban: normalizeIban(f.iban),
          manager_name: f.manager_name.trim(), manager_title: f.manager_title.trim(), national_address: f.national_address.trim(),
          tax_number: f.tax_number, authorization_doc_path: authPath, license_doc_path: licensePath, accepts_delivery: acceptsDelivery,
          account_holder_name: f.account_holder_name.trim(), bank_name: f.bank_name.trim() || bankFromIban(f.iban) },
        p_contract_version: contract.version_id, p_contract_hash: contract.body_sha256, p_signer_name: signer.trim(), p_agreed: agree, p_request: requestId,
      })
      setBusy(false)
      if (error) setMsg('تعذّر إرسال الطلب: ' + error.message); else setOk(true)
    } catch (e: any) { setBusy(false); setMsg(e.message || String(e)) }
  }

  if (ok) return <section style={{ padding: '32px 0', maxWidth: 600 }}>
    <div className="note">تم استلام طلب الانضمام بنجاح. حالته الآن: <strong>قيد المراجعة</strong>. يراجع فريق الإدارة تطابق المنشأة والسجل التجاري ونشاطه، والعنوان الوطني، ومطابقة الآيبان، والمستندات — وتُفعّل صلاحياتك بعد الاعتماد.</div>
    <Link className="btn ghost" to="/supplier" style={{ marginTop: 14 }}>عودة لبوابة المورد</Link>
  </section>

  const field = (label: string, node: any, hint?: string) => (
    <div className="field"><label>{label}</label>{node}{hint && <p className="muted" style={{ fontSize: 12, marginTop: 3 }}>{hint}</p>}</div>
  )

  return (
    <section style={{ padding: '32px 0', maxWidth: 600 }}>
      <h2 style={{ color: 'var(--green)' }}>انضمام مورد جديد</h2>
      <p className="muted">سجّل الدخول برمز التحقق أولاً، ثم أكمل بيانات منشأتك الرسمية ومستنداتها. يبقى الطلب <strong>قيد المراجعة</strong> حتى يعتمده فريق الإدارة بعد التحقق.</p>
      {authed === false && (
        <div className="note" style={{ margin: '12px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
          <span>يلزم تسجيل الدخول برمز التحقق (OTP) قبل إرسال الطلب.</span>
          <Link className="btn" to="/supplier/login" style={{ padding: '7px 16px' }}>تسجيل الدخول ←</Link>
        </div>
      )}
      <div className="card">
        <h3 style={{ marginTop: 0, color: 'var(--green)', fontSize: 15 }}>بيانات المنشأة</h3>
        {field('نوع المنشأة *', <select value={f.entity_type} onChange={e => set('entity_type', e.target.value)}><option value="">— اختر —</option>{Object.entries(ENTITY_TYPES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>)}
        {field('اسم المنشأة التجاري (مطابق للسجل) *', <input value={f.business_name} onChange={e => set('business_name', e.target.value)} />)}
        {field('رقم السجل التجاري (10 أرقام) *', <input value={f.commercial_registration} onChange={e => set('commercial_registration', e.target.value.replace(/\D/g, '').slice(0, 10))} placeholder="1010xxxxxx" />, 'يُراجَع نشاط السجل وصلاحيته قبل الاعتماد.')}
        {field('صورة السجل التجاري (PDF أو صورة) *', <input type="file" accept="application/pdf,image/jpeg,image/png" onChange={e => setCrDoc(e.target.files?.[0] || null)} />)}

        <h3 style={{ color: 'var(--green)', fontSize: 15, marginTop: 18 }}>ممثل المنشأة</h3>
        {field('اسم المسؤول *', <input value={f.manager_name} onChange={e => set('manager_name', e.target.value)} />)}
        {field('صفة المسؤول *', <select value={f.manager_title} onChange={e => set('manager_title', e.target.value)}><option>المالك</option><option>مدير مفوّض</option><option>ممثل مفوّض</option><option>مدير مبيعات</option></select>)}
        <label style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '4px 0 8px' }}>
          <input type="checkbox" checked={isOwner} onChange={e => setIsOwner(e.target.checked)} /> أنا صاحب الصلاحية (المالك أو المدير المفوّض في السجل)
        </label>
        {!isOwner && field('مستند تفويض ممثل المنشأة *', <input type="file" accept="application/pdf,image/jpeg,image/png" onChange={e => setAuthDoc(e.target.files?.[0] || null)} />, 'مطلوب عند عدم كونك صاحب الصلاحية.')}
        {field('رقم جوال المسؤول *', <input value={f.phone} onChange={e => set('phone', e.target.value)} placeholder="05xxxxxxxx" />, 'مُوثّق عبر رمز OTP عند الدخول.')}
        {field('البريد الإلكتروني *', <input type="email" value={f.email} onChange={e => set('email', e.target.value)} placeholder="name@company.com" />)}

        <h3 style={{ color: 'var(--green)', fontSize: 15, marginTop: 18 }}>العنوان والمستودع والمالية</h3>
        {field('العنوان الوطني وموقع المستودع *', <input value={f.national_address} onChange={e => set('national_address', e.target.value)} placeholder="المدينة، الحي، الرمز البريدي، الرقم الإضافي" />, 'إلزامي قبل البيع — يحدد موقع التوريد.')}
        {field('المدينة', <select value={f.city} onChange={e => set('city', e.target.value)}><option value="makkah">مكة المكرمة</option><option value="madinah">المدينة المنورة</option></select>)}
        {field('فئة المنتجات', <select value={f.category} onChange={e => set('category', e.target.value)}>{Object.entries(CATS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>)}
        {field('الرقم الضريبي (15 رقماً) *', <input value={f.tax_number} onChange={e => set('tax_number', e.target.value.replace(/\D/g, '').slice(0, 15))} placeholder="3xxxxxxxxxxxxxx" inputMode="numeric" />, 'إلزامي — رقم تسجيل ضريبة القيمة المضافة (15 رقماً).')}
        {field('الرخصة التجارية/الصناعية (حسب النشاط)', <input type="file" accept="application/pdf,image/jpeg,image/png" onChange={e => setLicenseDoc(e.target.files?.[0] || null)} />, 'ترفقها إن كان نشاطك يتطلب ترخيصاً.')}
        {field('رقم الآيبان البنكي (IBAN) *', <input dir="ltr" value={f.iban} onChange={e => set('iban', normalizeIban(e.target.value).slice(0, 24))} placeholder="SA0000000000000000000000" />,
          !f.iban ? 'يجب أن يطابق المستفيد اسم المنشأة.' : isValidSaIban(f.iban) ? `✓ آيبان صحيح${bankFromIban(f.iban) ? ' — ' + bankFromIban(f.iban) : ''}` : '✗ الآيبان غير صحيح')}
        {field('اسم صاحب الحساب البنكي *', <input value={f.account_holder_name} onChange={e => set('account_holder_name', e.target.value)} />)}
        {field('اسم البنك', <input value={f.bank_name} onChange={e => set('bank_name', e.target.value)} placeholder={bankFromIban(f.iban) ?? ''} />)}

        <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', margin: '6px 0' }}>
          <input type="checkbox" checked={acceptsDelivery} onChange={e => setAcceptsDelivery(e.target.checked)} style={{ marginTop: 3 }} />
          <span>أقبل توصيل الطلبات عبر مندوبي منشأتي (يظهر للعميل خيار «التوصيل عبر المورد»). يمكنك تغيير ذلك لاحقاً من لوحة المورد.</span>
        </label>

        <h3 style={{ color: 'var(--green)', fontSize: 15, marginTop: 18 }}>اتفاقية المورد (اقرأها كاملة قبل الموافقة)</h3>
        {contract
          ? <div style={{ whiteSpace: 'pre-wrap', fontSize: 13, maxHeight: 320, overflow: 'auto', border: '1px solid var(--line)', borderRadius: 10, padding: 12, background: '#fff' }}>{contract.body_ar}</div>
          : <p className="muted">جارٍ تحميل نص الاتفاقية…</p>}
        {contract && <p className="muted" style={{ fontSize: 11 }}>الإصدار {contract.version_id} · بصمة النص <span dir="ltr">{contract.body_sha256.slice(0, 16)}…</span></p>}
        {field('اسم الموقّع كاملاً *', <input value={signer} onChange={e => setSigner(e.target.value)} placeholder="الاسم الرباعي لممثل المنشأة" />)}
        <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', margin: '10px 0 6px' }}>
          <input type="checkbox" checked={agree} onChange={e => setAgree(e.target.checked)} style={{ marginTop: 3 }} />
          <span>أقر بأنني قرأت الاتفاقية وفهمت جميع أحكامها، بما فيها العمولة الأساسية والزيادات السعرية والالتزام بالسداد الشهري، وأوافق عليها إلكترونياً، وكذلك <Link to="/terms" style={{ color: 'var(--green)' }}>الشروط والأحكام</Link> و<Link to="/privacy" style={{ color: 'var(--green)' }}>سياسة الخصوصية</Link>.</span>
        </label>
        <p className="muted" style={{ fontSize: 12, margin: '0 0 6px' }}>تُحفظ موافقتك مع رقم إصدار الاتفاقية وبصمتها وتاريخ ووقت الموافقة ومعرّف حسابك وجلستك.</p>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || authed === false || !agree || signer.trim().length < 3} onClick={submit}>{authed === false ? 'سجّل الدخول أولاً' : (busy ? 'جارٍ الإرسال…' : 'إرسال طلب الانضمام ←')}</button>
      </div>
    </section>
  )
}
