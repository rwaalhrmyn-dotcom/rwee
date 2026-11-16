import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { Badge, INVOICE_STATUS, pct, riyal, toHalalas } from '../../lib/finance'

const TABS = [['summary', 'الملخص'], ['invoices', 'الفواتير'], ['payments', 'المدفوعات والإشعارات الدائنة'], ['lines', 'تفاصيل العمولات'], ['notices', 'الإشعارات'], ['contract', 'العقد الموقّع']] as const

export default function SupplierFinance() {
  const [sup, setSup] = useState<{ id: string; name: string } | null>(null)
  const [tab, setTab] = useState<string>('summary')
  const [sum, setSum] = useState<any>(null)
  const [invoices, setInvoices] = useState<any[]>([])
  const [pc, setPc] = useState<any>({ payments: [], credit_notes: [] })
  const [lines, setLines] = useState<any[]>([])
  const [notices, setNotices] = useState<any[]>([])
  const [contracts, setContracts] = useState<any[]>([])
  const [msg, setMsg] = useState<string | null>(null)

  const load = async (id: string) => {
    const [a, b, c, d, e, f] = await Promise.all([
      supabase.rpc('supplier_finance_summary', { p_supplier: id }), supabase.rpc('supplier_invoices', { p_supplier: id }),
      supabase.rpc('supplier_payments_and_credits', { p_supplier: id }), supabase.rpc('supplier_commission_lines', { p_supplier: id, p_month: null }),
      supabase.from('supplier_notifications').select('*').eq('supplier_id', id).order('created_at', { ascending: false }).limit(100),
      supabase.rpc('my_signed_contracts', { p_supplier: id }),
    ])
    const err = [a, b, c, d, e, f].find(r => r.error)?.error
    if (err) setMsg(err.message)
    setSum(a.data); setInvoices(b.data ?? []); setPc(c.data ?? { payments: [], credit_notes: [] }); setLines(d.data ?? []); setNotices(e.data ?? []); setContracts(f.data ?? [])
  }
  useEffect(() => { (async () => {
    const { data } = await supabase.rpc('my_supplier_dashboard')
    const s = Array.isArray(data) ? data.find((x: any) => x.approval_status === 'approved') : null
    if (s) { setSup({ id: s.id, name: s.name }); await load(s.id) } else setMsg('لا توجد منشأة معتمدة مرتبطة بحسابك.')
  })() }, [])

  const markRead = async () => { if (!sup) return; await supabase.rpc('supplier_mark_notifications_read', { p_supplier: sup.id }); await load(sup.id) }
  const m = sum?.month ?? {}
  const stat = (label: string, v: string, warn = false) => (
    <div style={{ flex: '1 1 150px', padding: 12, border: '1px solid var(--line)', borderRadius: 12, textAlign: 'center' }}>
      <div style={{ fontSize: 19, fontWeight: 700, color: warn ? '#b00020' : 'var(--green)' }}>{v}</div><div className="muted" style={{ fontSize: 12 }}>{label}</div>
    </div>)

  return (
    <section style={{ padding: '32px 0', maxWidth: 900 }}>
      <Link to="/supplier" className="muted">→ لوحة المورد</Link>
      <h2 style={{ color: 'var(--green)' }}>المالية والعمولات {sup ? `— ${sup.name}` : ''}</h2>
      {msg && <div className="note">{msg}</div>}
      {sum?.overdue_halalas > 0 && <div className="note" style={{ borderColor: '#b00020', margin: '10px 0' }}>⚠️ لديك مستحقات متأخرة بقيمة {riyal(sum.overdue_halalas)} ر.س. يحق للمنصة تعليق استقبال الطلبات الجديدة بعد الإنذار وفق العقد، دون المساس بطلباتك القائمة.</div>}
      {sum?.orders_suspended && <div className="note" style={{ margin: '10px 0' }}>استقبال الطلبات الجديدة معلّق حالياً. سدّد المستحقات وتواصل مع الإدارة لاستئنافه.</div>}
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', margin: '14px 0' }}>
        {TABS.map(([k, v]) => <button key={k} className="badge" onClick={() => setTab(k)} style={{ border: 0, cursor: 'pointer', padding: '8px 12px', background: tab === k ? 'var(--green)' : undefined, color: tab === k ? '#fff' : undefined }}>
          {v}{k === 'notices' && sum?.unread_notifications > 0 ? ` (${sum.unread_notifications})` : ''}</button>)}
      </div>

      {tab === 'summary' && sum && <div className="card">
        <p className="muted" style={{ fontSize: 13, marginTop: 0 }}>العمولة الأساسية {pct(sum.commission_rate_bp)} من قيمة منتجاتك الأصلية قبل الضريبة والشحن{sum.commission_on_markup ? ' (تشمل الزيادة السعرية)' : ''}، مضافاً إليها الزيادة السعرية التي تحددها رواء. تصدر الفاتورة أول كل شهر ويستحق السداد يوم {sum.due_day}.</p>
        <h4 style={{ margin: '8px 0' }}>الشهر الحالي ({sum.current_month})</h4>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          {stat('طلبات مكتملة', String(m.orders ?? 0))}
          {stat('المبيعات بأسعارك الأصلية', riyal(m.original_sales_halalas) + ' ر.س')}
          {stat('العمولة الأساسية', riyal(m.base_commission_halalas) + ' ر.س')}
          {stat('الزيادات السعرية', riyal(m.markup_commission_halalas) + ' ر.س')}
          {stat('إجمالي عمولات الشهر', riyal(m.total_commission_halalas) + ' ر.س')}
        </div>
        <h4 style={{ margin: '16px 0 8px' }}>الإجمالي</h4>
        <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          {stat('المبيعات المكتملة (صافي الاسترجاع)', riyal(sum.completed_sales?.total_halalas) + ' ر.س')}
          {stat('عمولات لم تُفوتر بعد', riyal(sum.unbilled_commission_halalas) + ' ر.س')}
          {stat('مستحقات قائمة', riyal(sum.outstanding_halalas) + ' ر.س', sum.outstanding_halalas > 0)}
          {stat('متأخرات', riyal(sum.overdue_halalas) + ' ر.س', sum.overdue_halalas > 0)}
          {stat('رصيد دائن لك', riyal(sum.available_credit_halalas) + ' ر.س')}
        </div>
      </div>}

      {tab === 'invoices' && <div>
        {invoices.length === 0 && <p className="muted">لا توجد فواتير صادرة بعد.</p>}
        {invoices.map(inv => <InvoiceCard key={inv.id} inv={inv} onDone={() => sup && load(sup.id)} />)}
      </div>}

      {tab === 'payments' && <div className="card">
        <h4 style={{ marginTop: 0 }}>التحويلات المرسلة</h4>
        {pc.payments.length === 0 ? <p className="muted">لا توجد تحويلات.</p> : pc.payments.map((p: any) => (
          <div key={p.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid var(--line)', fontSize: 14, gap: 8, flexWrap: 'wrap' }}>
            <span>{p.invoice_no} · {p.reference} · {p.transfer_date ?? ''}</span>
            <span>{riyal(p.amount_halalas)} ر.س · {p.status === 'verified' ? '✓ معتمد' : p.status === 'rejected' ? '✗ مرفوض' + (p.review_note ? ` (${p.review_note})` : '') : 'بانتظار التحقق'}</span>
          </div>))}
        <h4>الإشعارات الدائنة والتسويات</h4>
        {pc.credit_notes.length === 0 ? <p className="muted">لا توجد إشعارات دائنة.</p> : pc.credit_notes.map((c: any) => (
          <div key={c.id} style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0', borderBottom: '1px solid var(--line)', fontSize: 14 }}>
            <span>{c.credit_note_no} · على {c.invoice_no} · {c.reason}</span><span>{riyal(c.total_halalas)} ر.س</span>
          </div>))}
      </div>}

      {tab === 'lines' && <div className="card" style={{ overflowX: 'auto' }}>
        <table style={{ width: '100%', fontSize: 13, borderCollapse: 'collapse' }}>
          <thead><tr>{['الطلب', 'المنتج', 'الكمية', 'سعرك', 'سعر البيع', 'النوع', 'الأساسية', 'الزيادة', 'الإجمالي', 'الشهر', 'الفاتورة'].map(h => <th key={h} style={{ textAlign: 'start', padding: 6, borderBottom: '1px solid var(--line)' }}>{h}</th>)}</tr></thead>
          <tbody>{lines.map((l, i) => <tr key={i} style={{ borderBottom: '1px solid var(--line)' }}>
            <td style={{ padding: 6 }}>{l.order_ref}</td><td>{l.product_name}</td><td>{l.quantity}</td><td>{riyal(l.original_unit_halalas)}</td><td>{riyal(l.sale_unit_halalas)}</td>
            <td>{l.kind === 'accrual' ? 'استحقاق' : 'استرجاع'}</td><td>{riyal(l.base_commission_halalas)}</td><td>{riyal(l.markup_commission_halalas)}</td><td><strong>{riyal(l.total_commission_halalas)}</strong></td>
            <td>{l.period_month}</td><td>{l.invoice_no ?? '—'}</td></tr>)}</tbody>
        </table>
        {lines.length === 0 && <p className="muted">لا توجد عمولات بعد — تُستحق العمولة عند اكتمال الطلب المدفوع وتوثيق التسليم.</p>}
      </div>}

      {tab === 'notices' && <div className="card">
        <button className="btn ghost" style={{ padding: '6px 12px', marginBottom: 8 }} onClick={markRead}>تعليم الكل كمقروء</button>
        {notices.length === 0 && <p className="muted">لا توجد إشعارات.</p>}
        {notices.map(n => <div key={n.id} style={{ padding: '8px 0', borderBottom: '1px solid var(--line)', opacity: n.read_at ? 0.7 : 1 }}>
          <strong style={{ fontSize: 14 }}>{n.read_at ? '' : '● '}{n.title}</strong><div className="muted" style={{ fontSize: 13 }}>{n.body}</div>
          <div className="muted" style={{ fontSize: 11 }}>{new Date(n.created_at).toLocaleString('ar-SA')}</div></div>)}
      </div>}

      {tab === 'contract' && <div>
        {contracts.length === 0 && <p className="muted">لا توجد نسخة موقّعة. <Link to="/supplier/contract" style={{ color: 'var(--green)' }}>عرض العقد وتوقيعه ←</Link></p>}
        {contracts.map(c => <div key={c.version_id} className="card" style={{ marginBottom: 12 }}>
          <strong>{c.title ?? 'اتفاقية المورد'}</strong> {c.is_current && <span className="badge">الإصدار الساري</span>}
          <p className="muted" style={{ fontSize: 12 }}>الإصدار {c.version_id} · وقّعه {c.signer_full_name} · {new Date(c.accepted_at).toLocaleString('ar-SA')} · البصمة <code dir="ltr">{String(c.body_sha256).slice(0, 16)}…</code></p>
          <div style={{ whiteSpace: 'pre-wrap', fontSize: 13, maxHeight: 320, overflow: 'auto', border: '1px solid var(--line)', borderRadius: 10, padding: 10 }}>{c.body_ar}</div>
        </div>)}
      </div>}
    </section>
  )
}

function InvoiceCard({ inv, onDone }: { inv: any; onDone: () => void }) {
  const [open, setOpen] = useState(false)
  const [amount, setAmount] = useState(''); const [ref, setRef] = useState(''); const [date, setDate] = useState(''); const [file, setFile] = useState<File | null>(null)
  const [msg, setMsg] = useState<string | null>(null); const [busy, setBusy] = useState(false)
  const balance = inv.total_halalas - inv.paid_halalas - inv.credited_halalas
  const payable = ['issued', 'partially_paid', 'overdue'].includes(inv.status) && balance > 0
  const submit = async () => {
    setBusy(true); setMsg(null)
    try {
      let proof: string | null = null
      if (file) {
        const { data: { user } } = await supabase.auth.getUser()
        proof = `${user!.id}/transfer-${inv.invoice_no}-${Date.now()}.${file.name.split('.').pop() || 'pdf'}`
        const up = await supabase.storage.from('invoice-payment-proofs').upload(proof, file)
        if (up.error) throw new Error(up.error.message)
      }
      const { error } = await supabase.rpc('supplier_submit_invoice_payment', { p_invoice: inv.id, p_amount_halalas: toHalalas(amount), p_reference: ref, p_transfer_date: date || null, p_proof_path: proof })
      if (error) throw new Error(error.message)
      setMsg('تم إرسال إشعار التحويل. يُعتمد السداد بعد تحقق الإدارة من وصول المبلغ.'); setOpen(false); onDone()
    } catch (e: any) { setMsg(e.message) } finally { setBusy(false) }
  }
  return (
    <div className="card" style={{ marginBottom: 10 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
        <div><strong>{inv.invoice_no}</strong> <span className="muted" style={{ fontSize: 13 }}>· {inv.period_month?.slice(0, 7)} · الاستحقاق {inv.due_date}</span></div>
        <Badge s={inv.status} map={INVOICE_STATUS} />
      </div>
      <div className="muted" style={{ fontSize: 13, margin: '6px 0' }}>الإجمالي {riyal(inv.total_halalas)} ر.س · المدفوع {riyal(inv.paid_halalas)} · إشعارات دائنة {riyal(inv.credited_halalas)} · <strong>المتبقي {riyal(Math.max(balance, 0))} ر.س</strong></div>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        <Link className="btn ghost" style={{ padding: '6px 12px' }} to={`/invoice/${inv.id}`}>عرض / تنزيل PDF</Link>
        {payable && <button className="btn" style={{ padding: '6px 12px' }} onClick={() => setOpen(o => !o)}>إرسال إشعار تحويل</button>}
      </div>
      {msg && <div className="note" style={{ marginTop: 8 }}>{msg}</div>}
      {open && <div style={{ marginTop: 10, borderTop: '1px solid var(--line)', paddingTop: 10 }}>
        <p className="muted" style={{ fontSize: 13 }}>حوّل المبلغ إلى حساب رواء: {inv.platform_snapshot?.bank_name} — <span dir="ltr">{inv.platform_snapshot?.iban}</span> باسم {inv.platform_snapshot?.account_holder}</p>
        <div className="field"><label>المبلغ المحوّل (ر.س)</label><input inputMode="decimal" value={amount} onChange={e => setAmount(e.target.value.replace(/[^\d.]/g, ''))} placeholder={riyal(balance)} /></div>
        <div className="field"><label>رقم مرجع التحويل</label><input value={ref} onChange={e => setRef(e.target.value)} /></div>
        <div className="field"><label>تاريخ التحويل</label><input type="date" value={date} onChange={e => setDate(e.target.value)} /></div>
        <div className="field"><label>إيصال التحويل (اختياري)</label><input type="file" accept="application/pdf,image/jpeg,image/png" onChange={e => setFile(e.target.files?.[0] || null)} /></div>
        <button className="btn" disabled={busy || toHalalas(amount) <= 0 || ref.trim().length < 3} onClick={submit}>{busy ? 'جارٍ الإرسال…' : 'إرسال ←'}</button>
      </div>}
    </div>
  )
}
