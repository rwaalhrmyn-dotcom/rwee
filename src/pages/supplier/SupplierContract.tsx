import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'

export default function SupplierContract() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [supplierId, setSupplierId] = useState<string | null>(null)
  const [contract, setContract] = useState<any>(null)
  const [signer, setSigner] = useState(''); const [agree, setAgree] = useState(false)
  const [msg, setMsg] = useState<string | null>(null); const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false)

  const load = async (sid: string) => {
    const { data, error } = await supabase.rpc('my_supplier_contract', { p_supplier: sid })
    if (error) setMsg(error.message); else setContract(data)
  }
  useEffect(() => { (async () => {
    const { data: { session } } = await supabase.auth.getSession(); setAuthed(!!session)
    if (session) {
      const { data } = await supabase.rpc('my_supplier_accounts')
      const first = Array.isArray(data) && data[0] ? (data[0].id || data[0].supplier_id) : null
      if (first) { setSupplierId(first); await load(first) }
    }
  })() }, [])

  const accept = async () => {
    if (!supplierId || !contract) return
    setBusy(true); setMsg(null)
    const { error } = await supabase.rpc('accept_supplier_contract', {
      p_supplier: supplierId,
      p_version: contract.version_id || contract.version,
      p_hash: contract.body_sha256 || contract.hash,
      p_signer_name: signer,
      p_request: crypto.randomUUID(),
      p_agreed: true,
    })
    setBusy(false)
    if (error) setMsg('تعذّر قبول العقد: ' + error.message); else setOk(true)
  }

  if (authed === false) return <section style={{ padding: '32px 0' }}><p className="muted">سجّل الدخول كمورد. <Link to="/supplier/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p></section>
  if (ok) return <section style={{ padding: '32px 0' }}><div className="note">تم توقيع العقد الإلكتروني بنجاح. شكراً لك.</div></section>
  if (!supplierId) return <section style={{ padding: '32px 0' }}><p className="muted">لا منشأة معتمدة مرتبطة بحسابك بعد.</p></section>
  if (!contract) return <section style={{ padding: '32px 0' }}><p className="muted">{msg || 'جارٍ تحميل العقد…'}</p></section>
  const accepted = contract.accepted || contract.is_accepted
  return (
    <section style={{ padding: '32px 0', maxWidth: 680 }}>
      <h2 style={{ color: 'var(--green)' }}>عقد المورد الإلكتروني</h2>
      {accepted && <div className="note">هذا العقد موقّع مسبقاً من حسابك.</div>}
      <div className="card" style={{ maxHeight: 360, overflow: 'auto', whiteSpace: 'pre-wrap', fontSize: 14 }}>
        {contract.body_ar || contract.body || 'نص العقد غير متوفر.'}
      </div>
      {!accepted && (
        <div className="card" style={{ marginTop: 16 }}>
          <div className="field"><label>اسم الموقّع</label><input value={signer} onChange={e => setSigner(e.target.value)} /></div>
          <label style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <input type="checkbox" checked={agree} onChange={e => setAgree(e.target.checked)} /> أقرّ بموافقتي على بنود العقد.
          </label>
          {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
          <button className="btn" style={{ width: '100%', marginTop: 10 }} disabled={busy || !agree || signer.trim().length < 3} onClick={accept}>توقيع وقبول العقد ←</button>
        </div>
      )}
    </section>
  )
}
