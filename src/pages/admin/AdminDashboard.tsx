import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'

export default function AdminDashboard() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [audit, setAudit] = useState<any[]>([]); const [staff, setStaff] = useState<any[]>([])
  const [err, setErr] = useState<string | null>(null)
  useEffect(() => { (async () => {
    const { data: { session } } = await supabase.auth.getSession(); setAuthed(!!session)
    if (session) {
      const a = await supabase.rpc('admin_audit_page'); if (a.error) setErr(a.error.message); else setAudit(Array.isArray(a.data) ? a.data : [])
      const s = await supabase.rpc('admin_staff_profiles'); if (!s.error) setStaff(Array.isArray(s.data) ? s.data : [])
    }
  })() }, [])
  if (authed === false) return <section style={{ padding: '32px 0' }}><p className="muted">يلزم دخول إداري. <Link to="/admin/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p></section>
  return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>لوحة التحكم الإدارية</h2>
      {err && <div className="note">صلاحية محدودة أو خطأ: {err}</div>}
      <h3>طاقم الإدارة ({staff.length})</h3>
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(220px,1fr))', marginBottom: 24 }}>
        {staff.map((s: any, i: number) => <div className="card" key={i}><strong>{s.role || 'عضو'}</strong><div className="badge" style={{ marginTop: 6 }}>{s.status}</div></div>)}
      </div>
      <h3>سجل التدقيق الأخير</h3>
      {audit.length === 0 && !err && <p className="muted">لا سجلات.</p>}
      <div className="card">
        {audit.slice(0, 20).map((a: any, i: number) => (
          <div key={i} style={{ padding: '8px 0', borderBottom: '1px solid var(--border)', fontSize: 14 }}>
            <strong>{a.action}</strong> <span className="muted">· {a.entity_type} · {a.created_at ? new Date(a.created_at).toLocaleString('ar-SA') : ''}</span>
          </div>
        ))}
      </div>
    </section>
  )
}
