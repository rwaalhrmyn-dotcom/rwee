import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { sar, CATEGORIES } from '../../lib/format'
import { Link } from 'react-router-dom'

export default function SupplierInventory() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [rows, setRows] = useState<any[]>([])
  const [err, setErr] = useState<string | null>(null)
  const [msg, setMsg] = useState<string | null>(null)

  const load = async () => {
    const { data, error } = await supabase.rpc('supplier_products')
    if (error) setErr(error.message); else setRows(Array.isArray(data) ? data : [])
  }
  useEffect(() => {
    (async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setAuthed(!!session); if (session) await load()
    })()
  }, [])

  const adjust = async (p: any, delta: number) => {
    setMsg(null)
    const { error } = await supabase.rpc('supplier_adjust_stock', { p_product_id: p.id, p_delta: delta, p_expected_version: p.version ?? p.stock_version ?? 0 })
    if (error) setMsg('تعذّر تعديل المخزون: ' + error.message); else { setMsg('تم تحديث المخزون'); await load() }
  }

  if (authed === false) return <section style={{ padding: '32px 0' }}><p className="muted">سجّل الدخول كمورد. <Link to="/supplier/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p></section>
  return (
    <section style={{ padding: '32px 0' }}>
      <div style={{display:"flex",justifyContent:"space-between",alignItems:"center",flexWrap:"wrap",gap:8}}><h2 style={{ color: 'var(--green)' }}>إدارة المنتجات والمخزون</h2><div style={{display:"flex",gap:8}}><Link className="btn" to="/supplier/products/new">+ منتج</Link><Link className="btn ghost" to="/supplier/import">استيراد Excel</Link><Link className="btn ghost" to="/supplier/shipping">الشحن</Link></div></div>
      {err && <div className="note">تعذّر الجلب: {err}</div>}
      {msg && <div className="note">{msg}</div>}
      {rows.length === 0 && !err && <p className="muted">لا منتجات بعد.</p>}
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(260px,1fr))' }}>
        {rows.map(p => (
          <div className="card" key={p.id}>
            <span className="badge">{CATEGORIES[p.category] || p.category}</span>
            <h3 style={{ margin: '8px 0 4px' }}>{p.name}</h3>
            <div className="price">{sar(p.supplier_price_halalas ?? p.price_halalas)}</div>
            <div className="muted" style={{ fontSize: 12, margin: '2px 0' }}>صافي سعرك · العرض للعميل {sar(p.price_halalas)}</div>
            <div className="muted" style={{ fontSize: 13, margin: '6px 0' }}>المخزون: {p.stock}</div>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn ghost" style={{ padding: '6px 14px' }} onClick={() => adjust(p, -1)}>−</button>
              <button className="btn ghost" style={{ padding: '6px 14px' }} onClick={() => adjust(p, +1)}>+</button>
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}
