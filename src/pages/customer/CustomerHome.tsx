import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'
import { sar } from '../../lib/format'

export default function CustomerHome() {
  const [email, setEmail] = useState<string | null>(null)
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [orders, setOrders] = useState<any[]>([])
  useEffect(() => {
    (async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setAuthed(!!session)
      if (session) {
        setEmail(session.user.phone || session.user.email || null)
        const { data } = await supabase.from('orders').select('id,status,subtotal_halalas,delivery_halalas,created_at').order('created_at', { ascending: false }).limit(10)
        setOrders(data || [])
      }
    })()
  }, [])
  if (authed === false) return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>حسابي</h2>
      <p className="muted">يلزم تسجيل الدخول لعرض طلباتك.</p>
      <Link className="btn" to="/customer/login">تسجيل الدخول ←</Link>
    </section>
  )
  return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>مرحباً{email ? ` · ${email}` : ''}</h2>
      <h3>طلباتك الأخيرة</h3>
      {orders.length === 0 ? <p className="muted">لا توجد طلبات بعد.</p> : (
        <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(240px,1fr))' }}>
          {orders.map(o => (
            <Link className="card" to={`/customer/orders/${o.id}`} key={o.id} style={{display:"block"}}>
              <span className="badge">{o.status}</span>
              <div className="price" style={{ marginTop: 8 }}>{sar((o.subtotal_halalas||0)+(o.delivery_halalas||0))}</div>
              <div className="muted" style={{ fontSize: 13 }}>{new Date(o.created_at).toLocaleDateString('ar-SA')}</div>
            </Link>
          ))}
        </div>
      )}
      <button className="btn ghost" style={{ marginTop: 20 }} onClick={() => supabase.auth.signOut().then(() => location.reload())}>تسجيل الخروج</button>
    </section>
  )
}
