import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'

export default function Loyalty() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [wallet, setWallet] = useState<any>(null); const [err, setErr] = useState<string | null>(null)
  useEffect(() => { (async () => {
    const { data: { session } } = await supabase.auth.getSession(); setAuthed(!!session)
    if (session) { const { data, error } = await supabase.rpc('my_loyalty_wallet'); error ? setErr(error.message) : setWallet(data) }
  })() }, [])
  if (authed === false) return <section style={{ padding: '32px 0' }}><p className="muted">سجّل الدخول لعرض محفظتك. <Link to="/customer/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p></section>
  return (
    <section style={{ padding: '32px 0', maxWidth: 520 }}>
      <h2 style={{ color: 'var(--green)' }}>محفظة الولاء</h2>
      {err && <div className="note">{err}</div>}
      {wallet && (
        <>
          <div className="card" style={{ display: 'flex', justifyContent: 'space-around', textAlign: 'center' }}>
            <div><div className="price" style={{ fontSize: 28 }}>{wallet.balance ?? 0}</div><div className="muted">الرصيد الحالي</div></div>
            <div><div className="price" style={{ fontSize: 28 }}>{wallet.lifetime ?? 0}</div><div className="muted">إجمالي ما كسبته</div></div>
          </div>
          <h3>آخر الحركات</h3>
          <div className="card">
            {(wallet.transactions || []).length === 0 ? <p className="muted">لا حركات بعد.</p> :
              (wallet.transactions || []).slice(0, 15).map((t: any, i: number) => (
                <div key={i} style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid var(--border)', fontSize: 14 }}>
                  <span>{t.reason || t.type || 'حركة'}</span><span className="price">{t.points > 0 ? '+' : ''}{t.points ?? t.amount}</span>
                </div>
              ))}
          </div>
        </>
      )}
    </section>
  )
}
