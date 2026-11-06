import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { Link } from 'react-router-dom'
import { useSeo } from '../lib/seo'

export default function Business() {
  useSeo('توريد الجمعيات الخيرية','أسعار توريد خاصة وخدمات لوجستية للجمعيات والمنشآت الخيرية.')
  const [org, setOrg] = useState(''); const [phone, setPhone] = useState(''); const [city, setCity] = useState('makkah'); const [details, setDetails] = useState('')
  const [msg, setMsg] = useState<string | null>(null); const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false)
  const submit = async () => {
    setBusy(true); setMsg(null)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setBusy(false); setMsg('يلزم تسجيل الدخول أولاً.'); return }
    const { error } = await supabase.from('quote_requests').insert({ customer_id: user.id, organization_name: org, contact_phone: phone, city, details })
    setBusy(false); error ? setMsg('تعذّر الإرسال: ' + error.message) : setOk(true)
  }
  if (ok) return <section style={{ padding: '32px 0', maxWidth: 560 }}><div className="note">تم استلام طلب عرض التوريد. سيتواصل فريقنا مع جمعيتكم قريباً.</div></section>
  return (
    <section style={{ padding: '32px 0', maxWidth: 560 }}>
      <div className="eyebrow">— للجمعيات الخيرية والمنشآت</div>
      <h2 style={{ color: 'var(--green)' }}>توريد الجمعيات الخيرية — طلب عرض</h2>
      <p className="muted">نوفّر للجمعيات والمنشآت أسعار توريد خاصة وخدمات لوجستية منسّقة. اطلب عرضاً مخصّصاً.</p>
      <div className="card">
        <div className="field"><label>اسم الجمعية / المنشأة</label><input value={org} onChange={e => setOrg(e.target.value)} /></div>
        <div className="field"><label>رقم التواصل</label><input value={phone} onChange={e => setPhone(e.target.value)} placeholder="05xxxxxxxx" /></div>
        <div className="field"><label>المدينة</label>
          <select value={city} onChange={e => setCity(e.target.value)}><option value="makkah">مكة المكرمة</option><option value="madinah">المدينة المنورة</option></select></div>
        <div className="field"><label>تفاصيل الطلب</label><textarea value={details} onChange={e => setDetails(e.target.value)} rows={4} style={{ width: '100%', padding: 12, border: '1px solid var(--border)', borderRadius: 12, fontFamily: 'inherit' }} placeholder="المنتجات، الكميات، دورية التوريد…" /></div>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || org.length < 2 || phone.length < 9 || details.length < 10} onClick={submit}>اطلب عرض توريد ←</button>
        <p className="muted" style={{ fontSize: 13, marginTop: 8 }}>يتطلب تسجيل الدخول. <Link to="/customer/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p>
      </div>
    </section>
  )
}
