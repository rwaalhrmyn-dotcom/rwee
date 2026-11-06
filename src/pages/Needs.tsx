import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { CATEGORIES } from '../lib/format'
import { Link } from 'react-router-dom'

export default function Needs() {
  const [f, setF] = useState({ facility_name: '', city: 'makkah', category: 'water', description: '', quantity: '' })
  const [msg, setMsg] = useState<string | null>(null); const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false)
  const set = (k: string, v: string) => setF(p => ({ ...p, [k]: v }))
  const submit = async () => {
    setBusy(true); setMsg(null)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setBusy(false); setMsg('يلزم تسجيل الدخول أولاً.'); return }
    const { error } = await supabase.from('facility_needs').insert({
      manager_id: user.id, facility_name: f.facility_name, city: f.city, category: f.category,
      description: f.description, quantity: Number(f.quantity),
    })
    setBusy(false); error ? setMsg('تعذّر الإرسال: ' + error.message) : setOk(true)
  }
  if (ok) return <section style={{ padding: '32px 0', maxWidth: 560 }}><div className="note">تم نشر احتياج الجمعية. سيظهر للموردين لتلبيته.</div></section>
  return (
    <section style={{ padding: '32px 0', maxWidth: 560 }}>
      <div className="eyebrow">— أعلن احتياجك</div>
      <h2 style={{ color: 'var(--green)' }}>احتياجات الجمعية</h2>
      <p className="muted">انشر احتياج منشأتك ليصل إلى الموردين المناسبين في مدينتك.</p>
      <div className="card">
        <div className="field"><label>اسم المنشأة / الجمعية</label><input value={f.facility_name} onChange={e => set('facility_name', e.target.value)} /></div>
        <div className="field"><label>المدينة</label>
          <select value={f.city} onChange={e => set('city', e.target.value)}><option value="makkah">مكة المكرمة</option><option value="madinah">المدينة المنورة</option></select></div>
        <div className="field"><label>الفئة</label>
          <select value={f.category} onChange={e => set('category', e.target.value)}>{Object.entries(CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></div>
        <div className="field"><label>الكمية</label><input value={f.quantity} onChange={e => set('quantity', e.target.value.replace(/\D/g, ''))} /></div>
        <div className="field"><label>الوصف</label><textarea value={f.description} onChange={e => set('description', e.target.value)} rows={3} style={{ width: '100%', padding: 12, border: '1px solid var(--border)', borderRadius: 12, fontFamily: 'inherit' }} /></div>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || f.facility_name.length < 2 || !f.quantity || f.description.length < 2} onClick={submit}>انشر الاحتياج ←</button>
        <p className="muted" style={{ fontSize: 13, marginTop: 8 }}>يتطلب تسجيل الدخول. <Link to="/customer/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p>
      </div>
    </section>
  )
}
