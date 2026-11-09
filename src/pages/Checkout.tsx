import { useEffect, useState, lazy, Suspense } from 'react'
import { supabase, SUPABASE_URL } from '../lib/supabase'
import { useCart } from '../context/CartContext'
import { sar, CITIES } from '../lib/format'
import { useNavigate, Link } from 'react-router-dom'
import type { LatLng } from '../components/LocationPicker'
// Leaflet is heavy — load the map only on this page so the rest of the site stays light.
const LocationPicker = lazy(() => import('../components/LocationPicker'))

export default function Checkout() {
  const { items, total, clear } = useCart()
  const [city, setCity] = useState('makkah')
  const [address, setAddress] = useState('')
  const [geo, setGeo] = useState<LatLng | null>(null)
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [msg, setMsg] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [method, setMethod] = useState<'oto' | 'supplier'>('oto')
  const [delv, setDelv] = useState<{ supplier_delivery_available: boolean; parcels: number; supplier_delivery_halalas: number; oto_waybill_halalas: number } | null>(null)
  const nav = useNavigate()

  // Delivery options for this cart: supplier delivery shows only if every
  // supplier in the basket accepts it; otherwise OTO shipping is used.
  useEffect(() => {
    if (items.length === 0) return
    (async () => {
      const { data } = await supabase.rpc('delivery_options', { p_product_ids: items.map(i => i.id) })
      const o = Array.isArray(data) ? data[0] : data
      if (o) { setDelv(o); if (!o.supplier_delivery_available) setMethod('oto') }
    })()
  }, [items])

  const parcels = delv?.parcels || 1
  const deliveryHalalas = delv
    ? (method === 'supplier' ? delv.supplier_delivery_halalas : delv.oto_waybill_halalas) * parcels
    : 0
  const baseHalalas = total + deliveryHalalas
  const grandHalalas = Math.round(baseHalalas * 1.15) // 15% VAT on products + delivery
  const vatHalalas = grandHalalas - baseHalalas

  // prefill returning customer's saved details
  useEffect(() => {
    (async () => {
      const { data } = await supabase.from('profiles').select('full_name,phone,city').maybeSingle()
      if (data) { if (data.full_name) setName(data.full_name); if (data.phone) setPhone(data.phone); if (data.city) setCity(data.city) }
    })()
  }, [])

  // If the customer returns from the Tap page via the browser back button, the
  // component may be restored from the bfcache with busy still true (which would
  // leave the pay button stuck disabled). Reset it whenever the page is shown.
  useEffect(() => {
    const reset = () => setBusy(false)
    window.addEventListener('pageshow', reset)
    return () => window.removeEventListener('pageshow', reset)
  }, [])

  const submit = async () => {
    setBusy(true); setMsg(null)
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) { setBusy(false); nav('/customer/login?redirect=/checkout'); return }
    // Include the exact map pin (if chosen) so the courier can navigate to it.
    const fullAddress = geo
      ? `${address} — الموقع على الخريطة: https://www.google.com/maps?q=${geo.lat},${geo.lng}`
      : address
    // 1) create the order
    const { data: orderId, error } = await supabase.rpc('place_order', {
      p_items: items.map(i => ({ product_id: i.id, quantity: i.qty })),
      p_city: city, p_address: fullAddress, p_recipient_name: name, p_phone: phone,
      p_request_id: crypto.randomUUID(), p_customization: {}, p_loyalty_points: 0,
    })
    if (error) { setBusy(false); setMsg('تعذّر إنشاء الطلب: ' + error.message); return }
    // 1b) record the delivery method — the fee is computed and stored server-side
    const dset = await supabase.rpc('set_order_delivery', { p_order_id: orderId, p_method: method })
    if (dset.error) { setBusy(false); setMsg('تعذّر تحديد طريقة التوصيل: ' + dset.error.message); return }
    // save the customer's details for next time (opportunistic, non-blocking)
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        const ins = await supabase.from('profiles').insert({ id: user.id, full_name: name, phone, city })
        if (ins.error) await supabase.from('profiles').update({ full_name: name, phone, city }).eq('id', user.id)
      }
    } catch { /* non-blocking */ }
    // 2) create a Tap charge and redirect to the hosted payment page
    try {
      const res = await fetch(`${SUPABASE_URL}/functions/v1/tap-create-charge`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ order_id: orderId }),
      })
      const out = await res.json().catch(() => ({}))
      if (out.url) { clear(); window.location.href = out.url; return }
      // Charge could not be created — keep the order pending (unpaid) and let the
      // customer retry; never pretend the order was completed without payment.
      setBusy(false)
      setMsg('تعذّر فتح صفحة الدفع حالياً. طلبك محفوظ كمعلّق — حاول الدفع مرة أخرى، وإن تكرر الأمر تواصل معنا وسنكمل طلبك.')
      return
    } catch (e) {
      setBusy(false)
      setMsg('تعذّر الاتصال ببوابة الدفع. تحقق من اتصالك وحاول مرة أخرى.')
      return
    }
  }

  if (items.length === 0) return <section style={{ padding: '32px 0' }}><p className="muted">سلتك فارغة. <Link to="/products" style={{ color: 'var(--green)' }}>تصفّح المنتجات ←</Link></p></section>

  return (
    <section style={{ padding: '32px 0', maxWidth: 520 }}>
      <h2 style={{ color: 'var(--green)' }}>إتمام الطلب والدفع</h2>
      <div className="card">
        <div className="field"><label>المدينة</label>
          <select value={city} onChange={e => setCity(e.target.value)}>
            {Object.entries(CITIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select></div>
        <div className="field"><label>العنوان ومكان التوصيل</label>
          <Suspense fallback={<div className="muted" style={{ fontSize: 13 }}>جارٍ تحميل الخريطة…</div>}>
            <LocationPicker value={address} onChange={setAddress} onLocation={setGeo} city={city} />
          </Suspense></div>
        <div className="field"><label>اسم المستلم</label><input value={name} onChange={e => setName(e.target.value)} /></div>
        <div className="field"><label>رقم الجوال</label><input value={phone} onChange={e => setPhone(e.target.value)} placeholder="05xxxxxxxx" /></div>

        <div className="field"><label>طريقة التوصيل</label>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 12px', border: '1px solid var(--line)', borderRadius: 10, cursor: 'pointer', background: method === 'oto' ? 'rgba(7,84,66,0.06)' : undefined }}>
              <input type="radio" name="deliv" checked={method === 'oto'} onChange={() => setMethod('oto')} />
              <span style={{ flex: 1 }}>الشحن عبر أوتو (OTO)</span>
              <strong>{sar((delv?.oto_waybill_halalas || 800) * parcels)}</strong>
            </label>
            {delv?.supplier_delivery_available && (
              <label style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 12px', border: '1px solid var(--line)', borderRadius: 10, cursor: 'pointer', background: method === 'supplier' ? 'rgba(7,84,66,0.06)' : undefined }}>
                <input type="radio" name="deliv" checked={method === 'supplier'} onChange={() => setMethod('supplier')} />
                <span style={{ flex: 1 }}>التوصيل عبر المورد</span>
                <strong>{sar((delv?.supplier_delivery_halalas || 25) * parcels)}</strong>
              </label>
            )}
          </div>
          <p className="muted" style={{ fontSize: 12, marginTop: 6 }}>تظهر قيمة التوصيل/البوليصة كإجمالي واحد شامل{parcels > 1 ? ` (${parcels} طرود)` : ''}.</p>
        </div>

        <div style={{ margin: '14px 0', borderTop: '1px solid var(--line)', paddingTop: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', margin: '4px 0' }}><span className="muted">إجمالي المنتجات</span><span>{sar(total)}</span></div>
          <div style={{ display: 'flex', justifyContent: 'space-between', margin: '4px 0' }}><span className="muted">{method === 'supplier' ? 'التوصيل عبر المورد' : 'الشحن عبر أوتو'}</span><span>{sar(deliveryHalalas)}</span></div>
          <div style={{ display: 'flex', justifyContent: 'space-between', margin: '4px 0' }}><span className="muted">ضريبة القيمة المضافة (15%)</span><span>{sar(vatHalalas)}</span></div>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700, marginTop: 8, fontSize: 17 }}><span>الإجمالي شامل الضريبة</span><span className="price">{sar(grandHalalas)}</span></div>
        </div>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        {(() => {
          const need: string[] = []
          if (address.trim().length < 6) need.push('العنوان التفصيلي')
          if (name.trim().length < 2) need.push('اسم المستلم')
          if (phone.replace(/\D/g, '').length < 9) need.push('رقم الجوال')
          return !busy && need.length > 0
            ? <div className="note" style={{ margin: '10px 0' }}>أكمل الحقول التالية للمتابعة: {need.join('، ')}.</div>
            : null
        })()}
        <button className="btn" style={{ width: '100%' }} disabled={busy || address.trim().length < 6 || name.trim().length < 2 || phone.replace(/\D/g, '').length < 9} onClick={submit}>
          {busy ? 'جارٍ التحويل للدفع…' : 'المتابعة للدفع ←'}
        </button>
        <p className="muted" style={{ fontSize: 13, marginTop: 8, textAlign: 'center' }}>الأسعار شاملة ضريبة القيمة المضافة · الدفع الآمن عبر Tap · mada · Visa · Apple Pay</p>
      </div>
    </section>
  )
}
