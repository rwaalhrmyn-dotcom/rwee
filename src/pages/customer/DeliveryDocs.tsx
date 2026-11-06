import { useEffect, useState } from 'react'
import { supabase } from '../../lib/supabase'
import { Link } from 'react-router-dom'

export default function DeliveryDocs() {
  const [authed, setAuthed] = useState<boolean | null>(null)
  const [rows, setRows] = useState<any[]>([]); const [err, setErr] = useState<string | null>(null); const [msg, setMsg] = useState<string | null>(null)
  const load = async () => {
    const { data, error } = await supabase.from('deliveries').select('id,order_id,status,recipient_confirmed_at,reviewed_at,created_at').order('created_at', { ascending: false })
    if (error) setErr(error.message); else setRows(data || [])
  }
  useEffect(() => { (async () => { const { data: { session } } = await supabase.auth.getSession(); setAuthed(!!session); if (session) await load() })() }, [])

  const upload = async (d: any, file: File) => {
    setMsg(null)
    const ext = file.name.endsWith('.webm') ? 'webm' : 'mp4'
    const path = `${d.order_id}/evidence-${Date.now()}.${ext}`
    const up = await supabase.storage.from('delivery-evidence').upload(path, file)
    if (up.error) { setMsg('تعذّر رفع الفيديو: ' + up.error.message); return }
    const { error } = await supabase.rpc('submit_delivery_evidence', { p_delivery_id: d.id, p_object_path: path })
    if (error) setMsg('تعذّر تسجيل الدليل: ' + error.message); else { setMsg('تم رفع دليل التسليم'); await load() }
  }
  const confirm = async (d: any) => { setMsg(null); const { error } = await supabase.rpc('confirm_delivery_receipt', { p_delivery_id: d.id }); error ? setMsg(error.message) : (setMsg('تم تأكيد الاستلام'), await load()) }
  const review = async (d: any, decision: string) => { setMsg(null); const { error } = await supabase.rpc('review_delivery', { p_delivery_id: d.id, p_decision: decision }); error ? setMsg(error.message) : (setMsg('تم تحديث المراجعة'), await load()) }

  const LABEL: Record<string, string> = { scheduled: 'مجدول', submitted: 'بانتظار المراجعة', approved: 'مُعتمد', changes_requested: 'يحتاج تعديل' }
  if (authed === false) return <section style={{ padding: '32px 0' }}><p className="muted">يلزم تسجيل الدخول. <Link to="/customer/login" style={{ color: 'var(--green)' }}>دخول ←</Link></p></section>
  return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>توثيق التسليم</h2>
      {err && <div className="note">{err}</div>}{msg && <div className="note">{msg}</div>}
      {rows.length === 0 && !err && <p className="muted">لا عمليات تسليم مرتبطة بحسابك.</p>}
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(300px,1fr))' }}>
        {rows.map(d => (
          <div className="card" key={d.id}>
            <span className="badge">{LABEL[d.status] || d.status}</span>
            <div className="muted" style={{ fontSize: 13, margin: '8px 0' }}>طلب {String(d.order_id).slice(0, 8)}…</div>
            {(d.status === 'scheduled' || d.status === 'changes_requested') && (
              <label className="btn ghost" style={{ display: 'block', textAlign: 'center', cursor: 'pointer' }}>
                رفع فيديو التسليم
                <input type="file" accept="video/mp4,video/webm" style={{ display: 'none' }} onChange={e => e.target.files?.[0] && upload(d, e.target.files[0])} />
              </label>
            )}
            {!d.recipient_confirmed_at && <button className="btn" style={{ width: '100%', marginTop: 8 }} onClick={() => confirm(d)}>تأكيد الاستلام</button>}
            {d.status === 'submitted' && (
              <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
                <button className="btn" style={{ flex: 1 }} onClick={() => review(d, 'approved')}>اعتماد</button>
                <button className="btn ghost" style={{ flex: 1 }} onClick={() => review(d, 'changes_requested')}>طلب تعديل</button>
              </div>
            )}
          </div>
        ))}
      </div>
    </section>
  )
}
