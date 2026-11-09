import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'

export default function SupplierContract() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [supplierId, setSupplierId] = useState<string | null>(null)
  const [contract, setContract] = useState<any>(null)
  const [signer, setSigner] = useState(''); const [agree, setAgree] = useState(false)
  const [msg, setMsg] = useState<string | null>(null); const [ok, setOk] = useState(false); const [busy, setBusy] = useState(false)

  useEffect(() => { (async () => {
    // Always load the current published contract so anyone can read it.
    const { data: pub } = await supabase.rpc('current_supplier_contract')
    const current = Array.isArray(pub) && pub[0] ? pub[0] : (pub && pub.version_id ? pub : null)

    const { data: { session } } = await supabase.auth.getSession(); setAuthed(!!session)
    if (session) {
      const { data } = await supabase.rpc('my_supplier_accounts')
      const first = Array.isArray(data) && data[0] ? (data[0].id || data[0].supplier_id) : null
      if (first) {
        setSupplierId(first)
        // Signable contract tied to the approved supplier (tracks acceptance state).
        const { data: mine, error } = await supabase.rpc('my_supplier_contract', { p_supplier: first })
        if (!error && mine) { setContract(mine); return }
      }
    }
    // Fallback: read-only current contract for prospective / pending suppliers.
    if (current) setContract({ ...current, readonly: true })
    else setMsg('نص العقد غير متوفر حالياً.')
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

  const PolicyLinks = () => (
    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', margin: '12px 0' }}>
      <Link className="btn ghost" to="/terms" style={{ padding: '6px 14px', fontSize: 13 }}>الشروط والأحكام</Link>
      <Link className="btn ghost" to="/privacy" style={{ padding: '6px 14px', fontSize: 13 }}>سياسة الخصوصية</Link>
    </div>
  )

  if (ok) return (
    <section style={{ padding: '32px 0' }}>
      <div className="note">تم توقيع العقد الإلكتروني بنجاح. شكراً لك.</div>
      <PolicyLinks />
    </section>
  )

  if (!contract) return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>عقد المورد والشروط</h2>
      <PolicyLinks />
      <p className="muted">{msg || 'جارٍ تحميل العقد…'}</p>
    </section>
  )

  const accepted = contract.accepted || contract.is_accepted
  const readonly = contract.readonly
  const canSign = authed && !!supplierId && !accepted && !readonly

  return (
    <section style={{ padding: '32px 0', maxWidth: 680 }}>
      <h2 style={{ color: 'var(--green)' }}>عقد المورد والشروط</h2>
      <p className="muted" style={{ fontSize: 14 }}>اطّلع على عقد المورد وشروط الاستخدام وسياسة الخصوصية قبل الانضمام وأثناء العمل على المنصة.</p>
      <PolicyLinks />

      {accepted && <div className="note">هذا العقد موقّع مسبقاً من حسابك.</div>}
      {readonly && (
        <div className="note" style={{ margin: '10px 0' }}>
          هذه نسخة للاطّلاع. يتم التوقيع الإلكتروني للعقد من حساب المورد بعد تسجيل الدخول واعتماد منشأتك.
        </div>
      )}

      <div className="card" style={{ maxHeight: 420, overflow: 'auto', whiteSpace: 'pre-wrap', fontSize: 14 }}>
        {contract.body_ar || contract.body || 'نص العقد غير متوفر.'}
      </div>
      {(contract.version_id || contract.version) && (
        <p className="muted" style={{ fontSize: 12, marginTop: 6 }}>إصدار العقد: {contract.version_id || contract.version}</p>
      )}

      {canSign && (
        <div className="card" style={{ marginTop: 16 }}>
          <div className="field"><label>اسم الموقّع</label><input value={signer} onChange={e => setSigner(e.target.value)} /></div>
          <label style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
            <input type="checkbox" checked={agree} onChange={e => setAgree(e.target.checked)} /> أقرّ بموافقتي على بنود العقد وشروط الاستخدام وسياسة الخصوصية.
          </label>
          {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
          <button className="btn" style={{ width: '100%', marginTop: 10 }} disabled={busy || !agree || signer.trim().length < 3} onClick={accept}>توقيع وقبول العقد ←</button>
        </div>
      )}

      {authed === false && (
        <div className="note" style={{ margin: '14px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10, flexWrap: 'wrap' }}>
          <span>للتوقيع الإلكتروني سجّل الدخول كمورد.</span>
          <Link className="btn" to="/supplier/login" style={{ padding: '7px 16px' }}>دخول المورد ←</Link>
        </div>
      )}
    </section>
  )
}
