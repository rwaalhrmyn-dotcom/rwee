import { useEffect, useMemo, useState, lazy, Suspense } from 'react'
import { supabase, SUPABASE_URL } from '../lib/supabase'
import { useCart } from '../context/CartContext'
import { sar, CITIES } from '../lib/format'
import { useNavigate, Link } from 'react-router-dom'
import type { LatLng } from '../components/LocationPicker'
// Leaflet is heavy — load the map only on this page so the rest of the site stays light.
const LocationPicker = lazy(() => import('../components/LocationPicker'))

type Line = { product_id: string; name: string; quantity: number; unit_price_halalas: number; line_net_halalas: number; vat_rate_bp: number; line_vat_halalas: number; line_total_halalas: number }
type Group = { supplier_id: string; supplier_name: string; accepts_delivery: boolean; vat_rate_bp: number; lines: Line[]; subtotal_halalas: number;
  delivery_halalas: number; delivery_method: 'oto' | 'supplier'; vat_halalas: number; total_halalas: number }
type Quote = { direct_payments: boolean; groups: Group[]; requires_split: boolean; disclosure: string | null; unavailable: { product_id: string; name: string; reason: string }[] }

const REASON: Record<string, string> = { unavailable: 'غير متاح حالياً', insufficient_stock: 'الكمية غير متوفرة', supplier_not_selling: 'المورد لا يستقبل طلبات حالياً', not_in_city: 'غير متاح في هذه المدينة' }

