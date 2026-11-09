import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link, useNavigate } from 'react-router-dom'

const CATS: Record<string, string> = { water: 'مياه', quran: 'مصاحف', supplies: 'مستلزمات', food: 'أغذية', equipment: 'تجهيزات' }

export default function SupplierRegister() {
  const [f, setF] = useState({
    business_name: '', commercial_registration: '', manager_name: '', manager_title: 'المالك',
    phone: '', email: '', national_address: '', tax_number: '', city: 'makkah', category: 'water', iban: '',
  })
  const [isOwner, setIsOwner] = useState(true)
  const [crDoc, setCrDoc] = useState<File | null>(null)
  const [authDoc, setAuthDoc] = useState<File | null>(null)
  const [licenseDoc, setLicenseDoc] = useState<File | null>(null)
  const [agree, setAgree] = useState(false)
  const [msg, setMsg] = useState<string | null>(null); const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false)
  const [authed, setAuthed] = useState<boolean | null>(null)
  const set = (k: string, v: string) => setF(p => ({ ...p, [k]: v }))

  useEffect(() => {
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
      if (f.tax_number && !/^[0-9]{15}$/.test(f.tax_number)) throw new Error('الرقم الضريبي يجب أن يكون 15 رقماً (أو اتركه فارغاً إن لم ينطبق).')
      if (!/^SA[0-9]{22}$/.test(f.iban)) throw new Error('رقم الآيبان يجب أن يبدأ بـ SA ويتبعه 22 رقماً، ويطابق المستفيد اسم المنشأة.')
      if (!crDoc) throw new Error('صورة السجل التجاري مطلوبة.')
      if (!isOwner && !authDoc) throw new Error('مستند تفويض ممثل المنشأة مطلوب عند عدم كونك صاحب الصلاحية.')
      if (!agree) throw new Error('يلزم الموافقة على عقد المورد.')

      const crPath = await upload(user.id, crDoc, 'cr')
      const authPath = (!isOwner && authDoc) ? await upload(user.id, authDoc, 'authorization') : null
      const licensePath = licenseDoc ? await upload(user.id, licenseDoc, 'license') : null

      const { error } = await supabase.from('seller_applications').insert({
        owner_id: user.id, business_name: f.business_name.trim(), commercial_registration: f.commercial_registration,
        phone: f.phone, email: f.email.trim(), city: f.city, category: f.category, document_path: crPath, iban: f.iban,
        manager_name: f.manager_name.trim(), manager_title: f.manager_title.trim(),
        national_address: f.national_address.trim(), tax_number: f.tax_number || null,
        authorization_doc_path: authPath, license_doc_path: licensePath,
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
        {field('الرقم الضريبي (إن وُجد)', <input value={f.tax_number} onChange={e => set('tax_number', e.target.value.replace(/\D/g, '').slice(0, 15))} placeholder="15 رقماً — اتركه فارغاً إن لم ينطبق" />)}
        {field('الرخصة التجارية/الصناعية (حسب النشاط)', <input type="file" accept="application/pdf,image/jpeg,image/png" onChange={e => setLicenseDoc(e.target.files?.[0] || null)} />, 'ترفقها إن كان نشاطك يتطلب ترخيصاً.')}
        {field('رقم الآيبان البنكي (IBAN) *', <input value={f.iban} onChange={e => set('iban', e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 24))} placeholder="SA0000000000000000000000" />, 'يجب أن يطابق المستفيد اسم المنشأة — يُتحقق قبل صرف المستحقات.')}

        <label style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '14px 0 6px' }}>
          <input type="checkbox" checked={agree} onChange={e => setAgree(e.target.checked)} />
          أوافق على <Link to="/supplier/contract" style={{ color: 'var(--green)' }}>عقد المورد وسياسة الاستخدام</Link>.
        </label>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || authed === false} onClick={submit}>{authed === false ? 'سجّل الدخول أولاً' : (busy ? 'جارٍ الإرسال…' : 'إرسال طلب الانضمام ←')}</button>
      </div>
    </section>
  )
}
