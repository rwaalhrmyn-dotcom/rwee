import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { sar } from '../../lib/format'

export default function OrderDetail() {
  const { id } = useParams()
  const [order, setOrder] = useState<any>(null)
  const [items, setItems] = useState<any[]>([])
  const [err, setErr] = useState<string | null>(null)
  useEffect(() => { (async () => {
    const o = await supabase.from('orders').select('*').eq('id', id).maybeSingle()
    if (o.error) { setErr(o.error.message); return }
    setOrder(o.data)
    const it = await supabase.from('order_items').select('product_name,unit_price_halalas,quantity').eq('order_id', id)
    if (!it.error) setItems(it.data || [])
  })() }, [id])
  if (err) return <section style={{ padding: '32px 0' }}><div className="note">تعذّر جلب الطلب: {err}</div></section>
  if (!order) return <section style={{ padding: '32px 0' }}><p className="muted">جارٍ التحميل…</p></section>
  const total = (order.subtotal_halalas || 0) + (order.delivery_halalas || 0)
  return (
    <section style={{ padding: '32px 0', maxWidth: 560 }}>
      <Link to="/customer" className="muted">→ طلباتي</Link>
      <h2 style={{ color: 'var(--green)' }}>تفاصيل الطلب</h2>
      <div className="card">
        <span className="badge">{order.status}</span>
        <p className="muted" style={{ margin: '8px 0' }}>{order.recipient_name} · {order.phone} · {order.address}</p>
        {items.map((it, i) => (
          <div key={i} style={{ display: 'flex', justifyContent: 'space-between', padding: '8px 0', borderBottom: '1px solid var(--border)' }}>
            <span>{it.product_name} ×{it.quantity}</span><span className="price">{sar(it.unit_price_halalas * it.quantity)}</span>
          </div>
        ))}
        <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8 }}><span className="muted">المنتجات</span><span>{sar(order.subtotal_halalas)}</span></div>
        <div style={{ display: 'flex', justifyContent: 'space-between' }}><span className="muted">التوصيل</span><span>{order.delivery_halalas != null ? sar(order.delivery_halalas) : 'يُحتسب لاحقاً'}</span></div>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontWeight: 700, marginTop: 6 }}><span>الإجمالي</span><span className="price">{sar(total)}</span></div>
      </div>
    </section>
  )
}
