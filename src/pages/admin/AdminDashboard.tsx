import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { sar } from '../../lib/format'
import { Link } from 'react-router-dom'

const ORDER_STATUS: Record<string, string> = {
  pending: 'بانتظار المراجعة', confirmed: 'مؤكّد', preparing: 'قيد التجهيز',
  out_for_delivery: 'قيد التوصيل', delivered: 'تم التسليم', cancelled: 'ملغي',
}
const TABS = ['overview', 'orders', 'customers', 'suppliers', 'products', 'deliveries', 'inquiries', 'staff', 'audit', 'settings'] as const
type Tab = typeof TABS[number]
const TAB_LABEL: Record<Tab, string> = {
  overview: 'نظرة عامة', orders: 'الطلبات', customers: 'العملاء', suppliers: 'الموردون',
  products: 'المنتجات والأسعار', deliveries: 'التوصيل والشحن', inquiries: 'الاستفسارات',
  staff: 'طاقم الإدارة', audit: 'سجل التدقيق', settings: 'الإعدادات',
}

export default function AdminDashboard() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [tab, setTab] = useState<Tab>('overview')
  const [err, setErr] = useState<string | null>(null)
  const [metrics, setMetrics] = useState<any>(null)

  useEffect(() => { (async () => {
    const { data: { session } } = await supabase.auth.getSession(); setAuthed(!!session)
    if (session) { const m = await supabase.rpc('admin_metrics'); if (m.error) setErr(m.error.message); else setMetrics(m.data) }
  })() }, [])

  if (authed === false) return <section style={{ padding: '32px 0' }}><p className="muted">يلزم دخول إداري. <Link to="/admin/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p></section>

  return (
    <section style={{ padding: '24px 0' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
        <h2 style={{ color: 'var(--green)', margin: 0 }}>لوحة التحكم</h2>
        <button className="btn ghost" style={{ padding: '7px 14px' }} onClick={() => supabase.auth.signOut().then(() => location.href = '/admin/login')}>خروج</button>
      </div>
      {err && <div className="note" style={{ margin: '12px 0' }}>خطأ: {err}</div>}

      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', margin: '16px 0' }}>
        {TABS.map(t => (
          <button key={t} onClick={() => setTab(t)} className="badge" style={{
            border: 0, cursor: 'pointer', padding: '9px 14px',
            background: tab === t ? 'var(--green)' : undefined, color: tab === t ? '#fff' : undefined,
          }}>{TAB_LABEL[t]}</button>
        ))}
      </div>

      {tab === 'overview' && <Overview m={metrics} />}
      {tab === 'orders' && <Orders />}
      {tab === 'customers' && <Customers />}
      {tab === 'suppliers' && <Suppliers />}
      {tab === 'products' && <Products />}
      {tab === 'deliveries' && <Deliveries />}
      {tab === 'inquiries' && <Inquiries />}
      {tab === 'staff' && <Staff />}
      {tab === 'audit' && <Audit />}
      {tab === 'settings' && <Settings />}
    </section>
  )
}

function Stat({ label, value }: { label: string; value: any }) {
  return <div className="card" style={{ textAlign: 'center' }}><div style={{ fontSize: 26, fontWeight: 700, color: 'var(--green)' }}>{value}</div><div className="muted" style={{ fontSize: 13 }}>{label}</div></div>
}
function Overview({ m }: { m: any }) {
  if (!m) return <p className="muted">جارٍ التحميل…</p>
  return (
    <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(150px,1fr))' }}>
      <Stat label="إجمالي الطلبات" value={m.orders_total} />
      <Stat label="طلبات معلّقة" value={m.orders_pending} />
      <Stat label="طلبات مدفوعة" value={m.orders_paid} />
      <Stat label="الإيرادات المدفوعة" value={sar(m.revenue_halalas)} />
      <Stat label="طلبات موردين معلّقة" value={m.applications_pending} />
      <Stat label="موردون معتمدون" value={m.suppliers_approved} />
      <Stat label="منتجات نشطة" value={m.products_active} />
      <Stat label="استفسارات مفتوحة" value={m.inquiries_open} />
    </div>
  )
}

function useLoader(rpc: string, args?: any) {
  const [rows, setRows] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const load = async () => {
    setLoading(true)
    const { data, error } = await supabase.rpc(rpc, args)
    setLoading(false)
    if (error) setErr(error.message); else { setErr(null); setRows(Array.isArray(data) ? data : []) }
  }
  useEffect(() => { load() }, [])
  return { rows, loading, err, reload: load }
}

