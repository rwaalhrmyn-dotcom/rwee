import { useEffect, useState } from 'react'
import { useSearchParams, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'

export default function PaymentCallback() {
  const [params] = useSearchParams()
  const orderId = params.get('order')
  const tapStatus = params.get('tap_id') ? 'processing' : null
  const [status, setStatus] = useState<'checking' | 'paid' | 'pending'>('checking')

  useEffect(() => {
    let tries = 0
    const check = async () => {
      if (!orderId) { setStatus('pending'); return }
      const { data } = await supabase.from('orders').select('payment_status').eq('id', orderId).maybeSingle()
      if (data?.payment_status === 'paid') { setStatus('paid'); return }
      if (++tries < 6) setTimeout(check, 2500); else setStatus('pending')
    }
    check()
  }, [orderId])

  return (
    <section style={{ padding: '48px 0', maxWidth: 520, textAlign: 'center' }}>
      {status === 'checking' && <><h2 style={{ color: 'var(--green)' }}>جارٍ تأكيد الدفع…</h2><p className="muted">لحظات من فضلك.</p></>}
      {status === 'paid' && <>
        <div style={{ fontSize: 48 }}>✅</div>
        <h2 style={{ color: 'var(--green)' }}>تم الدفع بنجاح</h2>
        <p className="muted">شكراً لك. طلبك قيد التجهيز.</p>
        <Link className="btn" to="/customer">عرض طلباتي ←</Link>
      </>}
      {status === 'pending' && <>
        <div style={{ fontSize: 48 }}>⏳</div>
        <h2 style={{ color: 'var(--green)' }}>الدفع قيد المعالجة</h2>
        <p className="muted">إن تمّ خصم المبلغ فسيُؤكَّد طلبك تلقائياً خلال لحظات. تابع حالته من حسابك.</p>
        <Link className="btn" to="/customer">حسابي ←</Link>
      </>}
    </section>
  )
}
