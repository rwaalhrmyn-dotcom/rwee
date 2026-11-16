import { useEffect, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { ENTITY_TYPES, INVOICE_STATUS, riyal } from '../lib/finance'

// Commission invoice document (supplier owner or operator). Rendered from the immutable
// snapshot stored at issue time, so the printed/downloaded PDF never changes later.
export default function InvoiceDocument() {
  const { id } = useParams()
  const [doc, setDoc] = useState<any>(null)
  const [err, setErr] = useState<string | null>(null)
  const [qr, setQr] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => { (async () => {
    const { data, error } = await supabase.rpc('invoice_document', { p_invoice: id })
    if (error) { setErr(error.message); return }
    setDoc(data)
    const tlv = data?.invoice?.zatca_qr_tlv
    if (tlv) { const QR = await import('qrcode'); setQr(await QR.toDataURL(tlv, { margin: 1, width: 140 })) }
  })() }, [id])

  const download = async () => {
    if (!ref.current || !doc) return
    setBusy(true)
    try {
      const html2pdf = (await import('html2pdf.js')).default as any
      await html2pdf().set({ margin: 8, filename: `${doc.invoice.invoice_no}.pdf`, image: { type: 'jpeg', quality: 0.96 },
        html2canvas: { scale: 2, useCORS: true }, jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' } }).from(ref.current).save()
    } finally { setBusy(false) }
  }

  if (err) return <section style={{ padding: '32px 0' }}><div className="note">تعذّر عرض الفاتورة: {err}</div></section>
  if (!doc) return <section style={{ padding: '32px 0' }}><p className="muted">جارٍ تحميل الفاتورة…</p></section>
  const inv = doc.invoice, p = inv.platform_snapshot ?? {}, s = inv.supplier_snapshot ?? {}
  const st = INVOICE_STATUS[inv.status] ?? { label: inv.status }
  const r = (k: string, v: string, bold = false) => <tr><td style={{ padding: '5px 8px', color: '#555' }}>{k}</td><td style={{ padding: '5px 8px', textAlign: 'left', fontWeight: bold ? 700 : 400 }}>{v}</td></tr>
  const th: React.CSSProperties = { padding: 6, borderBottom: '1px solid #ccc', textAlign: 'start', background: '#f4f7f5' }

  return (
    <section style={{ padding: '24px 0', maxWidth: 820 }}>
      <div className="no-print" style={{ display: 'flex', gap: 8, marginBottom: 12, flexWrap: 'wrap' }}>
        <button className="btn ghost" onClick={() => history.back()}>رجوع</button>
        <button className="btn" disabled={busy} onClick={download}>{busy ? 'جارٍ الإنشاء…' : 'تنزيل PDF'}</button>
        <button className="btn ghost" onClick={() => window.print()}>طباعة</button>
      </div>
      <div ref={ref} dir="rtl" style={{ background: '#fff', color: '#111', padding: 24, border: '1px solid #ddd', borderRadius: 8, fontSize: 13, lineHeight: 1.6 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, alignItems: 'flex-start' }}>
          <div>
            <div style={{ fontSize: 20, fontWeight: 700, color: '#0b5d49' }}>فاتورة عمولات خدمات المنصة</div>
            <div>{p.legal_name} · سجل تجاري {p.cr_number}</div>
            {p.vat_registered && <div>الرقم الضريبي: {p.vat_number}</div>}
            {p.address && <div>{p.address}</div>}
          </div>
          <div style={{ textAlign: 'left' }}>
            <div><strong>رقم الفاتورة:</strong> <span dir="ltr">{inv.invoice_no}</span></div>
            <div><strong>تاريخ الإصدار:</strong> {inv.issue_date}</div>
            <div><strong>تاريخ الاستحقاق:</strong> {inv.due_date}</div>
            <div><strong>الحالة:</strong> {st.label}</div>
            {qr && <img src={qr} alt="ZATCA QR" style={{ width: 110, marginTop: 6 }} />}
          </div>
        </div>
        <hr />
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16, flexWrap: 'wrap' }}>
          <div><strong>المورد:</strong> {s.legal_name || s.name}{s.entity_type ? ` (${ENTITY_TYPES[s.entity_type] ?? s.entity_type})` : ''}<br />
            سجل تجاري: {s.cr_number ?? '—'} · الرقم الضريبي: {s.vat_number ?? '—'}<br />{s.address ?? ''}</div>
          <div><strong>الفترة المحاسبية:</strong> {inv.period_start} — {inv.period_end}<br /><strong>عدد الطلبات المكتملة:</strong> {inv.order_count}</div>
        </div>
        <table style={{ width: '100%', borderCollapse: 'collapse', margin: '14px 0' }}>
          <thead><tr><th style={th}>الطلب</th><th style={th}>تاريخ الاكتمال</th><th style={th}>المبيعات الأصلية</th><th style={th}>العمولة الأساسية</th><th style={th}>الزيادة السعرية</th><th style={th}>تسويات</th></tr></thead>
          <tbody>{doc.orders.map((o: any) => <tr key={o.order_ref}>
            <td style={{ padding: 6, borderBottom: '1px solid #eee' }} dir="ltr">{o.order_ref}</td>
            <td style={{ padding: 6, borderBottom: '1px solid #eee' }}>{o.delivered_at ? String(o.delivered_at).slice(0, 10) : '—'}</td>
            <td style={{ padding: 6, borderBottom: '1px solid #eee' }}>{riyal(o.original_halalas)}</td>
            <td style={{ padding: 6, borderBottom: '1px solid #eee' }}>{riyal(o.base_halalas)}</td>
            <td style={{ padding: 6, borderBottom: '1px solid #eee' }}>{riyal(o.markup_halalas)}</td>
            <td style={{ padding: 6, borderBottom: '1px solid #eee' }}>{riyal(o.adjustment_halalas)}</td></tr>)}</tbody>
        </table>
        <table style={{ width: '60%', marginInlineStart: 'auto', borderCollapse: 'collapse' }}><tbody>
          {r('إجمالي المبيعات الأصلية المؤهلة', riyal(inv.gross_original_halalas) + ' ر.س')}
          {r('العمولة الأساسية', riyal(inv.base_commission_halalas) + ' ر.س')}
          {r('إجمالي الزيادات السعرية', riyal(inv.markup_commission_halalas) + ' ر.س')}
          {r('الخصومات والتسويات والاسترجاعات', riyal(inv.adjustments_halalas) + ' ر.س')}
          {inv.credits_applied_halalas > 0 && r('رصيد دائن سابق مطبَّق', '-' + riyal(inv.credits_applied_halalas) + ' ر.س')}
          {r('إجمالي مستحقات رواء', riyal(inv.subtotal_halalas) + ' ر.س')}
          {r(inv.vat_halalas > 0 ? `ضريبة خدمات المنصة (${inv.vat_rate_bp / 100}%)` : 'ضريبة خدمات المنصة', inv.vat_halalas > 0 ? riyal(inv.vat_halalas) + ' ر.س' : 'غير مطبّقة (المنصة غير ملزمة نظاماً)')}
          {r('المبلغ النهائي المطلوب سداده', riyal(inv.total_halalas) + ' ر.س', true)}
          {inv.paid_halalas > 0 && r('المدفوع المعتمد', riyal(inv.paid_halalas) + ' ر.س')}
          {inv.credited_halalas > 0 && r('إشعارات دائنة', riyal(inv.credited_halalas) + ' ر.س')}
          {r('المتبقي', riyal(Math.max(doc.balance_halalas, 0)) + ' ر.س', true)}
        </tbody></table>
        <div style={{ marginTop: 14, padding: 10, background: '#f4f7f5', borderRadius: 6 }}>
          <strong>بيانات السداد المعتمدة:</strong> {p.bank_name} · الآيبان <span dir="ltr">{p.iban}</span> · باسم {p.account_holder}<br />
          يُسدَّد المبلغ في موعد أقصاه {inv.due_date}. لا يُعتبر التحويل مسدداً إلا بعد التحقق منه واعتماده.
        </div>
        {doc.credit_notes.length > 0 && <div style={{ marginTop: 10 }}><strong>إشعارات دائنة مرتبطة:</strong> {doc.credit_notes.map((c: any) => `${c.no} (${riyal(c.total_halalas)} ر.س — ${c.reason})`).join('، ')}</div>}
        <div style={{ marginTop: 14, fontSize: 11, color: '#666' }}>بصمة المستند: <span dir="ltr">{inv.snapshot_sha256}</span></div>
      </div>
    </section>
  )
}
