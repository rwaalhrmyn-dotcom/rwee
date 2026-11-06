import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { useNavigate } from 'react-router-dom'
import GoogleButton from '../../components/GoogleButton'

export default function AdminLogin() {
  const [email, setEmail] = useState(''); const [password, setPassword] = useState('')
  const [msg, setMsg] = useState<string | null>(null); const [busy, setBusy] = useState(false)
  const nav = useNavigate()
  const submit = async () => {
    setBusy(true); setMsg(null)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setBusy(false)
    if (error) setMsg('تعذّر الدخول: ' + error.message); else nav('/admin')
  }
  return (
    <section style={{ padding: '32px 0', maxWidth: 480 }}>
      <h2 style={{ color: 'var(--green)' }}>أمان حساب الإدارة</h2>
      <p className="muted">اسم المستخدم هو بريد الحساب الموثّق. يتحقق الخادم من كلمة المرور والصلاحية الإدارية.</p>
      <div className="card">
        <div className="field"><label>اسم المستخدم (البريد الإلكتروني)</label><input value={email} onChange={e => setEmail(e.target.value)} type="email" /></div>
        <div className="field"><label>كلمة المرور</label><input value={password} onChange={e => setPassword(e.target.value)} type="password" /></div>
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || !email || !password} onClick={submit}>متابعة التحقق</button>
        <div className="orsep">أو</div>
        <GoogleButton redirect="/admin" label="دخول الإدارة عبر Google" />
        <p className="muted" style={{ fontSize: 13, marginTop: 10 }}>استعادة كلمة المرور غير متاحة حتى اعتماد قناة البريد والتحقق منها.</p>
      </div>
    </section>
  )
}
