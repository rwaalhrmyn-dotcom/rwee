import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { CITIES } from '../lib/format'

type Supplier = { id: string; name: string; cities: string[]; approval_status: string }

export default function Suppliers() {
  const [items, setItems] = useState<Supplier[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  useEffect(() => {
    (async () => {
      const { data, error } = await supabase.from('suppliers').select('id,name,cities,approval_status').order('name')
      if (error) setErr(error.message); else setItems(data || [])
      setLoading(false)
    })()
  }, [])
  return (
    <section style={{ padding: '24px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>الموردون المعتمدون</h2>
      {loading && <p className="muted">جارٍ التحميل…</p>}
      {err && <div className="note">تعذّر جلب الموردين: {err}</div>}
      {!loading && !err && items.length === 0 && <p className="muted">لا يوجد موردون معروضون حالياً.</p>}
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(260px,1fr))' }}>
        {items.map(s => (
          <div className="card" key={s.id}>
            <h3 style={{ margin: 0 }}>{s.name}</h3>
            <p className="muted" style={{ margin: '8px 0' }}>{(s.cities || []).map(c => CITIES[c] || c).join('، ')}</p>
            <span className="badge">{s.approval_status === 'approved' ? 'معتمد' : s.approval_status}</span>
          </div>
        ))}
      </div>
    </section>
  )
}
