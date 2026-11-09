import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { CITIES } from '../../lib/format'
import { Link } from 'react-router-dom'

type Acct = {
  id: string; name: string; approval_status: string; cities: string[]
  national_address: string | null; warehouse_city: string | null
  warehouse_name: string | null; warehouse_address: string | null
  products_count: number; active_products: number; low_stock: number
}

const STATUS: Record<string, { label: string; color: string }> = {
  approved: { label: 'معتمد', color: 'var(--green)' },
  pending: { label: 'قيد المراجعة', color: '#b8860b' },
  blocked: { label: 'محظور', color: '#b00020' },
}

export default function SupplierHome() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [accounts, setAccounts] = useState<Acct[]>([])
  const [err, setErr] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  useEffect(() => {
    (async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setAuthed(!!session)
      if (session) {
        const { data, error } = await supabase.rpc('my_supplier_dashboard')
        if (error) setErr(error.message); else setAccounts(Array.isArray(data) ? data : [])
      }
      setLoading(false)
    })()
  }, [])

  if (authed === false) return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>بوابة المورد</h2>
      <p className="muted">سجّل الدخول لإدارة منتجاتك ومخزونك وطلباتك وأسعارك بالريال.</p>
      <Link className="btn" to="/supplier/login">دخول المورد ←</Link>
    </section>
  )

  const cityLabel = (k?: string | null) => (k && CITIES[k]) || k || '—'

  return (
    <section style={{ padding: '32px 0', maxWidth: 760 }}>
      <h2 style={{ color: 'var(--green)' }}>لوحة المورد</h2>
      {err && <div className="note">تعذّر جلب حساباتك: {err}</div>}
      {loading && !err && <p className="muted">جارٍ تحميل بيانات منشأتك…</p>}

      {!loading && accounts.length === 0 && !err && (
        <div className="card">
          <p className="muted" style={{ margin: 0 }}>لا توجد منشأة مرتبطة بحسابك بعد.</p>
          <Link className="btn" to="/supplier/register" style={{ marginTop: 12 }}>إنشاء طلب انضمام ←</Link>
        </div>
      )}

      {accounts.map((a) => {
        const st = STATUS[a.approval_status] || { label: a.approval_status, color: 'var(--muted)' }
        const approved = a.approval_status === 'approved'
        return (
          <div className="card" key={a.id} style={{ marginBottom: 16 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
              <strong style={{ fontSize: 17 }}>{a.name}</strong>
              <span className="badge" style={{ background: st.color, color: '#fff' }}>{st.label}</span>
            </div>
            <div className="muted" style={{ fontSize: 13, marginTop: 6 }}>
              مدن العرض: {(a.cities || []).map(cityLabel).join('، ') || '—'}
            </div>

            {!approved && (
              <div className="note" style={{ margin: '12px 0 0' }}>
                منشأتك {st.label}. تُفعّل إدارة المخزون والأسعار بعد اعتماد الإدارة لمطابقة السجل والعنوان الوطني والآيبان والمستندات.
              </div>
            )}

            {approved && (
              <>
                {/* Warehouse */}
                <div style={{ marginTop: 14, padding: 12, border: '1px solid var(--line)', borderRadius: 12, background: 'var(--bg-soft, #f7faf8)' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <strong style={{ color: 'var(--green)', fontSize: 14 }}>🏬 مستودعك</strong>
                    <span className="muted" style={{ fontSize: 12 }}>{cityLabel(a.warehouse_city)}</span>
                  </div>
                  <div className="muted" style={{ fontSize: 13, marginTop: 6 }}>
                    {a.warehouse_name || 'المستودع الرئيسي'}
                    {a.warehouse_address ? <> · {a.warehouse_address}</> : (a.national_address ? <> · {a.national_address}</> : null)}
                  </div>
                </div>

                {/* Inventory stats */}
                <div style={{ display: 'flex', gap: 10, marginTop: 12, flexWrap: 'wrap' }}>
                  <Stat label="منتجاتك" value={a.products_count} />
                  <Stat label="معروضة الآن" value={a.active_products} />
                  <Stat label="مخزون منخفض (≤5)" value={a.low_stock} warn={a.low_stock > 0} />
                </div>
                {a.low_stock > 0 && (
                  <div className="note" style={{ margin: '10px 0 0' }}>
                    لديك {a.low_stock} منتج بمخزون منخفض — حدّث الكميات من المخزون لتفادي نفادها.
                  </div>
                )}

                <div style={{ display: 'flex', gap: 8, marginTop: 14, flexWrap: 'wrap' }}>
                  <Link className="btn" to="/supplier/inventory">إدارة المخزون والأسعار (ر.س)</Link>
                  <Link className="btn ghost" to="/supplier/products/new">+ منتج</Link>
                  <Link className="btn ghost" to="/supplier/import">استيراد Excel</Link>
                  <Link className="btn ghost" to="/supplier/orders">الطلبات</Link>
                </div>
                <p className="muted" style={{ fontSize: 12, marginTop: 10 }}>
                  تُدخل <strong>صافي سعرك بالريال</strong>؛ تُضاف رسوم المنصة والضريبة تلقائياً على سعر العميل.
                </p>
              </>
            )}
          </div>
        )
      })}

      <div style={{ display: 'flex', gap: 8, marginTop: 8, flexWrap: 'wrap' }}>
        <Link className="btn ghost" to="/supplier/contract">عقد المورد</Link>
        <Link className="btn ghost" to="/supplier/register">إضافة منشأة أخرى</Link>
        <button className="btn ghost" onClick={() => supabase.auth.signOut().then(() => location.reload())}>تسجيل الخروج</button>
      </div>
    </section>
  )
}

function Stat({ label, value, warn }: { label: string; value: number; warn?: boolean }) {
  return (
    <div style={{ flex: '1 1 120px', minWidth: 110, padding: 12, border: '1px solid var(--line)', borderRadius: 12, textAlign: 'center' }}>
      <div style={{ fontSize: 22, fontWeight: 700, color: warn ? '#b00020' : 'var(--green)' }}>{value}</div>
      <div className="muted" style={{ fontSize: 12, marginTop: 2 }}>{label}</div>
    </div>
  )
}
