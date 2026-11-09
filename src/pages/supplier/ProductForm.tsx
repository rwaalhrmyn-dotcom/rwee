import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { CATEGORIES, CITIES } from '../../lib/format'
import { useNavigate, Link } from 'react-router-dom'

export default function ProductForm() {
  const [supplierId, setSupplierId] = useState<string | null>(null)
  const [supplierCities, setSupplierCities] = useState<string[]>([])
  const [f, setF] = useState({ name: '', description: '', unit: '', category: 'water', price: '', stock: '' })
  const [cities, setCities] = useState<string[]>([])
  const [active, setActive] = useState(true)
  const [msg, setMsg] = useState<string | null>(null); const [busy, setBusy] = useState(false)
  const nav = useNavigate()
  useEffect(() => { (async () => {
    const { data } = await supabase.rpc('my_supplier_accounts')
    const s = Array.isArray(data) && data[0] ? data[0] : null
    if (s) { setSupplierId(s.id || s.supplier_id); setSupplierCities(s.cities || Object.keys(CITIES)) }
  })() }, [])
  const toggle = (c: string) => setCities(p => p.includes(c) ? p.filter(x => x !== c) : [...p, c])
  const save = async () => {
    if (!supplierId) { setMsg('لا منشأة معتمدة مرتبطة.'); return }
    setBusy(true); setMsg(null)
    const { error } = await supabase.rpc('supplier_save_product', {
      p_product_id: null, p_supplier_id: supplierId, p_expected_version: 0,
      p_data: { name: f.name, description: f.description, unit: f.unit, category: f.category,
        price_halalas: Math.round(Number(f.price) * 100), stock: Number(f.stock), cities, active },
    })
    setBusy(false)
    if (error) setMsg('تعذّر الحفظ: ' + error.message); else nav('/supplier/inventory')
  }
  const cityOptions = supplierCities.length ? supplierCities : Object.keys(CITIES)
  return (
    <section style={{ padding: '32px 0', maxWidth: 560 }}>
      <Link to="/supplier/inventory" className="muted">→ المخزون</Link>
      <h2 style={{ color: 'var(--green)' }}>إضافة منتج</h2>
      <div className="card">
        <div className="field"><label>اسم المنتج</label><input value={f.name} onChange={e => setF({ ...f, name: e.target.value })} /></div>
        <div className="field"><label>الوصف</label><input value={f.description} onChange={e => setF({ ...f, description: e.target.value })} /></div>
        <div className="field"><label>الفئة</label>
          <select value={f.category} onChange={e => setF({ ...f, category: e.target.value })}>
            {Object.entries(CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select></div>
        <div className="field"><label>الوحدة</label><input value={f.unit} onChange={e => setF({ ...f, unit: e.target.value })} placeholder="كرتون / حبة / كيس" /></div>
        <div className="field"><label>صافي سعرك بالريال (ر.س)</label><input inputMode="decimal" value={f.price} onChange={e => setF({ ...f, price: e.target.value.replace(/[^\d.]/g, '').replace(/(\..*)\./g, '$1') })} placeholder="مثال: 15 أو 12.50" />
          {f.price && Number(f.price) > 0 && (
            <p className="muted" style={{ fontSize: 13, marginTop: 6 }}>سعر العرض للعميل (شامل رسوم المنصة 35% والضريبة عند الدفع): <strong style={{ color: 'var(--green)' }}>{(Number(f.price) * 1.35).toFixed(2)} ر.س</strong> · يُحسب تلقائياً.</p>
          )}</div>
        <div className="field"><label>المخزون</label><input value={f.stock} onChange={e => setF({ ...f, stock: e.target.value.replace(/\D/g, '') })} /></div>
        <div className="field"><label>مدن العرض</label>
          <div style={{ display: 'flex', gap: 8 }}>
            {cityOptions.map(k => <button key={k} className="badge" style={{ border: 0, cursor: 'pointer', background: cities.includes(k) ? 'var(--green)' : undefined, color: cities.includes(k) ? '#fff' : undefined }} onClick={() => toggle(k)}>{CITIES[k] || k}</button>)}
          </div></div>
        <label style={{ display: 'flex', gap: 8, alignItems: 'center' }}><input type="checkbox" checked={active} onChange={e => setActive(e.target.checked)} /> متاح للعرض</label>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%', marginTop: 10 }} disabled={busy || f.name.length < 2 || !f.price || cities.length === 0} onClick={save}>حفظ المنتج ←</button>
      </div>
    </section>
  )
}
