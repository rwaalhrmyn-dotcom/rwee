import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'

export default function AdminHome() {
  const [session, setSession] = useState<any>(null)
  const [adminErr, setAdminErr] = useState<string | null>(null)
  const [me, setMe] = useState<any>(null)
  useEffect(() => {
    (async () => {
      const { data: { session } } = await supabase.auth.getSession()
      setSession(session)
      if (session) {
        const { data, error } = await supabase.rpc('my_admin_session')
        if (error) setAdminErr(error.message); else setMe(data)
      }
    })()
  }, [])
  if (!session) return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>لوحة التحكم</h2>
      <p className="muted">يلزم تسجيل دخول إداري موثّق.</p>
      <Link className="btn" to="/admin/login">تسجيل الدخول ←</Link>
    </section>
  )
  return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>لوحة التحكم</h2>
      {adminErr && <div className="note">هذا الحساب ليس له صلاحية إدارية: {adminErr}</div>}
      {me && <div className="card" style={{ maxWidth: 480 }}>
        <strong>جلسة إدارية موثّقة</strong>
        <pre style={{ whiteSpace: 'pre-wrap', fontSize: 13, color: 'var(--muted)' }}>{JSON.stringify(me, null, 2)}</pre>
      </div>}
      <button className="btn ghost" style={{ marginTop: 20 }} onClick={() => supabase.auth.signOut().then(() => location.reload())}>تسجيل الخروج</button>
    </section>
  )
}
