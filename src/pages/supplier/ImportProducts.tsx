import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'

// صفوف متوقعة (عناوين عربية أو إنجليزية): name/الاسم, description/الوصف, category/الفئة, unit/الوحدة, price_halalas أو price/السعر, stock/المخزون, cities/المدن
const CATMAP: Record<string, string> = { 'مياه': 'water', 'مصاحف': 'quran', 'مستلزمات': 'supplies', 'أغذية': 'food', 'تجهيزات': 'equipment' }
const CITYMAP: Record<string, string> = { 'مكة': 'makkah', 'المدينة': 'madinah', 'makkah': 'makkah', 'madinah': 'madinah' }

function toRow(r: any) {
  const g = (...keys: string[]) => { for (const k of keys) { const v = r[k] ?? r[k?.trim()]; if (v != null && v !== '') return v } return '' }
  const cat = String(g('category', 'الفئة', 'القسم')).trim()
  const priceRaw = String(g('price_halalas', 'price', 'السعر', 'السعر_هللة')).replace(/[^\d.]/g, '')
  let price = Number(priceRaw || 0)
  // if price looks like SAR (has decimal or small), convert to halalas
  if (String(g('price', 'السعر')) && !g('price_halalas')) price = Math.round(price * 100)
  const citiesRaw = String(g('cities', 'المدن', 'المدينة')).split(/[,،]/).map(s => s.trim()).filter(Boolean)
  const cities = citiesRaw.map(c => CITYMAP[c] || c).filter(c => c === 'makkah' || c === 'madinah')
  return {
    name: String(g('name', 'الاسم', 'اسم المنتج')).trim(),
    description: String(g('description', 'الوصف')).trim() || '-',
    category: CATMAP[cat] || cat || 'supplies',
    unit: String(g('unit', 'الوحدة')).trim() || 'حبة',
    price_halalas: price,
    stock: Number(String(g('stock', 'المخزون', 'الكمية')).replace(/\D/g, '') || 0),
    cities: cities.length ? cities : ['makkah'],
    active: true,
  }
}

export default function ImportProducts() {
  const [supplierId, setSupplierId] = useState<string | null>(null)
  const [supplierCities, setSupplierCities] = useState<string[]>(['makkah', 'madinah'])
  const [rows, setRows] = useState<any[]>([])
  const [msg, setMsg] = useState<string | null>(null); const [busy, setBusy] = useState(false)
  useEffect(() => { (async () => {
    const { data } = await supabase.rpc('my_supplier_accounts')
    const s = Array.isArray(data) && data[0] ? data[0] : null
    if (s) { setSupplierId(s.id || s.supplier_id); if (Array.isArray(s.cities) && s.cities.length) setSupplierCities(s.cities) }
  })() }, [])

  const onFile = async (file: File) => {
    setMsg(null)
    const XLSX = await import('xlsx')
    const buf = await file.arrayBuffer()
    const wb = XLSX.read(buf, { type: 'array' })
    const ws = wb.Sheets[wb.SheetNames[0]]
    const json: any[] = XLSX.utils.sheet_to_json(ws, { defval: '' })
    const parsed = json.map(toRow).filter(r => r.name && r.price_halalas > 0)
    setRows(parsed)
    if (parsed.length === 0) setMsg('لم يتم التعرّف على صفوف صالحة. تأكد من الأعمدة: الاسم، الفئة، الوحدة، السعر، المخزون، المدن.')
  }
  const importAll = async () => {
    if (!supplierId) { setMsg('لا منشأة معتمدة.'); return }
    if (rows.length === 0 || rows.length > 200) { setMsg('عدد الصفوف يجب أن يكون بين 1 و200.'); return }
    setBusy(true); setMsg(null)
    // Clamp each row's cities to the supplier's approved cities (fallback to all of them)
    // so an out-of-range city in the file can never fail the whole import.
    const safeRows = rows.map(r => {
      const cities = (Array.isArray(r.cities) ? r.cities : []).filter((c: string) => supplierCities.includes(c))
      return { ...r, cities: cities.length ? cities : supplierCities }
    })
    const { data, error } = await supabase.rpc('supplier_import_products', { p_supplier_id: supplierId, p_rows: safeRows, p_request_id: crypto.randomUUID() })
    setBusy(false)
    if (error) setMsg('تعذّر الاستيراد: ' + error.message)
    else { setMsg(`تم استيراد ${Array.isArray(data) ? data.length : rows.length} منتجاً بنجاح.`); setRows([]) }
  }

  return (
    <section style={{ padding: '32px 0', maxWidth: 760 }}>
      <Link to="/supplier/inventory" className="muted">→ المخزون</Link>
      <h2 style={{ color: 'var(--green)' }}>استيراد المنتجات (Excel / CSV)</h2>
      <div className="card">
        <p className="muted">ارفع ملف Excel (.xlsx) أو CSV يحتوي الأعمدة: <strong>الاسم، الوصف، الفئة، الوحدة، السعر، المخزون، المدن</strong>. أو أدخل المنتجات يدوياً من <Link to="/supplier/products/new" style={{ color: 'var(--green)' }}>هنا</Link>.</p>
        <p className="muted" style={{ fontSize: 13 }}>السعر الذي تُدخله هو <strong>صافي سعرك</strong>؛ تُضاف رسوم المنصة 35% تلقائياً إلى سعر العرض للعميل.</p>
        <input type="file" accept=".xlsx,.xls,.csv" onChange={e => e.target.files?.[0] && onFile(e.target.files[0])} />
        {msg && <div className="note" style={{ margin: '12px 0' }}>{msg}</div>}
        {rows.length > 0 && (
          <>
            <p style={{ marginTop: 14 }}>معاينة ({rows.length} منتج):</p>
            <div style={{ maxHeight: 260, overflow: 'auto' }}>
              {rows.slice(0, 50).map((r, i) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid var(--border)', fontSize: 14 }}>
                  <span>{r.name} · {r.category} · {r.unit}</span><span className="muted">صافي {(r.price_halalas / 100).toFixed(2)} ← للعميل {(Math.round(r.price_halalas * 1.35) / 100).toFixed(2)} ر.س · مخزون {r.stock}</span>
                </div>
              ))}
            </div>
            <button className="btn" style={{ width: '100%', marginTop: 14 }} disabled={busy} onClick={importAll}>استيراد {rows.length} منتج ←</button>
          </>
        )}
      </div>
      <div className="card" style={{ marginTop: 16 }}>
        <h3 style={{ marginTop: 0 }}>نموذج العناوين</h3>
        <code style={{ fontSize: 13 }}>الاسم, الوصف, الفئة, الوحدة, السعر, المخزون, المدن</code>
        <p className="muted" style={{ fontSize: 13 }}>مثال: مياه 330مل, كرتون 40 حبة, مياه, كرتون, 15, 500, مكة،المدينة</p>
      </div>
    </section>
  )
}
