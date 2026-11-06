import { useState } from 'react'
import { supabase } from '../lib/supabase'
import { useCart } from '../context/CartContext'
import { sar, CITIES } from '../lib/format'
import { useNavigate, Link } from 'react-router-dom'

export default function Checkout() {
  const { items, total, clear } = useCart()
  const [city, setCity] = useState('makkah')
  const [address, setAddress] = useState('')
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [msg, setMsg] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const nav = useNavigate()

  const submit = async () => {
    setBusy(true); setMsg(null)
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) { setBusy(false); nav('/customer/login'); return }
    const payload = {
      p_items: items.map(i => ({ product_id: i.id, quantity: i.qty })),
      p_city: city, p_address: address, p_recipient_name: name, p_phone: phone,
      p_request_id: crypto.randomUUID(), p_customization: null, p_loyalty_points: 0,
    }
    const { data, error } = await supabase.rpc('place_order', payload)
    setBusy(false)
    if (error) { setMsg('تعذّر إتمام الطلب: ' + error.message); return }
    clear(); nav('/customer')
  }

  if (items.length === 0) return <section style={{ padding: '32px 0' }}><p className="muted">سلتك فارغة. <Link to="/products" style={{ color: 'var(--green)' }}>تصفّح المنتجات ←</Link></p></section>

  return (
    <section style={{ padding: '32px 0', maxWidth: 520 }}>
      <h2 style={{ color: 'var(--green)' }}>إتمام الطلب</h2>
      <div className="card">
        <div className="field"><label>المدينة</label>
          <select value={city} onChange={e => setCity(e.target.value)}>
            {Object.entries(CITIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select></div>
        <div className="field"><label>العنوان التفصيلي</label><input value={address} onChange={e => setAddress(e.target.value)} placeholder="الحي، الشارع، رقم المبنى" /></div>
        <div className="field"><label>اسم المستلم</label><input value={name} onChange={e => setName(e.target.value)} /></div>
        <div className="field"><label>رقم الجوال</label><input value={phone} onChange={e => setPhone(e.target.value)} placeholder="05xxxxxxxx" /></div>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700, margin: '12px 0' }}>
          <span>إجمالي المنتجات</span><span className="price">{sar(total)}</span></div>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || address.length < 10 || name.length < 2 || phone.length < 9} onClick={submit}>
          تأكيد الطلب ←
        </button>
        <p className="muted" style={{ fontSize: 13, marginTop: 8 }}>يتطلب تسجيل دخول العميل. رسوم التوصيل تُحتسب بعد التأكيد.</p>
      </div>
    </section>
  )
}
