import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { sar } from '../../lib/format'
import { Link } from 'react-router-dom'

export default function SupplierOrders() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [rows, setRows] = useState<any[]>([]); const [err, setErr] = useState<string | null>(null)
  useEffect(() => { (async () => {
    const { data: { session } } = await supabase.auth.getSession(); setAuthed(!!session)
    if (session) { const { data, error } = await supabase.rpc('supplier_order_summaries'); error ? setErr(error.message) : setRows(Array.isArray(data) ? data : []) }
  })() }, [])
  if (authed === false) return <section style={{ padding: '32px 0' }}><p className="muted">سجّل الدخول كمورد. <Link to="/supplier/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p></section>
  return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>طلبات منتجاتك</h2>
      {err && <div className="note">تعذّر الجلب: {err}</div>}
      {rows.length === 0 && !err && <p className="muted">لا طلبات بعد.</p>}
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(240px,1fr))' }}>
        {rows.map((o: any, i: number) => (
          <div className="card" key={i}><span className="badge">{o.status}</span>
            <div className="price" style={{ marginTop: 8 }}>{sar(o.subtotal_halalas || o.amount_halalas || 0)}</div>
            <div className="muted" style={{ fontSize: 13 }}>{o.city} · {o.item_count || o.items || ''} عناصر</div></div>
        ))}
      </div>
    </section>
  )
}
