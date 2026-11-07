import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link, useNavigate } from 'react-router-dom'

const CATS: Record<string, string> = { water: 'مياه', quran: 'مصاحف', supplies: 'مستلزمات', food: 'أغذية', equipment: 'تجهيزات' }

export default function SupplierRegister() {
  const [f, setF] = useState({ business_name: '', commercial_registration: '', phone: '', city: 'makkah', category: 'water', iban: '' })
  const [doc, setDoc] = useState<File | null>(null)
  const [agree, setAgree] = useState(false)
  const [msg, setMsg] = useState<string | null>(null); const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false)
  const set = (k: string, v: string) => setF(p => ({ ...p, [k]: v }))

  const submit = async () => {
    setBusy(true); setMsg(null)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setBusy(false); setMsg('يلزم تسجيل الدخول عبر رمز التحقق أولاً.'); return }
    if (!/^[0-9]{10}$/.test(f.commercial_registration)) { setBusy(false); setMsg('رقم السجل التجاري يجب أن يكون 10 أرقام.'); return }
    if (!/^SA[0-9]{22}$/.test(f.iban)) { setBusy(false); setMsg('رقم الآيبان يجب أن يبدأ بـ SA ويتبعه 22 رقماً.'); return }
    if (!doc) { setBusy(false); setMsg('يرجى إرفاق صورة السجل التجاري.'); return }
    // 1) upload CR document to seller-documents/{uid}/...
    const ext = doc.name.split('.').pop() || 'jpg'
    const path = `${user.id}/cr-${Date.now()}.${ext}`
    const up = await supabase.storage.from('seller-documents').upload(path, doc, { upsert: false })
    if (up.error) { setBusy(false); setMsg('تعذّر رفع المستند: ' + up.error.message); return }
    // 2) insert application (stays pending)
    const { error } = await supabase.from('seller_applications').insert({
      owner_id: user.id, business_name: f.business_name, commercial_registration: f.commercial_registration,
      phone: f.phone, city: f.city, category: f.category, document_path: path, iban: f.iban,
    })
    setBusy(false)
    if (error) setMsg('تعذّر إرسال الطلب: ' + error.message); else setOk(true)
  }

  if (ok) return <section style={{ padding: '32px 0', maxWidth: 560 }}>
    <div className="note">تم استلام طلب الانضمام بنجاح. حالته الآن: <strong>قيد المراجعة</strong>. سيُراجع فريق الإدارة منشأتك ومستنداتك، وتُفعّل صلاحياتك بعد الاعتماد من لوحة التحكم.</div>
    <Link className="btn ghost" to="/supplier" style={{ marginTop: 14 }}>عودة لبوابة المورد</Link>
  </section>

  return (
    <section style={{ padding: '32px 0', maxWidth: 560 }}>
      <h2 style={{ color: 'var(--green)' }}>انضمام مورد جديد</h2>
      <p className="muted">سجّل الدخول عبر رمز التحقق أولاً، ثم أكمل بيانات منشأتك الرسمية. يبقى الطلب <strong>قيد المراجعة</strong> حتى يعتمده فريق الإدارة. <Link to="/supplier/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p>
      <div className="card">
        <div className="field"><label>اسم المؤسسة / الشركة الرسمي</label><input value={f.business_name} onChange={e => set('business_name', e.target.value)} /></div>
        <div className="field"><label>رقم السجل التجاري (10 أرقام)</label><input value={f.commercial_registration} onChange={e => set('commercial_registration', e.target.value.replace(/\D/g, '').slice(0, 10))} placeholder="1010xxxxxx" /></div>
        <div className="field"><label>صورة السجل التجاري (PDF أو صورة)</label>
          <input type="file" accept="application/pdf,image/jpeg,image/png" onChange={e => setDoc(e.target.files?.[0] || null)} /></div>
        <div className="field"><label>رقم الحساب البنكي (IBAN) — لتحويل مستحقاتك مباشرة</label><input value={f.iban} onChange={e => set('iban', e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 24))} placeholder="SA0000000000000000000000" /></div>
        <div className="field"><label>رقم التواصل</label><input value={f.phone} onChange={e => set('phone', e.target.value)} placeholder="05xxxxxxxx" /></div>
        <div className="field"><label>المدينة</label>
          <select value={f.city} onChange={e => set('city', e.target.value)}>
            <option value="makkah">مكة المكرمة</option><option value="madinah">المدينة المنورة</option>
          </select></div>
        <div className="field"><label>فئة المنتجات</label>
          <select value={f.category} onChange={e => set('category', e.target.value)}>
            {Object.entries(CATS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select></div>
        <label style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '10px 0' }}>
          <input type="checkbox" checked={agree} onChange={e => setAgree(e.target.checked)} />
          أوافق على <Link to="/terms" style={{ color: 'var(--green)' }}>سياسة الاستخدام والخصوصية</Link>.
        </label>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || !agree || f.business_name.length < 2 || f.commercial_registration.length !== 10 || f.iban.length !== 24 || !doc || f.phone.length < 9} onClick={submit}>إرسال طلب الانضمام ←</button>
      </div>
    </section>
  )
}