export default function Checkout() {
  const { items, total, clear, remove } = useCart()
  const [city, setCity] = useState('makkah')
  const [address, setAddress] = useState('')
  const [geo, setGeo] = useState<LatLng | null>(null)
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [msg, setMsg] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [method, setMethod] = useState<'oto' | 'supplier'>('oto')
  const [quote, setQuote] = useState<Quote | null>(null)
  const [groupId, setGroupId] = useState<string | null>(null)
  const nav = useNavigate()

  // Authoritative server-side quote: prices, per-supplier VAT and delivery.
  useEffect(() => {
    if (items.length === 0) return
    let alive = true
    ;(async () => {
      const { data, error } = await supabase.rpc('checkout_quote', {
        p_items: items.map(i => ({ product_id: i.id, quantity: i.qty })), p_city: city, p_delivery_method: method,
      })
      if (!alive) return
      if (error) { setMsg('تعذّر حساب الإجمالي: ' + error.message); return }
      const q = data as Quote
      setQuote(q)
      setGroupId(g => (g && q.groups.some(x => x.supplier_id === g)) ? g : (q.groups[0]?.supplier_id ?? null))
    })()
    return () => { alive = false }
  }, [items, city, method])

  const group = useMemo(() => quote?.groups.find(g => g.supplier_id === groupId) ?? null, [quote, groupId])
  const direct = !!quote?.direct_payments
  const supplierDeliveryAvailable = direct ? !!group?.accepts_delivery : !!quote?.groups.length && quote.groups.every(g => g.accepts_delivery)

  // Legacy (flag off): platform collects; keep the previous totals logic.
  const legacyDelivery = quote ? quote.groups.reduce((s, g) => s + g.delivery_halalas, 0) : 0
  const legacyBase = total + legacyDelivery
  const legacyGrand = Math.round(legacyBase * 1.15)

  useEffect(() => {
    (async () => {
      const { data } = await supabase.from('profiles').select('full_name,phone,city').maybeSingle()
      if (data) { if (data.full_name) setName(data.full_name); if (data.phone) setPhone(data.phone); if (data.city) setCity(data.city) }
    })()
  }, [])

  // bfcache restore after the back button from the payment page: re-enable the button.
  useEffect(() => {
    const reset = () => setBusy(false)
    window.addEventListener('pageshow', reset)
    return () => window.removeEventListener('pageshow', reset)
  }, [])

  const submit = async () => {
    setBusy(true); setMsg(null)
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) { setBusy(false); nav('/customer/login?redirect=/checkout'); return }
    if (direct && !group) { setBusy(false); setMsg('اختر طلب المورد الذي تريد دفعه.'); return }
    const fullAddress = geo ? `${address} — الموقع على الخريطة: https://www.google.com/maps?q=${geo.lat},${geo.lng}` : address
    // In direct mode only the selected supplier's items form this order (each supplier collects its own payment).
    const orderLines = direct ? group!.lines.map(l => ({ product_id: l.product_id, quantity: l.quantity })) : items.map(i => ({ product_id: i.id, quantity: i.qty }))
    const { data: orderId, error } = await supabase.rpc('place_order', {
      p_items: orderLines, p_city: city, p_address: fullAddress, p_recipient_name: name, p_phone: phone,
      p_request_id: crypto.randomUUID(), p_customization: {}, p_loyalty_points: 0,
    })
    if (error) {
      setBusy(false)
      setMsg(error.message.includes('multi_supplier_order') ? 'يلزم الدفع لكل مورد على حدة. اختر طلب مورد واحد ثم تابع.' : 'تعذّر إنشاء الطلب: ' + error.message)
      return
    }
    const dset = await supabase.rpc('set_order_delivery', { p_order_id: orderId, p_method: direct ? group!.delivery_method : method })
    if (dset.error) { setBusy(false); setMsg('تعذّر تحديد طريقة التوصيل: ' + dset.error.message); return }
    try {
      const { data: { user } } = await supabase.auth.getUser()
      if (user) {
        const ins = await supabase.from('profiles').insert({ id: user.id, full_name: name, phone, city })
        if (ins.error) await supabase.from('profiles').update({ full_name: name, phone, city }).eq('id', user.id)
      }
    } catch { /* non-blocking */ }
    try {
      const fn = direct ? 'supplier-checkout' : 'tap-create-charge'
      const res = await fetch(`${SUPABASE_URL}/functions/v1/${fn}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}` },
        body: JSON.stringify({ order_id: orderId }),
      })
      const out = await res.json().catch(() => ({}))
      if (out.url) {
        if (direct) group!.lines.forEach(l => remove(l.product_id)); else clear()
        window.location.href = out.url
        return
      }
      setBusy(false)
      setMsg('تعذّر فتح صفحة الدفع حالياً. طلبك محفوظ كمعلّق — حاول الدفع مرة أخرى، وإن تكرر الأمر تواصل معنا.')
    } catch {
      setBusy(false)
      setMsg('تعذّر الاتصال ببوابة الدفع. تحقق من اتصالك وحاول مرة أخرى.')
    }
  }

  if (items.length === 0) return <section style={{ padding: '32px 0' }}><p className="muted">سلتك فارغة. <Link to="/products" style={{ color: 'var(--green)' }}>تصفّح المنتجات ←</Link></p></section>

  const row = (k: string, v: string, strong = false) => (
    <div style={{ display: 'flex', justifyContent: 'space-between', margin: '4px 0', fontWeight: strong ? 700 : undefined, fontSize: strong ? 17 : undefined }}>
      <span className={strong ? undefined : 'muted'}>{k}</span><span className={strong ? 'price' : undefined}>{v}</span>
    </div>
  )

  return (
    <section style={{ padding: '32px 0', maxWidth: 560 }}>
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

        {quote && quote.unavailable.length > 0 && (
          <div className="note" style={{ margin: '10px 0' }}>
            <strong>منتجات لا يمكن طلبها الآن:</strong>
            <ul style={{ margin: '6px 0 0', paddingInlineStart: 18 }}>{quote.unavailable.map(u => <li key={u.product_id}>{u.name || 'منتج'} — {REASON[u.reason] || u.reason}</li>)}</ul>
          </div>
        )}

        {direct && quote && quote.requires_split && (
          <div className="note" style={{ margin: '10px 0' }}>
            <strong>الدفع لكل مورد على حدة</strong>
            <p style={{ margin: '6px 0 0', fontSize: 14 }}>{quote.disclosure}</p>
          </div>
        )}

        {direct && quote && quote.groups.length > 0 && (
          <div className="field"><label>{quote.requires_split ? 'اختر طلب المورد الذي تدفعه الآن' : 'المورد'}</label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {quote.groups.map(g => (
                <label key={g.supplier_id} style={{ display: 'block', padding: '10px 12px', border: '1px solid var(--line)', borderRadius: 10, cursor: 'pointer', background: groupId === g.supplier_id ? 'rgba(7,84,66,0.06)' : undefined }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                    <input type="radio" name="grp" checked={groupId === g.supplier_id} onChange={() => setGroupId(g.supplier_id)} />
                    <strong style={{ flex: 1 }}>{g.supplier_name}</strong>
                    <span className="price">{sar(g.total_halalas)}</span>
                  </div>
                  <div className="muted" style={{ fontSize: 13, marginTop: 4 }}>{g.lines.map(l => `${l.name} × ${l.quantity}`).join('، ')}</div>
                </label>
              ))}
            </div>
          </div>
        )}

        {supplierDeliveryAvailable && (
          <div className="field"><label>طريقة التوصيل</label>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {(['oto', 'supplier'] as const).map(m => (
                <label key={m} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '10px 12px', border: '1px solid var(--line)', borderRadius: 10, cursor: 'pointer', background: method === m ? 'rgba(7,84,66,0.06)' : undefined }}>
                  <input type="radio" name="deliv" checked={method === m} onChange={() => setMethod(m)} />
                  <span style={{ flex: 1 }}>{m === 'oto' ? 'توصيل المنصة' : 'التوصيل عبر المورد'}</span>
                </label>
              ))}
            </div>
          </div>
        )}

        <div style={{ margin: '14px 0', borderTop: '1px solid var(--line)', paddingTop: 12 }}>
          {direct && group ? <>
            {row('المنتجات (قبل الضريبة)', sar(group.subtotal_halalas))}
            {group.delivery_halalas > 0 && row('التوصيل', sar(group.delivery_halalas))}
            {row(group.vat_rate_bp > 0 ? `ضريبة القيمة المضافة (${group.vat_rate_bp / 100}%)` : 'ضريبة القيمة المضافة (المورد غير مسجّل)', sar(group.vat_halalas))}
            {row('الإجمالي المستحق لهذا المورد', sar(group.total_halalas), true)}
            <p className="muted" style={{ fontSize: 12, margin: '8px 0 0' }}>يُدفع المبلغ مباشرة لحساب المورد «{group.supplier_name}» عبر بوابة دفعه، وتُصدر فاتورة المبيعات باسمه.</p>
          </> : <>
            {row('إجمالي المنتجات', sar(total))}
            {legacyDelivery > 0 && row('التوصيل', sar(legacyDelivery))}
            {row('ضريبة القيمة المضافة (15%)', sar(legacyGrand - legacyBase))}
            {row('الإجمالي شامل الضريبة', sar(legacyGrand), true)}
          </>}
        </div>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        {(() => {
          const need: string[] = []
          if (address.trim().length < 6) need.push('العنوان التفصيلي')
          if (name.trim().length < 2) need.push('اسم المستلم')
          if (phone.replace(/\D/g, '').length < 9) need.push('رقم الجوال')
          return !busy && need.length > 0 ? <div className="note" style={{ margin: '10px 0' }}>أكمل الحقول التالية للمتابعة: {need.join('، ')}.</div> : null
        })()}
        <button className="btn" style={{ width: '100%' }} onClick={submit}
          disabled={busy || !quote || (direct && !group) || address.trim().length < 6 || name.trim().length < 2 || phone.replace(/\D/g, '').length < 9}>
          {busy ? 'جارٍ التحويل للدفع…' : direct && quote?.requires_split ? `ادفع طلب ${group?.supplier_name ?? 'المورد'} ←` : 'المتابعة للدفع ←'}
        </button>
        <p className="muted" style={{ fontSize: 13, marginTop: 8, textAlign: 'center' }}>الدفع الآمن عبر Tap · mada · Visa · Apple Pay</p>
      </div>
    </section>
  )
}
