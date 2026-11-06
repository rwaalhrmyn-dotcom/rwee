import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { useNavigate } from 'react-router-dom'

export default function CustomerLogin() {
  const [phone, setPhone] = useState('')
  const [code, setCode] = useState('')
  const [sent, setSent] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const nav = useNavigate()
  const norm = (p: string) => p.replace(/^0/, '+966').replace(/\s/g, '')

  const send = async () => {
    setBusy(true); setMsg(null)
    const { error } = await supabase.auth.signInWithOtp({ phone: norm(phone) })
    setBusy(false)
    if (error) setMsg('تعذّر إرسال الرمز: ' + error.message); else setSent(true)
  }
  const verify = async () => {
    setBusy(true); setMsg(null)
    const { error } = await supabase.auth.verifyOtp({ phone: norm(phone), token: code, type: 'sms' })
    setBusy(false)
    if (error) setMsg('رمز غير صحيح: ' + error.message); else nav('/customer')
  }
  return (
    <section style={{ padding: '32px 0', maxWidth: 440 }}>
      <h2 style={{ color: 'var(--green)' }}>دخول العميل</h2>
      <p className="muted">سنرسل رمز تحقق إلى جوالك لمتابعة طلباتك.</p>
      <div className="card">
        <div className="field"><label>رقم الجوال</label>
          <input value={phone} onChange={e => setPhone(e.target.value)} placeholder="05xxxxxxxx" disabled={sent} /></div>
        {sent && <div className="field"><label>رمز التحقق</label>
          <input value={code} onChange={e => setCode(e.target.value)} placeholder="______" /></div>}
        {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
        {!sent
          ? <button className="btn" style={{ width: '100%' }} disabled={busy || phone.length < 9} onClick={send}>إرسال رسالة التحقق ←</button>
          : <button className="btn" style={{ width: '100%' }} disabled={busy || code.length < 4} onClick={verify}>تأكيد الدخول ←</button>}
      </div>
    </section>
  )
}
