import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { CITIES } from '../../lib/format'
import { Link } from 'react-router-dom'

export default function SupplierRegister() {
  const [name, setName] = useState(''); const [cities, setCities] = useState<string[]>([])
  const [contact, setContact] = useState(''); const [msg, setMsg] = useState<string | null>(null)
  const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false)
  const toggle = (c: string) => setCities(p => p.includes(c) ? p.filter(x => x !== c) : [...p, c])
  const submit = async () => {
    setBusy(true); setMsg(null)
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) { setBusy(false); setMsg('يلزم تسجيل الدخول أولاً عبر رمز التحقق.'); return }
    const { error } = await supabase.from('seller_applications').insert({ name, cities, contact })
    setBusy(false)
    if (error) setMsg('تعذّر إرسال الطلب: ' + error.message); else setOk(true)
  }
  if (ok) return <section style={{ padding: '32px 0' }}><div className="note">تم استلام طلب الانضمام. سيُراجع فريق الإدارة منشأتك ويُعتمدها قبل تفعيل الصلاحيات.</div></section>
  return (
    <section style={{ padding: '32px 0', maxWidth: 520 }}>
      <h2 style={{ color: 'var(--green)' }}>انضمام مورد جديد</h2>
      <p className="muted">سجّل الدخول عبر رمز التحقق أولاً، ثم أرسل بيانات منشأتك للاعتماد. <Link to="/supplier/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p>
      <div className="card">
        <div className="field"><label>اسم المنشأة</label><input value={name} onChange={e => setName(e.target.value)} /></div>
        <div className="field"><label>مدن الخدمة</label>
          <div style={{ display: 'flex', gap: 8 }}>
            {Object.entries(CITIES).map(([k, v]) => (
              <button key={k} className="badge" style={{ border: 0, cursor: 'pointer', background: cities.includes(k) ? 'var(--green)' : undefined, color: cities.includes(k) ? '#fff' : undefined }} onClick={() => toggle(k)}>{v}</button>
            ))}
          </div></div>
        <div className="field"><label>وسيلة تواصل</label><input value={contact} onChange={e => setContact(e.target.value)} placeholder="جوال أو بريد" /></div>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || name.length < 2 || cities.length === 0} onClick={submit}>إرسال طلب الانضمام ←</button>
      </div>
    </section>
  )
}
