import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'

export default function Shipping() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [rows, setRows] = useState<any[]>([]); const [err, setErr] = useState<string | null>(null); const [msg, setMsg] = useState<string | null>(null)
  const load = async () => { const { data, error } = await supabase.rpc('shipping_candidates'); error ? setErr(error.message) : setRows(Array.isArray(data) ? data : []) }
  useEffect(() => { (async () => { const { data: { session } } = await supabase.auth.getSession(); setAuthed(!!session); if (session) await load() })() }, [])
  const prepare = async (r: any) => {
    setMsg(null)
    const { error } = await supabase.rpc('prepare_oto_shipment', {
      p_order_id: r.order_id, p_supplier_id: r.supplier_id,
      p_pickup_code: 'PICKUP-' + r.order_id.slice(0, 6), p_package_weight: 1, p_package_count: 1,
    })
    if (error) setMsg('تعذّر تجهيز الشحنة: ' + error.message); else { setMsg('تم تجهيز الشحنة عبر OTO'); await load() }
  }
  if (authed === false) return <section style={{ padding: '32px 0' }}><p className="muted">يلزم دخول مخوّل. <Link to="/supplier/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p></section>
  return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>تجهيز الشحنات (OTO)</h2>
      {err && <div className="note">{err}</div>}{msg && <div className="note">{msg}</div>}
      {rows.length === 0 && !err && <p className="muted">لا طلبات جاهزة للشحن.</p>}
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(260px,1fr))' }}>
        {rows.map((r, i) => (
          <div className="card" key={i}>
            <strong>{r.supplier_name}</strong>
            <div className="muted" style={{ fontSize: 13, margin: '6px 0' }}>طلب {String(r.order_id).slice(0, 8)}…</div>
            <button className="btn" style={{ width: '100%' }} onClick={() => prepare(r)}>تجهيز شحنة OTO ←</button>
          </div>
        ))}
      </div>
    </section>
  )
}
