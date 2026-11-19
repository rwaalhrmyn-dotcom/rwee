import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { riyal } from '../lib/finance'

// The customer pays the supplier directly: through the supplier's own payment link or cash on
// delivery. Rawaa never receives the money; the supplier confirms receipt from its dashboard.
export default function OrderPayment() {
  const { id } = useParams()
  const [o, setO] = useState<any>(null)
  const [msg, setMsg] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const load = async () => {
    const { data, error } = await supabase.rpc('order_payment_options', { p_order: id })
    if (error) setMsg('تعذّر عرض خيارات الدفع: ' + error.message); else setO(data)
  }
  useEffect(() => { load() }, [id])

  const choose = async (method: 'supplier_link' | 'cod') => {
    setBusy(true); setMsg(null)
    const { error } = await supabase.rpc('choose_order_payment_method', { p_order: id, p_method: method })
    setBusy(false)
    if (error) { setMsg('تعذّر حفظ طريقة الدفع: ' + error.message); return }
    if (method === 'supplier_link' && o?.payment_link) window.open(o.payment_link, '_blank', 'noopener,noreferrer')
    await load()
  }

  if (!o) return <section style={{ padding: '32px 0' }}>{msg ? <div className="note">{msg}</div> : <p className="muted">جارٍ التحميل…</p>}</section>
  const paid = o.payment_status === 'paid'
  return (
    <section style={{ padding: '32px 0', maxWidth: 560 }}>
      <h2 style={{ color: 'var(--green)' }}>الدفع للمورد</h2>
      <div className="card">
        <p style={{ margin: 0 }}>المورد: <strong>{o.supplier_name}</strong></p>
        <p style={{ margin: '6px 0 0' }}>المبلغ المستحق: <strong className="price">{riyal(o.payable_halalas)} ر.س</strong></p>
        <p className="muted" style={{ fontSize: 12 }}>يُدفع المبلغ للمورد مباشرة ولا يمر بحساب منصة رواء.</p>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}

        {paid ? <div className="note" style={{ borderColor: 'var(--green)' }}>✓ أكّد المورد استلام المبلغ. يجري تجهيز طلبك.</div> : <>
          {o.payment_method && <div className="note" style={{ margin: '10px 0' }}>
            {o.payment_method === 'cod'
              ? 'اخترت الدفع عند الاستلام. جهّز المبلغ للمورد أو مندوب التوصيل عند التسليم.'
              : 'اخترت الدفع عبر رابط المورد. بعد إتمام الدفع سيؤكد المورد استلام المبلغ ويبدأ تجهيز طلبك.'}
          </div>}
          {o.instructions && <p style={{ fontSize: 13 }}>تعليمات المورد: {o.instructions}</p>}
          <div style={{ display: 'grid', gap: 8, marginTop: 10 }}>
            {o.payment_link && <button className="btn" disabled={busy} onClick={() => choose('supplier_link')}>الدفع عبر رابط المورد ←</button>}
            {o.accepts_cod && <button className="btn ghost" disabled={busy} onClick={() => choose('cod')}>الدفع عند الاستلام</button>}
            {!o.payment_link && !o.accepts_cod && <div className="note">المورد لا يستقبل الدفع حالياً. تواصل معنا.</div>}
          </div>
        </>}
        <div style={{ marginTop: 14 }}><Link to="/customer" className="muted">طلباتي ←</Link></div>
      </div>
    </section>
  )
}
