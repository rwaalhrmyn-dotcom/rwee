import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { sar, CATEGORIES } from '../lib/format'
import { useCart } from '../context/CartContext'

type Product = { id: string; name: string; description: string; category: string; price_halalas: number; stock: number; unit: string; cities: string[] }

export default function Products() {
  const [items, setItems] = useState<Product[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [params] = useSearchParams()
  const [cat, setCat] = useState<string>(params.get('cat') || '')
  const { add } = useCart()

  useEffect(() => {
    (async () => {
      setLoading(true); setErr(null)
      let q = supabase.from('products').select('id,name,description,category,price_halalas,stock,unit,cities').order('name')
      if (cat) q = q.eq('category', cat)
      const { data, error } = await q
      if (error) setErr(error.message); else setItems(data || [])
      setLoading(false)
    })()
  }, [cat])

  return (
    <section style={{ padding: '24px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>تسوّق المنتجات</h2>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', margin: '12px 0 20px' }}>
        <button className={'badge'} style={{ border: 0, cursor: 'pointer', background: cat === '' ? 'var(--green)' : undefined, color: cat === '' ? '#fff' : undefined }} onClick={() => setCat('')}>الكل</button>
        {Object.entries(CATEGORIES).map(([k, v]) => (
          <button key={k} className="badge" style={{ border: 0, cursor: 'pointer', background: cat === k ? 'var(--green)' : undefined, color: cat === k ? '#fff' : undefined }} onClick={() => setCat(k)}>{v}</button>
        ))}
      </div>
      {loading && <p className="muted">جارٍ التحميل…</p>}
      {err && <div className="note">تعذّر جلب المنتجات: {err}</div>}
      {!loading && !err && items.length === 0 && <p className="muted">لا توجد منتجات متاحة حالياً.</p>}
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(240px,1fr))' }}>
        {items.map(p => (
          <div className="card" key={p.id}>
            <span className="badge">{CATEGORIES[p.category] || p.category}</span>
            <h3 style={{ margin: '10px 0 4px' }}>{p.name}</h3>
            <p className="muted" style={{ minHeight: 40, fontSize: 14 }}>{p.description}</p>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: 8 }}>
              <span className="price">{sar(p.price_halalas)}</span>
              <span className="muted" style={{ fontSize: 13 }}>{p.unit} · مخزون {p.stock}</span>
            </div>
            <button className="btn" style={{ width: '100%', marginTop: 12 }} disabled={p.stock <= 0}
              onClick={() => add({ id: p.id, name: p.name, price_halalas: p.price_halalas })}>
              {p.stock > 0 ? 'أضف إلى السلة' : 'غير متوفر'}
            </button>
          </div>
        ))}
      </div>
    </section>
  )
}
