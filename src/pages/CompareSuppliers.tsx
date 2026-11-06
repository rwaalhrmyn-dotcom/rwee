import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { CITIES } from '../lib/format'

export default function CompareSuppliers() {
  const [rows, setRows] = useState<any[]>([]); const [city, setCity] = useState(''); const [err, setErr] = useState<string | null>(null); const [loading, setLoading] = useState(true)
  useEffect(() => { (async () => {
    setLoading(true)
    let q = supabase.from('suppliers').select('id,name,cities,approval_status').eq('approval_status', 'approved').order('name')
    const { data, error } = await q
    if (error) setErr(error.message); else setRows(data || [])
    setLoading(false)
  })() }, [])
  const shown = city ? rows.filter(s => (s.cities || []).includes(city)) : rows
  return (
    <section style={{ padding: '32px 0' }}>
      <div className="eyebrow">— اختر الأنسب لك</div>
      <h2 style={{ color: 'var(--green)' }}>مقارنة الموردين</h2>
      <div style={{ display: 'flex', gap: 8, margin: '12px 0 20px' }}>
        <button className="badge" style={{ border: 0, cursor: 'pointer', background: city === '' ? 'var(--green)' : undefined, color: city === '' ? '#fff' : undefined }} onClick={() => setCity('')}>كل المدن</button>
        {Object.entries(CITIES).map(([k, v]) => <button key={k} className="badge" style={{ border: 0, cursor: 'pointer', background: city === k ? 'var(--green)' : undefined, color: city === k ? '#fff' : undefined }} onClick={() => setCity(k)}>{v}</button>)}
      </div>
      {loading && <p className="muted">جارٍ التحميل…</p>}
      {err && <div className="note">{err}</div>}
      {!loading && shown.length === 0 && <p className="muted">لا موردون معتمدون في هذا النطاق حالياً.</p>}
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(260px,1fr))' }}>
        {shown.map(s => (
          <div className="card" key={s.id}>
            <h3 style={{ margin: 0, color: 'var(--green)' }}>{s.name}</h3>
            <p className="muted" style={{ margin: '8px 0' }}>{(s.cities || []).map((c: string) => CITIES[c] || c).join('، ')}</p>
            <span className="badge">معتمد ✓</span>
          </div>
        ))}
      </div>
    </section>
  )
}
