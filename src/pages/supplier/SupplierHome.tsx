import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'

export default function SupplierHome() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [accounts, setAccounts] = useState<any[]>([])
  const [err, setErr] = useState<string | null>(null)
  useEffect(() => {
    (async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setAuthed(!!session)
      if (session) {
        const { data, error } = await supabase.rpc('my_supplier_accounts')
        if (error) setErr(error.message); else setAccounts(Array.isArray(data) ? data : [])
      }
    })()
  }, [])
  if (authed === false) return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>بوابة المورد</h2>
      <p className="muted">سجّل الدخول لإدارة منتجاتك ومخزونك وطلباتك.</p>
      <Link className="btn" to="/supplier/login">دخول المورد ←</Link>
    </section>
  )
  return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>لوحة المورد</h2>
      {err && <div className="note">تعذّر جلب حساباتك: {err}</div>}
      {accounts.length === 0 && !err && <p className="muted">لا توجد منشأة مرتبطة بعد — بانتظار اعتماد طلب الانضمام.</p>}
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(240px,1fr))' }}>
        {accounts.map((a: any, i: number) => (
          <div className="card" key={i}><strong>{a.name || a.supplier_name || 'منشأة'}</strong>
            <div className="badge" style={{ marginTop: 8 }}>{a.approval_status || a.status || ''}</div></div>
        ))}
      </div>
      <div style={{display:"flex",gap:8,margin:"16px 0"}}><Link className="btn" to="/supplier/inventory">المخزون</Link><Link className="btn ghost" to="/supplier/orders">الطلبات</Link><Link className="btn ghost" to="/supplier/contract">العقد</Link><Link className="btn ghost" to="/supplier/register">انضمام</Link></div>
      <button className="btn ghost" style={{ marginTop: 8 }} onClick={() => supabase.auth.signOut().then(() => location.reload())}>تسجيل الخروج</button>
    </section>
  )
}
