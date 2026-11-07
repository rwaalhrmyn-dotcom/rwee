import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { Link } from 'react-router-dom'

export default function Bundles() {
  const [frequency, setFrequency] = useState('monthly'); const [city, setCity] = useState('makkah'); const [details, setDetails] = useState('')
  const [msg, setMsg] = useState<string | null>(null); const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false)
  const submit = async () => {
    setBusy(true); setMsg(null)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setBusy(false); setMsg('يلزم تسجيل الدخول أولاً.'); return }
    const { error } = await supabase.from('subscription_requests').insert({ customer_id: user.id, frequency, city, details })
    setBusy(false); error ? setMsg('تعذّر الإرسال: ' + error.message) : setOk(true)
  }
  if (ok) return <section style={{ padding: '32px 0', maxWidth: 560 }}><div className="note">تم استلام طلب التوريد الدوري. سيتواصل معك فريقنا لتنسيق الباقة.</div></section>
  return (
    <section style={{ padding: '32px 0', maxWidth: 560 }}>
      <div className="eyebrow">— توريد منتظم بلا انقطاع</div>
      <h2 style={{ color: 'var(--green)' }}>الباقات والتوريد الدوري</h2>
      <p className="muted">اطلب توريداً أسبوعياً أو شهرياً لاحتياجاتك أو منشأتك، ونتكفّل بالباقي.</p>
      <div className="card">
        <div className="field"><label>التكرار</label>
          <select value={frequency} onChange={e => setFrequency(e.target.value)}>
            <option value="weekly">أسبوعي</option><option value="monthly">شهري</option>
          </select></div>
        <div className="field"><label>المدينة</label>
          <select value={city} onChange={e => setCity(e.target.value)}><option value="makkah">مكة المكرمة</option><option value="madinah">المدينة المنورة</option></select></div>
        <div className="field"><label>تفاصيل الاحتياج</label><textarea value={details} onChange={e => setDetails(e.target.value)} rows={4} style={{ width: '100%', padding: 12, border: '1px solid var(--border)', borderRadius: 12, fontFamily: 'inherit' }} placeholder="اذكر المنتجات والكميات التقريبية…" /></div>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || details.length < 10} onClick={submit}>اطلب التوريد الدوري ←</button>
        <p className="muted" style={{ fontSize: 13, marginTop: 8 }}>يتطلب تسجيل الدخول. <Link to="/customer/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p>
      </div>
    </section>
  )
}
