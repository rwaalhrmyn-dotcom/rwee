import { useState } from 'react'
import { supabase } from '../../lib/supabase'
import { useNavigate } from 'react-router-dom'
import { CITIES } from '../../lib/format'

type Mode = 'phone' | 'email'
export default function CustomerLogin() {
  const [mode, setMode] = useState<Mode>('phone')
  const [id, setId] = useState('')        // phone or email
  const [code, setCode] = useState('')
  const [step, setStep] = useState<'send' | 'verify' | 'profile'>('send')
  const [msg, setMsg] = useState<string | null>(null); const [busy, setBusy] = useState(false)
  // profile fields
  const [fullName, setFullName] = useState(''); const [phone, setPhone] = useState(''); const [city, setCity] = useState('makkah')
  const nav = useNavigate()
  const normPhone = (p: string) => p.replace(/^0/, '+966').replace(/\s/g, '')

  const send = async () => {
    setBusy(true); setMsg(null)
    const res = mode === 'phone'
      ? await supabase.auth.signInWithOtp({ phone: normPhone(id) })
      : await supabase.auth.signInWithOtp({ email: id })
    setBusy(false)
    if (res.error) setMsg('تعذّر إرسال الرمز: ' + res.error.message); else setStep('verify')
  }
  const verify = async () => {
    setBusy(true); setMsg(null)
    const res = mode === 'phone'
      ? await supabase.auth.verifyOtp({ phone: normPhone(id), token: code, type: 'sms' })
      : await supabase.auth.verifyOtp({ email: id, token: code, type: 'email' })
    setBusy(false)
    if (res.error) { setMsg('رمز غير صحيح: ' + res.error.message); return }
    // after verification, check/save profile
    const { data: prof } = await supabase.from('profiles').select('id,full_name').maybeSingle()
    if (prof?.full_name) { nav('/customer'); return }
    if (mode === 'phone') setPhone(id)
    setStep('profile')
  }
  const saveProfile = async () => {
    setBusy(true); setMsg(null)
    const { data: { user } } = await supabase.auth.getUser()
    if (!user) { setBusy(false); setMsg('انتهت الجلسة، أعد الدخول.'); return }
    const { error } = await supabase.from('profiles').upsert({
      id: user.id, full_name: fullName, phone: normPhone(phone).replace('+966', '0'), city,
    })
    setBusy(false)
    if (error) setMsg('تعذّر حفظ البيانات: ' + error.message); else nav('/customer')
  }

  return (
    <section style={{ padding: '32px 0', maxWidth: 460 }}>
      <h2 style={{ color: 'var(--green)' }}>دخول العميل</h2>
      {step === 'send' && (
        <div className="card">
          <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
            <button className="badge" style={{ border: 0, cursor: 'pointer', flex: 1, padding: 10, background: mode === 'phone' ? 'var(--green)' : undefined, color: mode === 'phone' ? '#fff' : undefined }} onClick={() => setMode('phone')}>رقم الجوال</button>
            <button className="badge" style={{ border: 0, cursor: 'pointer', flex: 1, padding: 10, background: mode === 'email' ? 'var(--green)' : undefined, color: mode === 'email' ? '#fff' : undefined }} onClick={() => setMode('email')}>البريد الإلكتروني</button>
          </div>
          <div className="field"><label>{mode === 'phone' ? 'رقم الجوال' : 'البريد الإلكتروني'}</label>
            <input value={id} onChange={e => setId(e.target.value)} placeholder={mode === 'phone' ? '05xxxxxxxx' : 'name@example.com'} type={mode === 'email' ? 'email' : 'text'} /></div>
          {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
          <button className="btn" style={{ width: '100%' }} disabled={busy || id.length < 5} onClick={send}>إرسال رمز التحقق ←</button>
        </div>
      )}
      {step === 'verify' && (
        <div className="card">
          <p className="muted">أدخل الرمز المُرسل إلى {mode === 'phone' ? 'جوالك' : 'بريدك'}.</p>
          <div className="field"><label>رمز التحقق</label><input value={code} onChange={e => setCode(e.target.value)} placeholder="______" /></div>
          {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
          <button className="btn" style={{ width: '100%' }} disabled={busy || code.length < 4} onClick={verify}>تأكيد ←</button>
        </div>
      )}
      {step === 'profile' && (
        <div className="card">
          <p className="muted">أكمل بياناتك لحفظ حسابك (تُحفظ لمتابعة طلباتك دائماً).</p>
          <div className="field"><label>الاسم الكامل</label><input value={fullName} onChange={e => setFullName(e.target.value)} /></div>
          <div className="field"><label>رقم الجوال</label><input value={phone} onChange={e => setPhone(e.target.value)} placeholder="05xxxxxxxx" /></div>
          <div className="field"><label>المدينة</label>
            <select value={city} onChange={e => setCity(e.target.value)}>
              <option value="makkah">مكة المكرمة</option><option value="madinah">المدينة المنورة</option>
            </select></div>
          {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
          <button className="btn" style={{ width: '100%' }} disabled={busy || fullName.length < 2 || phone.length < 9} onClick={saveProfile}>حفظ ومتابعة ←</button>
        </div>
      )}
    </section>
  )
}