function Orders() {
  const { rows, loading, err, reload } = useLoader('admin_orders')
  const [open, setOpen] = useState<string | null>(null)
  const [items, setItems] = useState<any[]>([])
  const [msg, setMsg] = useState<string | null>(null)

  const showItems = async (id: string) => {
    if (open === id) { setOpen(null); return }
    setOpen(id); setItems([])
    const { data } = await supabase.rpc('admin_order_items', { p_order_id: id })
    setItems(Array.isArray(data) ? data : [])
  }
  const setStatus = async (id: string, status: string) => {
    setMsg(null)
    const { error } = await supabase.rpc('admin_set_order_status', { p_order_id: id, p_status: status })
    if (error) setMsg('تعذّر: ' + error.message); else reload()
  }
  const setPaid = async (id: string, paid: boolean) => {
    const { error } = await supabase.rpc('admin_set_order_paid', { p_order_id: id, p_paid: paid })
    if (error) setMsg('تعذّر: ' + error.message); else reload()
  }
  if (loading) return <p className="muted">جارٍ التحميل…</p>
  if (err) return <div className="note">خطأ: {err}</div>
  return (
    <div>
      {msg && <div className="note" style={{ marginBottom: 10 }}>{msg}</div>}
      {rows.length === 0 && <p className="muted">لا طلبات.</p>}
      {rows.map(o => (
        <div className="card" key={o.id} style={{ marginBottom: 10 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
            <div>
              <strong>{o.recipient_name}</strong> · <span className="muted">{o.phone}</span><br />
              <span className="muted" style={{ fontSize: 13 }}>{o.city} — {o.address}</span>
            </div>
            <div style={{ textAlign: 'end' }}>
              <div className="price">{sar(o.total_halalas)}</div>
              <span className="badge" style={{ background: o.payment_status === 'paid' ? 'var(--green)' : undefined, color: o.payment_status === 'paid' ? '#fff' : undefined }}>{o.payment_status === 'paid' ? 'مدفوع' : 'غير مدفوع'}</span>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center', marginTop: 10 }}>
            <select value={o.status} onChange={e => setStatus(o.id, e.target.value)} style={{ maxWidth: 170 }}>
              {Object.entries(ORDER_STATUS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
            <button className="btn ghost" style={{ padding: '6px 12px' }} onClick={() => setPaid(o.id, o.payment_status !== 'paid')}>{o.payment_status === 'paid' ? 'إلغاء الدفع' : 'تحديد مدفوع'}</button>
            <button className="btn ghost" style={{ padding: '6px 12px' }} onClick={() => showItems(o.id)}>{open === o.id ? 'إخفاء' : 'المنتجات'}</button>
            <span className="muted" style={{ fontSize: 12 }}>{new Date(o.created_at).toLocaleString('ar-SA')}</span>
          </div>
          {open === o.id && (
            <div style={{ marginTop: 10, borderTop: '1px solid var(--line)', paddingTop: 8 }}>
              {items.map((it, i) => <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 14, padding: '3px 0' }}><span>{it.product_name} × {it.quantity}</span><span className="muted">{sar(it.unit_price_halalas * it.quantity)}</span></div>)}
            </div>
          )}
        </div>
      ))}
    </div>
  )
}

function Suppliers() {
  const apps = useLoader('admin_applications')
  const sups = useLoader('admin_suppliers')
  const [msg, setMsg] = useState<string | null>(null)
  const decide = async (id: string, approve: boolean) => {
    setMsg(null)
    const { error } = await supabase.rpc('admin_decide_application', { p_id: id, p_approve: approve })
    if (error) setMsg('تعذّر: ' + error.message); else { apps.reload(); sups.reload() }
  }
  const setStatus = async (id: string, status: string) => {
    const { error } = await supabase.rpc('admin_set_supplier_status', { p_id: id, p_status: status })
    if (error) setMsg('تعذّر: ' + error.message); else sups.reload()
  }
  return (
    <div>
      {msg && <div className="note" style={{ marginBottom: 10 }}>{msg}</div>}
      <h3>طلبات الانضمام</h3>
      {apps.loading ? <p className="muted">جارٍ…</p> : apps.rows.filter(a => a.status === 'pending').length === 0 ? <p className="muted">لا طلبات معلّقة.</p> : apps.rows.filter(a => a.status === 'pending').map(a => (
        <div className="card" key={a.id} style={{ marginBottom: 10 }}>
          <strong>{a.business_name}</strong> <span className="badge">{a.category}</span>
          <div className="muted" style={{ fontSize: 13, margin: '6px 0' }}>سجل تجاري: {a.commercial_registration} · {a.city} · {a.phone}<br />IBAN: {a.iban || '—'} · {a.owner_email}</div>
          <div style={{ display: 'flex', gap: 8 }}>
            <button className="btn" style={{ padding: '6px 14px' }} onClick={() => decide(a.id, true)}>اعتماد ←</button>
            <button className="btn ghost" style={{ padding: '6px 14px' }} onClick={() => decide(a.id, false)}>رفض</button>
          </div>
        </div>
      ))}
      <h3 style={{ marginTop: 20 }}>الموردون المعتمدون</h3>
      {sups.loading ? <p className="muted">جارٍ…</p> : sups.rows.map(s => (
        <div className="card" key={s.id} style={{ marginBottom: 8, display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
          <div><strong>{s.name}</strong> <span className="muted" style={{ fontSize: 13 }}>· {s.products} منتج · {s.owner_email}</span></div>
          <select value={s.approval_status} onChange={e => setStatus(s.id, e.target.value)} style={{ maxWidth: 140 }}>
            <option value="approved">معتمد</option><option value="pending">معلّق</option><option value="blocked">محظور</option>
          </select>
        </div>
      ))}
    </div>
  )
}

function Products() {
  const { rows, loading, err, reload } = useLoader('admin_products')
  const [msg, setMsg] = useState<string | null>(null)
  const [edit, setEdit] = useState<Record<string, { price: string; stock: string }>>({})
  const [nf, setNf] = useState({ name: '', category: 'water', unit: '', price: '', stock: '' })
  const [showNew, setShowNew] = useState(false)
  const create = async () => {
    setMsg(null)
    const { error } = await supabase.rpc('admin_create_product', {
      p_name: nf.name, p_category: nf.category, p_unit: nf.unit,
      p_price_halalas: Number(nf.price), p_stock: Number(nf.stock || 0), p_description: '',
    })
    if (error) setMsg('تعذّر الإنشاء: ' + error.message)
    else { setMsg('تمت الإضافة'); setNf({ name: '', category: 'water', unit: '', price: '', stock: '' }); setShowNew(false); reload() }
  }
  const archive = async (p: any) => {
    const { error } = await supabase.rpc('admin_set_product_archived', { p_id: p.id, p_archived: !p.archived })
    if (error) setMsg('تعذّر: ' + error.message); else reload()
  }
  const save = async (p: any) => {
    setMsg(null)
    const e = edit[p.id] || { price: String(p.price_halalas), stock: String(p.stock) }
    const { error } = await supabase.rpc('admin_update_product', {
      p_id: p.id, p_price_halalas: Number(e.price), p_stock: Number(e.stock), p_active: p.active, p_featured: p.featured,
    })
    if (error) setMsg('تعذّر: ' + error.message); else { setMsg('تم الحفظ'); reload() }
  }
  const toggle = async (p: any, field: 'active' | 'featured') => {
    const { error } = await supabase.rpc('admin_update_product', {
      p_id: p.id, p_price_halalas: null, p_stock: null,
      p_active: field === 'active' ? !p.active : p.active,
      p_featured: field === 'featured' ? !p.featured : p.featured,
    })
    if (error) setMsg('تعذّر: ' + error.message); else reload()
  }
  if (loading) return <p className="muted">جارٍ التحميل…</p>
  if (err) return <div className="note">خطأ: {err}</div>
  const CATS: [string, string][] = [['water', 'مياه'], ['quran', 'مصاحف'], ['supplies', 'مستلزمات'], ['food', 'أغذية'], ['equipment', 'تجهيزات']]
  return (
    <div>
      {msg && <div className="note" style={{ marginBottom: 10 }}>{msg}</div>}
      <button className="btn" style={{ marginBottom: 12 }} onClick={() => setShowNew(s => !s)}>{showNew ? 'إلغاء' : '+ إضافة منتج'}</button>
      {showNew && (
        <div className="card" style={{ marginBottom: 14 }}>
          <div className="field"><label>اسم المنتج</label><input value={nf.name} onChange={e => setNf({ ...nf, name: e.target.value })} /></div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <label style={{ fontSize: 13 }}>الفئة<select value={nf.category} onChange={e => setNf({ ...nf, category: e.target.value })}>{CATS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
            <label style={{ fontSize: 13 }}>الوحدة<input value={nf.unit} onChange={e => setNf({ ...nf, unit: e.target.value })} placeholder="شدة/كرتون" style={{ width: 110 }} /></label>
            <label style={{ fontSize: 13 }}>السعر (هللة)<input value={nf.price} onChange={e => setNf({ ...nf, price: e.target.value.replace(/\D/g, '') })} style={{ width: 110 }} /></label>
            <label style={{ fontSize: 13 }}>المخزون<input value={nf.stock} onChange={e => setNf({ ...nf, stock: e.target.value.replace(/\D/g, '') })} style={{ width: 90 }} /></label>
          </div>
          <button className="btn" style={{ marginTop: 10 }} disabled={nf.name.length < 2 || !nf.price} onClick={create}>حفظ المنتج ←</button>
        </div>
      )}
      {rows.map(p => {
        const e = edit[p.id] || { price: String(p.price_halalas), stock: String(p.stock) }
        return (
          <div className="card" key={p.id} style={{ marginBottom: 10 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 6 }}>
              <strong>{p.name}</strong>
              <span className="muted" style={{ fontSize: 13 }}>{p.supplier_name || '—'} · {p.category}</span>
            </div>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'end', marginTop: 8 }}>
              <label style={{ fontSize: 13 }}>السعر (هللة)<input value={e.price} onChange={ev => setEdit({ ...edit, [p.id]: { ...e, price: ev.target.value.replace(/\D/g, '') } })} style={{ width: 110 }} /></label>
              <label style={{ fontSize: 13 }}>المخزون<input value={e.stock} onChange={ev => setEdit({ ...edit, [p.id]: { ...e, stock: ev.target.value.replace(/\D/g, '') } })} style={{ width: 90 }} /></label>
              <button className="btn" style={{ padding: '7px 14px' }} onClick={() => save(p)}>حفظ</button>
              <button className="btn ghost" style={{ padding: '7px 12px' }} onClick={() => toggle(p, 'active')}>{p.active ? 'إخفاء' : 'إظهار'}</button>
              <button className="btn ghost" style={{ padding: '7px 12px' }} onClick={() => toggle(p, 'featured')}>{p.featured ? '★ مميّز' : 'تمييز'}</button>
              <button className="btn ghost" style={{ padding: '7px 12px', color: p.archived ? 'var(--green)' : '#b23' }} onClick={() => archive(p)}>{p.archived ? 'استرجاع' : 'أرشفة'}</button>
            </div>
            <div className="muted" style={{ fontSize: 12, marginTop: 6 }}>السعر الحالي {sar(p.price_halalas)} {p.active ? '· ظاهر' : '· مخفي'}{p.archived ? ' · مؤرشف' : ''}</div>
          </div>
        )
      })}
    </div>
  )
}

function Inquiries() {
  const { rows, loading, err, reload } = useLoader('admin_inquiries')
  const [msg, setMsg] = useState<string | null>(null)
  const STATUS: Record<string, [string, string][]> = {
    quote: [['pending', 'جديد'], ['contacted', 'تم التواصل'], ['closed', 'مغلق']],
    subscription: [['requested', 'جديد'], ['contacted', 'تم التواصل'], ['closed', 'مغلق']],
    need: [['open', 'مفتوح'], ['fulfilled', 'مُلبّى']],
  }
  const KIND: Record<string, string> = { quote: 'طلب عرض', subscription: 'توريد دوري', need: 'احتياج منشأة' }
  const setStatus = async (kind: string, id: string, status: string) => {
    setMsg(null)
    const { error } = await supabase.rpc('admin_set_inquiry_status', { p_kind: kind, p_id: id, p_status: status })
    if (error) setMsg('تعذّر: ' + error.message); else reload()
  }
  if (loading) return <p className="muted">جارٍ التحميل…</p>
  if (err) return <div className="note">خطأ: {err}</div>
  if (rows.length === 0) return <p className="muted">لا استفسارات.</p>
  return (
    <div>
      {msg && <div className="note" style={{ marginBottom: 10 }}>{msg}</div>}
      {rows.map(q => (
        <div className="card" key={q.kind + q.id} style={{ marginBottom: 8 }}>
          <span className="badge">{KIND[q.kind]}</span> <strong style={{ marginInlineStart: 6 }}>{q.title || '—'}</strong>
          <div className="muted" style={{ fontSize: 13, margin: '6px 0' }}>{q.detail || ''} {q.city ? '· ' + q.city : ''} {q.phone ? '· ' + q.phone : ''}</div>
          <select value={q.status} onChange={e => setStatus(q.kind, q.id, e.target.value)} style={{ maxWidth: 160 }}>
            {(STATUS[q.kind] || []).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </div>
      ))}
    </div>
  )
}

function Customers() {
  const { rows, loading, err } = useLoader('admin_customers')
  if (loading) return <p className="muted">جارٍ التحميل…</p>
  if (err) return <div className="note">خطأ: {err}</div>
  if (rows.length === 0) return <p className="muted">لا عملاء بعد.</p>
  return (
    <div>
      {rows.map(c => (
        <div className="card" key={c.id} style={{ marginBottom: 8, display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
          <div><strong>{c.full_name || 'عميل'}</strong> <span className="muted" style={{ fontSize: 13 }}>· {c.phone || '—'} · {c.city || '—'} {c.email ? '· ' + c.email : ''}</span></div>
          <span className="badge">{c.orders} طلب</span>
        </div>
      ))}
    </div>
  )
}

function Deliveries() {
  const { rows, loading, err, reload } = useLoader('admin_deliveries')
  const [msg, setMsg] = useState<string | null>(null)
  const STATUS: [string, string][] = [['scheduled', 'مجدول'], ['submitted', 'بانتظار المراجعة'], ['approved', 'معتمد'], ['changes_requested', 'يحتاج تعديل']]
  const setStatus = async (id: string, status: string) => {
    setMsg(null)
    const { error } = await supabase.rpc('admin_set_delivery_status', { p_id: id, p_status: status })
    if (error) setMsg('تعذّر: ' + error.message); else reload()
  }
  if (loading) return <p className="muted">جارٍ التحميل…</p>
  if (err) return <div className="note">خطأ: {err}</div>
  return (
    <div>
      <div className="note" style={{ marginBottom: 10 }}>ربط شركة الشحن <strong>OTO</strong> سيُفعّل لاحقاً. حالياً يمكنك متابعة حالة التوصيل واعتماده يدوياً.</div>
      {msg && <div className="note" style={{ marginBottom: 10 }}>{msg}</div>}
      {rows.length === 0 && <p className="muted">لا عمليات توصيل بعد.</p>}
      {rows.map(d => (
        <div className="card" key={d.id} style={{ marginBottom: 8, display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
          <div><strong>{d.recipient_name || '—'}</strong> <span className="muted" style={{ fontSize: 13 }}>· {d.city || ''} · {new Date(d.created_at).toLocaleDateString('ar-SA')}</span></div>
          <select value={d.status} onChange={e => setStatus(d.id, e.target.value)} style={{ maxWidth: 170 }}>
            {STATUS.map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </div>
      ))}
    </div>
  )
}

function Staff() {
  const { rows, loading, err, reload } = useLoader('admin_staff')
  const [email, setEmail] = useState('')
  const [msg, setMsg] = useState<string | null>(null)
  const add = async () => {
    setMsg(null)
    const { error } = await supabase.rpc('admin_add_staff', { p_email: email.trim() })
    if (error) setMsg('تعذّر: ' + error.message); else { setMsg('تمت الإضافة كمشرف'); setEmail(''); reload() }
  }
  const remove = async (uid: string) => {
    const { error } = await supabase.rpc('admin_remove_staff', { p_user_id: uid })
    if (error) setMsg('تعذّر: ' + error.message); else reload()
  }
  return (
    <div>
      {msg && <div className="note" style={{ marginBottom: 10 }}>{msg}</div>}
      <div className="card" style={{ marginBottom: 14 }}>
        <div className="field"><label>إضافة مشرف (بالبريد — يجب أن يملك حساباً بكلمة مرور)</label>
          <div style={{ display: 'flex', gap: 8 }}>
            <input value={email} onChange={e => setEmail(e.target.value)} placeholder="admin@example.com" type="email" />
            <button className="btn" style={{ padding: '8px 16px' }} disabled={!email} onClick={add}>إضافة</button>
          </div>
        </div>
      </div>
      {loading ? <p className="muted">جارٍ…</p> : err ? <div className="note">خطأ: {err}</div> : rows.map(s => (
        <div className="card" key={s.user_id} style={{ marginBottom: 8, display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 8 }}>
          <div><strong>{s.email}</strong> <span className="badge" style={{ marginInlineStart: 6 }}>{s.role}</span> <span className="muted" style={{ fontSize: 12 }}>· {s.status}{s.is_operator ? ' · مشغّل' : ''}</span></div>
          <button className="btn ghost" style={{ padding: '6px 12px', color: '#b23' }} onClick={() => remove(s.user_id)}>إزالة</button>
        </div>
      ))}
    </div>
  )
}

function Audit() {
  const { rows, loading, err } = useLoader('admin_audit', { p_limit: 100 })
  if (loading) return <p className="muted">جارٍ التحميل…</p>
  if (err) return <div className="note">خطأ: {err}</div>
  if (rows.length === 0) return <p className="muted">لا سجلات بعد.</p>
  return (
    <div className="card">
      {rows.map((a, i) => (
        <div key={i} style={{ padding: '8px 0', borderBottom: '1px solid var(--line)', fontSize: 14 }}>
          <strong>{a.action}</strong> <span className="muted">· {a.entity_type} · {a.actor_email || '—'} · {a.created_at ? new Date(a.created_at).toLocaleString('ar-SA') : ''}</span>
        </div>
      ))}
    </div>
  )
}

function Settings() {
  const [s, setS] = useState<any>(null)
  const [msg, setMsg] = useState<string | null>(null)
  const [delivery, setDelivery] = useState('')
  const load = async () => { const { data } = await supabase.rpc('admin_settings'); setS(data); setDelivery(data?.delivery_halalas != null ? String(data.delivery_halalas) : '') }
  useEffect(() => { load() }, [])
  const save = async (loyalty: boolean | null, deliveryH: number | null) => {
    setMsg(null)
    const { error } = await supabase.rpc('admin_update_settings', { p_loyalty_enabled: loyalty, p_delivery_halalas: deliveryH })
    if (error) setMsg('تعذّر: ' + error.message); else { setMsg('تم الحفظ'); load() }
  }
  if (!s) return <p className="muted">جارٍ التحميل…</p>
  return (
    <div className="card" style={{ maxWidth: 520 }}>
      {msg && <div className="note" style={{ marginBottom: 10 }}>{msg}</div>}
      <label style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 14 }}>
        <input type="checkbox" checked={!!s.loyalty_enabled} onChange={e => save(e.target.checked, null)} /> تفعيل برنامج الولاء
      </label>
      <div className="field"><label>رسوم التوصيل (هللة)</label>
        <div style={{ display: 'flex', gap: 8 }}>
          <input value={delivery} onChange={e => setDelivery(e.target.value.replace(/\D/g, ''))} placeholder="0 = مجاني" />
          <button className="btn" style={{ padding: '7px 16px' }} onClick={() => save(null, Number(delivery || 0))}>حفظ</button>
        </div>
      </div>
      <div style={{ marginTop: 14, borderTop: '1px solid var(--line)', paddingTop: 12 }}>
        <strong>الخدمات الإضافية</strong>
        {(s.services || []).map((x: any) => <ServiceRow key={x.code} svc={x} onSaved={load} onMsg={setMsg} />)}
        {(!s.services || s.services.length === 0) && <p className="muted" style={{ fontSize: 13 }}>لا خدمات.</p>}
      </div>
    </div>
  )
}

const SERVICE_LABEL: Record<string, string> = { name_printing: 'طباعة الاسم على المصحف', delivery: 'التوصيل' }
function ServiceRow({ svc, onSaved, onMsg }: { svc: any; onSaved: () => void; onMsg: (m: string) => void }) {
  const [price, setPrice] = useState(String(svc.price_halalas ?? 0))
  const save = async (active: boolean | null) => {
    const { error } = await supabase.rpc('admin_set_service', { p_code: svc.code, p_price_halalas: Number(price || 0), p_active: active })
    if (error) onMsg('تعذّر: ' + error.message); else { onMsg('تم الحفظ'); onSaved() }
  }
  return (
    <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', margin: '8px 0' }}>
      <span style={{ minWidth: 150, fontSize: 14 }}>{SERVICE_LABEL[svc.code] || svc.code}</span>
      <input value={price} onChange={e => setPrice(e.target.value.replace(/\D/g, ''))} style={{ width: 100 }} />
      <button className="btn" style={{ padding: '6px 12px' }} onClick={() => save(null)}>حفظ السعر</button>
      <button className="btn ghost" style={{ padding: '6px 12px' }} onClick={() => save(!svc.active)}>{svc.active ? 'إيقاف' : 'تفعيل'}</button>
      <span className="badge">{svc.active ? 'مفعّل' : 'موقوف'}</span>
    </div>
  )
}
