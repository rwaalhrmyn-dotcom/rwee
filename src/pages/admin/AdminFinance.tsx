import { useEffect, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { Badge, BLOCKERS, ENTITY_TYPES, INVOICE_STATUS, MISSING, PROFILE_STATUS, callFn, pct, riyal, toHalalas } from '../../lib/finance'

// Admin finance console: pricing & commissions, payment methods, contracts, commission invoices,
// transfers, arrears & disputes, reports and finance settings. Every action goes through an
// operator-only SECURITY DEFINER RPC that writes the audit log server-side.

const SECTIONS = {
  pricing: 'إدارة الأسعار والعمولات',
  gateways: 'وسائل دفع الموردين',
  contracts: 'العقود والإصدارات',
  invoices: 'فواتير العمولات',
  transfers: 'متابعة التحويلات',
  arrears: 'المتأخرات والتسويات',
  orders: 'طلبات الدفع المباشر',
  reports: 'التقارير المالية',
  settings: 'إعدادات المالية',
} as const
type Section = keyof typeof SECTIONS

const CATS: Record<string, string> = { water: 'مياه', quran: 'مصاحف', supplies: 'مستلزمات', food: 'أغذية', equipment: 'معدات' }
const SCOPES: Record<string, string> = { all: 'جميع المنتجات', supplier: 'مورد', category: 'تصنيف', product: 'منتج' }
const METHODS: Record<string, string> = { percent: 'نسبة مئوية %', fixed: 'مبلغ ثابت (ر.س)', final_price: 'سعر نهائي (ر.س)' }

async function rpc<T = any>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args)
  if (error) throw new Error(error.message)
  return data as T
}

const th: React.CSSProperties = { padding: '6px 8px', textAlign: 'start', borderBottom: '1px solid var(--line)', whiteSpace: 'nowrap', fontSize: 12 }
const td: React.CSSProperties = { padding: '6px 8px', borderBottom: '1px solid var(--line)', fontSize: 13, verticalAlign: 'top' }
function Table({ head, children }: { head: string[]; children: ReactNode }) {
  return <div style={{ overflowX: 'auto' }}><table style={{ width: '100%', borderCollapse: 'collapse' }}>
    <thead><tr>{head.map(h => <th key={h} style={th}>{h}</th>)}</tr></thead><tbody>{children}</tbody></table></div>
}
const Card = ({ title, children, right }: { title: string; children: ReactNode; right?: ReactNode }) => (
  <div className="card" style={{ marginBottom: 14 }}>
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
      <h3 style={{ margin: 0, fontSize: 15, color: 'var(--green)' }}>{title}</h3>{right}
    </div>
    <div style={{ marginTop: 10 }}>{children}</div>
  </div>
)
const fmtDate = (v?: string | null) => (v ? String(v).slice(0, 10) : '—')

export default function AdminFinance() {
  const [sec, setSec] = useState<Section>('pricing')
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null)
  const run = async (fn: () => Promise<unknown>, ok?: string) => {
    setMsg(null)
    try { await fn(); if (ok) setMsg({ ok: true, text: ok }) } catch (e: any) { setMsg({ ok: false, text: e.message }) }
  }
  const P = { run }
  return (
    <div>
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 12 }}>
        {(Object.keys(SECTIONS) as Section[]).map(k => (
          <button key={k} className={'btn' + (sec === k ? '' : ' ghost')} style={{ padding: '6px 12px', fontSize: 13 }} onClick={() => { setSec(k); setMsg(null) }}>{SECTIONS[k]}</button>
        ))}
      </div>
      {msg && <div className="note" style={{ marginBottom: 10, borderColor: msg.ok ? 'var(--green)' : '#b00020' }}>{msg.text}</div>}
      {sec === 'pricing' && <Pricing {...P} />}
      {sec === 'gateways' && <Gateways {...P} />}
      {sec === 'contracts' && <Contracts {...P} />}
      {sec === 'invoices' && <Invoices {...P} />}
      {sec === 'transfers' && <Transfers {...P} />}
      {sec === 'arrears' && <Arrears {...P} />}
      {sec === 'orders' && <DirectOrders {...P} />}
      {sec === 'reports' && <Reports />}
      {sec === 'settings' && <Settings {...P} />}
    </div>
  )
}
type Props = { run: (fn: () => Promise<unknown>, ok?: string) => Promise<void> }

// ------------------------------------------------------------------ pricing & commissions
const emptyRule = { id: null as string | null, scope: 'all', supplier: '', category: '', product: '', method: 'percent', value: '', note: '' }
function Pricing({ run }: Props) {
  const [fin, setFin] = useState<any>(null)
  const [rules, setRules] = useState<any[]>([])
  const [ov, setOv] = useState<any[]>([])
  const [audit, setAudit] = useState<any[]>([])
  const [r, setR] = useState({ ...emptyRule })
  const [preview, setPreview] = useState<any[] | null>(null)
  const [filter, setFilter] = useState('')
  const load = () => run(async () => {
    const [f, ru, o, a] = await Promise.all([rpc('admin_finance_settings'), rpc('admin_pricing_rules'), rpc('admin_pricing_overview'), rpc('admin_pricing_audit', { p_limit: 100 })])
    setFin(f); setRules(ru ?? []); setOv(o ?? []); setAudit(a ?? [])
  })
  useEffect(() => { load() }, [])

  const suppliers = Array.from(new Map(ov.map(x => [x.supplier_id, x.supplier_name])).entries())
  const valueInt = () => r.method === 'percent' ? Math.round(Number(r.value) * 100) : toHalalas(r.value)
  const args = () => ({ p_rule_id: r.id, p_scope: r.scope, p_supplier: r.scope === 'supplier' ? r.supplier || null : null,
    p_category: r.scope === 'category' ? r.category || null : null, p_product: r.scope === 'product' ? r.product || null : null,
    p_method: r.method, p_value: valueInt() })
  const doPreview = () => run(async () => setPreview(await rpc('admin_preview_pricing_rule', { ...args(), p_active: true }) ?? []))
  const save = () => run(async () => {
    await rpc('admin_save_pricing_rule', { ...args(), p_note: r.note || null })
    setR({ ...emptyRule }); setPreview(null); await load()
  }, 'تم حفظ القاعدة ونشر الأسعار الجديدة. السعر الأصلي للمورد لم يتغيّر.')
  const edit = (x: any) => {
    const v = x.rule
    setR({ id: v.id, scope: v.scope, supplier: v.supplier_id ?? '', category: v.category ?? '', product: v.product_id ?? '', method: v.method,
      value: v.method === 'percent' ? String(v.value / 100) : String(v.value / 100), note: v.note ?? '' }); setPreview(null)
  }
  const toggle = (x: any) => run(async () => { await rpc('admin_set_pricing_rule_active', { p_rule_id: x.rule.id, p_active: !x.rule.active }); await load() }, 'تم تحديث حالة القاعدة')
  const ovF = ov.filter(x => !filter || (x.product_name + ' ' + x.supplier_name).includes(filter))

  return <>
    {fin && <Card title="العمولة الأساسية">
      <p style={{ margin: 0, fontSize: 14 }}>العمولة الأساسية الحالية: <strong>{pct(fin.commission_rate_bp)}</strong> من السعر الأصلي للمورد (قبل الضريبة والشحن)
        {fin.commission_on_markup ? ' + على الزيادة السعرية (مفعّل بموجب العقد)' : ' — لا تُحتسب على الزيادة السعرية'}.
        عمولة المنصة على كل بند = العمولة الأساسية + الزيادة السعرية (سعر البيع − السعر الأصلي). تُعدّل من «إعدادات المالية»، ولا تؤثر على الطلبات السابقة (لكل بند لقطة ثابتة وقت الشراء).</p>
    </Card>}

    <Card title={r.id ? 'تعديل قاعدة تسعير' : 'قاعدة تسعير جديدة'}>
      <p className="muted" style={{ fontSize: 12, marginTop: 0 }}>الأولوية: منتج ← مورد ← تصنيف ← جميع المنتجات. قاعدة نشطة واحدة لكل نطاق؛ لا يُسمح بسعر نهائي أقل من السعر الأصلي.</p>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(160px,1fr))', gap: 8 }}>
        <div className="field"><label>النطاق</label><select value={r.scope} onChange={e => setR({ ...r, scope: e.target.value, method: e.target.value !== 'product' && r.method === 'final_price' ? 'percent' : r.method })}>
          {Object.entries(SCOPES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></div>
        {r.scope === 'supplier' && <div className="field"><label>المورد</label><select value={r.supplier} onChange={e => setR({ ...r, supplier: e.target.value })}>
          <option value="">—</option>{suppliers.map(([id, n]) => <option key={id} value={id}>{n}</option>)}</select></div>}
        {r.scope === 'category' && <div className="field"><label>التصنيف</label><select value={r.category} onChange={e => setR({ ...r, category: e.target.value })}>
          <option value="">—</option>{Object.entries(CATS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></div>}
        {r.scope === 'product' && <div className="field"><label>المنتج</label><select value={r.product} onChange={e => setR({ ...r, product: e.target.value })}>
          <option value="">—</option>{ov.map(p => <option key={p.product_id} value={p.product_id}>{p.product_name} — {p.supplier_name}</option>)}</select></div>}
        <div className="field"><label>طريقة الزيادة</label><select value={r.method} onChange={e => setR({ ...r, method: e.target.value })}>
          {Object.entries(METHODS).filter(([k]) => k !== 'final_price' || r.scope === 'product').map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></div>
        <div className="field"><label>القيمة {r.method === 'percent' ? '(%)' : '(ر.س)'}</label><input inputMode="decimal" value={r.value} onChange={e => setR({ ...r, value: e.target.value })} /></div>
        <div className="field"><label>ملاحظة</label><input value={r.note} onChange={e => setR({ ...r, note: e.target.value })} /></div>
      </div>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        <button className="btn ghost" disabled={r.value === ''} onClick={doPreview}>معاينة قبل النشر</button>
        <button className="btn" disabled={!preview} onClick={save} title={!preview ? 'اعرض المعاينة أولاً' : ''}>اعتماد ونشر</button>
        {r.id && <button className="btn ghost" onClick={() => { setR({ ...emptyRule }); setPreview(null) }}>إلغاء التعديل</button>}
      </div>
      {preview && <div style={{ marginTop: 10 }}>
        <p style={{ fontSize: 13 }}>ستتأثر <strong>{preview.filter(x => x.governed_by_proposed && x.changed).length}</strong> منتجات
          {preview.some(x => x.conflict) && <span style={{ color: '#b00020' }}> — تنبيه: يوجد تعارض (سعر نهائي أقل من الأصلي) سيُرفض عند الحفظ</span>}</p>
        <Table head={['المنتج', 'المورد', 'السعر الأصلي', 'السعر الحالي', 'القاعدة الحالية', 'الزيادة الجديدة', 'السعر الجديد', 'شامل الضريبة', 'يطبَّق؟']}>
          {preview.map(x => <tr key={x.product_id} style={{ opacity: x.governed_by_proposed ? 1 : 0.55 }}>
            <td style={td}>{x.product_name}</td><td style={td}>{x.supplier_name}</td><td style={td}>{riyal(x.original_halalas)}</td>
            <td style={td}>{riyal(x.current_price_halalas)}</td><td style={td}>{SCOPES[x.current_rule_scope] ?? '—'}</td>
            <td style={td}>{riyal(x.new_markup_halalas)}</td><td style={td}><strong>{riyal(x.new_price_halalas)}</strong></td><td style={td}>{riyal(x.new_display_price_halalas)}</td>
            <td style={td}>{x.conflict ? '⚠ تعارض' : x.governed_by_proposed ? '✓' : 'قاعدة أعلى أولوية'}</td></tr>)}
        </Table>
      </div>}
    </Card>

    <Card title="قواعد التسعير">
      {rules.length === 0 ? <p className="muted">لا توجد قواعد — تُعرض المنتجات بسعرها الأصلي.</p> :
        <Table head={['النطاق', 'الطريقة', 'القيمة', 'المنتجات الخاضعة', 'الحالة', 'آخر تعديل', '']}>
          {rules.map(x => <tr key={x.rule.id}>
            <td style={td}>{x.target_label}</td><td style={td}>{METHODS[x.rule.method]}</td>
            <td style={td}>{x.rule.method === 'percent' ? pct(x.rule.value) : riyal(x.rule.value) + ' ر.س'}</td>
            <td style={td}>{x.products_governed}</td><td style={td}>{x.rule.active ? 'نشطة' : 'موقوفة'}</td><td style={td}>{fmtDate(x.rule.updated_at)}</td>
            <td style={td}><button className="btn ghost" style={{ padding: '3px 8px' }} onClick={() => edit(x)}>تعديل</button>{' '}
              <button className="btn ghost" style={{ padding: '3px 8px' }} onClick={() => toggle(x)}>{x.rule.active ? 'إيقاف' : 'تفعيل'}</button></td></tr>)}
        </Table>}
    </Card>

    <Card title="منتجات الموردين وأسعارها" right={<input placeholder="بحث…" value={filter} onChange={e => setFilter(e.target.value)} style={{ maxWidth: 200 }} />}>
      <Table head={['المنتج', 'المورد', 'الأصلي', 'الزيادة', 'سعر البيع', 'شامل الضريبة', 'القاعدة', 'عمولة أساسية/وحدة', 'إجمالي العمولة/وحدة']}>
        {ovF.map(x => <tr key={x.product_id} style={{ background: x.price_conflict ? '#fff1f1' : undefined }}>
          <td style={td}>{x.product_name}{!x.active && <span className="muted"> (غير معروض)</span>}</td><td style={td}>{x.supplier_name ?? '—'}</td>
          <td style={td}>{riyal(x.original_halalas)}</td><td style={td}>{riyal(x.markup_halalas)}</td><td style={td}><strong>{riyal(x.price_halalas)}</strong></td>
          <td style={td}>{riyal(x.display_price_halalas)}{x.vat_rate_bp ? '' : ' (غير خاضع)'}</td>
          <td style={td}>{x.rule_scope ? `${SCOPES[x.rule_scope]} · ${x.rule_method === 'percent' ? pct(x.rule_value) : riyal(x.rule_value)}` : '—'}{x.price_conflict && ' ⚠'}</td>
          <td style={td}>{riyal(x.base_commission_unit)}</td><td style={td}>{riyal(x.total_commission_unit)}</td></tr>)}
      </Table>
    </Card>

    <Card title="سجل التدقيق (الأسعار والإعدادات)">
      <Table head={['التاريخ', 'المسؤول', 'العنصر', 'الإجراء', 'القيمة السابقة', 'القيمة الجديدة']}>
        {audit.map(a => <tr key={a.id}>
          <td style={td}>{new Date(a.created_at).toLocaleString('ar-SA')}</td><td style={td}>{a.actor_email ?? 'النظام'}</td>
          <td style={td}>{a.entity_label ?? a.entity_type}</td><td style={td}>{a.action}</td>
          <td style={{ ...td, fontSize: 11 }}><code dir="ltr">{JSON.stringify(a.old_value)}</code></td><td style={{ ...td, fontSize: 11 }}><code dir="ltr">{JSON.stringify(a.new_value)}</code></td></tr>)}
      </Table>
    </Card>
  </>
}

// ------------------------------------------------------------------ supplier payment methods
function Gateways({ run }: Props) {
  const [rows, setRows] = useState<any[]>([])
  const [note, setNote] = useState<Record<string, string>>({})
  const load = () => run(async () => setRows(await rpc('admin_payment_profiles') ?? []))
  useEffect(() => { load() }, [])
  const act = (id: string, action: string) => run(async () => { await rpc('admin_review_payment_profile', { p_supplier: id, p_action: action, p_note: note[id] || null }); await load() }, 'تم تحديث حالة وسيلة الدفع')
  const decide = (req: string, approve: boolean, id: string) => run(async () => { await rpc('admin_decide_payment_change', { p_request: req, p_approve: approve, p_note: note[id] || null }); await load() }, approve ? 'تم اعتماد التعديل' : 'تم رفض التعديل')
  const cert = async (path: string) => {
    const { data, error } = await supabase.storage.from('seller-documents').createSignedUrl(path, 120)
    if (error) alert(error.message); else window.open(data.signedUrl, '_blank', 'noopener')
  }
  return <>{rows.length === 0 && <p className="muted">لا يوجد موردون معتمدون.</p>}
    {rows.map(x => { const p = x.profile ?? {}; return (
      <Card key={x.supplier_id} title={x.supplier_name} right={<Badge s={p.status ?? 'incomplete'} map={PROFILE_STATUS} />}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(220px,1fr))', gap: '4px 16px', fontSize: 13 }}>
          <div>البريد: {x.owner_email ?? '—'}</div>
          <div>نوع المنشأة: {ENTITY_TYPES[p.entity_type] ?? '—'}</div>
          <div>الاسم التجاري: {p.legal_name ?? '—'}</div>
          <div>السجل التجاري: {p.cr_number ?? '—'}</div>
          <div>صاحب الحساب: {p.account_holder_name ?? '—'}</div>
          <div>البنك: {p.bank_name ?? '—'}{p.iban_bank_detected && p.iban_bank_detected !== p.bank_name ? ` (الآيبان يشير إلى: ${p.iban_bank_detected})` : ''}</div>
          <div>الآيبان: <span dir="ltr">{p.iban ?? '—'}</span> {p.iban ? (p.iban_valid ? '✓' : '✗') : ''}</div>
          <div>الضريبة: {p.vat_registered ? <>مسجل · <span dir="ltr">{p.tax_number}</span> {p.vat_certificate_path && <button className="btn ghost" style={{ padding: '1px 6px', fontSize: 12 }} onClick={() => cert(p.vat_certificate_path)}>الشهادة</button>}</> : 'غير مسجل'}</div>
          <div>البوابة: {p.gateway_provider ? `Tap · ${p.gateway_mode === 'live' ? 'حي' : 'تجريبي'} · …${p.gateway_key_hint ?? ''} · ${p.gateway_check_status}` : 'غير مرتبطة'}</div>
          <div>البيع: {x.selling_enabled ? '✓ مفعّل' : 'متوقف'}</div>
        </div>
        {x.missing?.length > 0 && <p style={{ fontSize: 13 }}>ناقص: {x.missing.map((m: string) => MISSING[m] ?? m).join('، ')}</p>}
        {!x.selling_enabled && x.blockers?.length > 0 && <p style={{ fontSize: 13 }}>العوائق: {x.blockers.map((b: string) => BLOCKERS[b] ?? b).join('، ')}</p>}
        {x.pending_change && <div className="note" style={{ fontSize: 13 }}>طلب تعديل بيانات حساسة ({fmtDate(x.pending_change.created_at)}):
          <code dir="ltr" style={{ display: 'block', fontSize: 11 }}>{JSON.stringify(x.pending_change.proposed)}{x.pending_change.gateway ? ' + gateway' : ''}</code>
          <div style={{ display: 'flex', gap: 6, marginTop: 6 }}>
            <button className="btn" style={{ padding: '4px 10px' }} onClick={() => decide(x.pending_change.id, true, x.supplier_id)}>اعتماد التعديل</button>
            <button className="btn ghost" style={{ padding: '4px 10px' }} onClick={() => decide(x.pending_change.id, false, x.supplier_id)}>رفض</button></div></div>}
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginTop: 8, alignItems: 'center' }}>
          <input placeholder="ملاحظة / سبب" value={note[x.supplier_id] ?? ''} onChange={e => setNote({ ...note, [x.supplier_id]: e.target.value })} style={{ maxWidth: 260 }} />
          {p.status === 'pending' && <><button className="btn" style={{ padding: '4px 10px' }} onClick={() => act(x.supplier_id, 'approve')}>اعتماد وسيلة الدفع</button>
            <button className="btn ghost" style={{ padding: '4px 10px' }} onClick={() => act(x.supplier_id, 'reject')}>رفض</button></>}
          {p.status === 'active' && <button className="btn ghost" style={{ padding: '4px 10px' }} onClick={() => act(x.supplier_id, 'suspend')}>إيقاف</button>}
          {p.status === 'suspended' && <button className="btn" style={{ padding: '4px 10px' }} onClick={() => act(x.supplier_id, 'reactivate')}>إعادة تفعيل</button>}
        </div>
      </Card>) })}
  </>
}

// ------------------------------------------------------------------ contracts
function Contracts({ run }: Props) {
  const [vers, setVers] = useState<any[]>([])
  const [sel, setSel] = useState<string | null>(null)
  const [text, setText] = useState<any>(null)
  const [acc, setAcc] = useState<any[]>([])
  const [rev, setRev] = useState({ reviewer: '', note: '' })
  const [draft, setDraft] = useState({ version: '', title: '', body: '' })
  const load = () => run(async () => setVers(await rpc('admin_contract_versions') ?? []))
  useEffect(() => { load() }, [])
  const open = (v: string) => run(async () => {
    setSel(v); const [t, a] = await Promise.all([rpc('admin_contract_text', { p_version: v }), rpc('admin_contract_acceptances_detail', { p_version: v })])
    setText(t); setAcc(a ?? [])
    const row = vers.find(x => x.version_id === v)
    if (row && !row.published) setDraft({ version: v, title: t?.title ?? row.title ?? '', body: t?.body_ar ?? '' })
  })
  const review = () => run(async () => { await rpc('admin_record_contract_legal_review', { p_version: sel, p_reviewer: rev.reviewer, p_note: rev.note || null }); await load(); await open(sel!) }, 'تم تسجيل اعتماد المراجعة القانونية')
  const publish = () => { if (confirm('نشر هذا الإصدار يجعله العقد الساري ويطلب من جميع الموردين قبوله. متابعة؟'))
    run(async () => { await rpc('admin_publish_contract', { p_version: sel }); await load() }, 'تم نشر الإصدار وإشعار الموردين') }
  const saveDraft = () => run(async () => { await rpc('admin_save_contract_draft', { p_version: draft.version, p_title: draft.title, p_body: draft.body }); await load() }, 'تم حفظ المسودة (تعود حالة المراجعة القانونية إلى «بانتظار المراجعة»)')
  const cur = vers.find(x => x.version_id === sel)
  return <>
    <Card title="إصدارات اتفاقية المورد">
      <Table head={['الإصدار', 'العنوان', 'الحالة', 'المراجعة القانونية', 'القبولات', '']}>
        {vers.map(v => <tr key={v.version_id}>
          <td style={td} dir="ltr">{v.version_id}</td><td style={td}>{v.title ?? '—'}</td>
          <td style={td}>{v.is_current ? 'ساري' : v.published ? 'منشور سابقاً' : 'مسودة'}</td>
          <td style={td}>{v.legal_review_status === 'approved' ? `✓ ${v.legal_reviewer ?? ''} ${fmtDate(v.legal_reviewed_at)}` : 'بانتظار المراجعة'}</td>
          <td style={td}>{v.acceptances}</td>
          <td style={td}><button className="btn ghost" style={{ padding: '3px 8px' }} onClick={() => open(v.version_id)}>عرض</button></td></tr>)}
      </Table>
      <p className="muted" style={{ fontSize: 12 }}>لا يمكن نشر إصدار قبل تسجيل اعتماد المراجعة القانونية. الإصدارات المنشورة لا تُعدّل؛ أي تغيير يكون بإصدار جديد.</p>
    </Card>
    {sel && text && <Card title={`نص الإصدار ${sel}`}>
      {cur && !cur.published ? <>
        <div className="field"><label>العنوان</label><input value={draft.title} onChange={e => setDraft({ ...draft, title: e.target.value })} /></div>
        <div className="field"><label>النص</label><textarea rows={16} value={draft.body} onChange={e => setDraft({ ...draft, body: e.target.value })} /></div>
        <button className="btn ghost" onClick={saveDraft}>حفظ المسودة</button>
      </> : <pre style={{ whiteSpace: 'pre-wrap', fontFamily: 'inherit', fontSize: 13, maxHeight: 420, overflow: 'auto', background: 'var(--bg-soft,#f7faf8)', padding: 10, borderRadius: 8 }}>{text.body_ar}</pre>}
      <p className="muted" style={{ fontSize: 11 }}>بصمة النص: <span dir="ltr">{text.body_sha256}</span></p>
      {cur && !cur.published && <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', alignItems: 'center', marginTop: 8 }}>
        <input placeholder="اسم المراجع القانوني" value={rev.reviewer} onChange={e => setRev({ ...rev, reviewer: e.target.value })} style={{ maxWidth: 220 }} />
        <input placeholder="ملاحظة المراجعة" value={rev.note} onChange={e => setRev({ ...rev, note: e.target.value })} style={{ maxWidth: 260 }} />
        <button className="btn ghost" disabled={rev.reviewer.trim().length < 3} onClick={review}>تسجيل اعتماد المراجعة القانونية</button>
        <button className="btn" disabled={cur.legal_review_status !== 'approved'} onClick={publish}>نشر كإصدار ساري</button>
      </div>}
      <h4 style={{ fontSize: 14, marginBottom: 4 }}>سجل القبول ({acc.length})</h4>
      <Table head={['المورد', 'الموقّع', 'البريد', 'التاريخ', 'بصمة النص']}>
        {acc.map((a, i) => <tr key={i}><td style={td}>{a.supplier}</td><td style={td}>{a.signer}</td><td style={td}>{a.signer_email}</td>
          <td style={td}>{new Date(a.accepted_at).toLocaleString('ar-SA')}</td><td style={{ ...td, fontSize: 11 }} dir="ltr">{String(a.body_sha256).slice(0, 16)}…</td></tr>)}
      </Table>
    </Card>}
  </>
}

// ------------------------------------------------------------------ commission invoices
const prevMonth = () => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - 1); return d.toISOString().slice(0, 7) }
function Invoices({ run }: Props) {
  const [rows, setRows] = useState<any[]>([])
  const [status, setStatus] = useState('')
  const [month, setMonth] = useState('')
  const [closeM, setCloseM] = useState(prevMonth())
  const [cn, setCn] = useState<Record<string, { amount: string; reason: string }>>({})
  const load = () => run(async () => setRows(await rpc('admin_invoices', { p_status: status || null, p_month: month ? month + '-01' : null }) ?? []))
  useEffect(() => { load() }, [status, month])
  const close = (issue: boolean) => run(async () => { const r = await rpc('admin_close_period', { p_month: closeM + '-01', p_issue: issue }); await load(); return r },
    issue ? 'تم إقفال الفترة وإصدار الفواتير (لا تتكرر الفاتورة لنفس الفترة).' : 'تم إقفال الفترة وإنشاء المسودات.')
  const issue = (id: string) => run(async () => { await rpc('admin_issue_invoice', { p_invoice: id }); await load() }, 'تم إصدار الفاتورة وإشعار المورد')
  const credit = (id: string) => run(async () => {
    const c = cn[id]; await rpc('admin_issue_credit_note', { p_invoice: id, p_amount_halalas: toHalalas(c.amount), p_reason: c.reason, p_source: 'manual' })
    setCn({ ...cn, [id]: { amount: '', reason: '' } }); await load()
  }, 'تم إصدار إشعار دائن مرتبط بالفاتورة (الفاتورة الأصلية محفوظة دون حذف)')
  return <>
    <Card title="إقفال فترة شهرية">
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
        <input type="month" value={closeM} onChange={e => setCloseM(e.target.value)} style={{ maxWidth: 180 }} />
        <button className="btn ghost" onClick={() => close(false)}>إقفال كمسودات</button>
        <button className="btn" onClick={() => close(true)}>إقفال وإصدار</button>
      </div>
      <p className="muted" style={{ fontSize: 12 }}>تُجمع العمولات المستحقة من الطلبات المكتملة والمدفوعة خلال الشهر الميلادي (توقيت الرياض)، وتُصدر فاتورة واحدة لكل مورد لكل فترة، وتستحق حتى اليوم المحدد من الشهر التالي. يعمل الإقفال تلقائياً يومياً بعد انتهاء الشهر.</p>
    </Card>
    <Card title="الفواتير" right={<div style={{ display: 'flex', gap: 6 }}>
      <select value={status} onChange={e => setStatus(e.target.value)}><option value="">كل الحالات</option>{Object.entries(INVOICE_STATUS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}</select>
      <input type="month" value={month} onChange={e => setMonth(e.target.value)} /></div>}>
      {rows.length === 0 ? <p className="muted">لا توجد فواتير.</p> : rows.map(x => { const i = x.invoice; const c = cn[i.id] ?? { amount: '', reason: '' }; return (
        <div key={i.id} style={{ borderBottom: '1px solid var(--line)', padding: '10px 0' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
            <div><strong dir="ltr">{i.invoice_no ?? 'مسودة'}</strong> · {x.supplier_name} · {i.period_month?.slice(0, 7)}</div>
            <Badge s={i.status} map={INVOICE_STATUS} />
          </div>
          <div style={{ fontSize: 13, display: 'flex', gap: 14, flexWrap: 'wrap', marginTop: 4 }}>
            <span>الطلبات: {i.order_count}</span><span>المبيعات الأصلية: {riyal(i.gross_original_halalas)}</span>
            <span>أساسية: {riyal(i.base_commission_halalas)}</span><span>زيادات: {riyal(i.markup_commission_halalas)}</span>
            <span>تسويات: {riyal(i.adjustments_halalas)}</span><span>ضريبة: {riyal(i.vat_halalas)}</span>
            <strong>الإجمالي: {riyal(i.total_halalas)} ر.س</strong><span>المتبقي: {riyal(x.balance_halalas)}</span>
            <span>الاستحقاق: {fmtDate(i.due_date)}</span>{x.days_overdue > 0 && <span style={{ color: '#b00020' }}>متأخرة {x.days_overdue} يوم</span>}
          </div>
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginTop: 6, alignItems: 'center' }}>
            {i.status === 'draft' && <button className="btn" style={{ padding: '3px 10px' }} onClick={() => issue(i.id)}>إصدار</button>}
            {i.status !== 'draft' && <Link className="btn ghost" style={{ padding: '3px 10px' }} to={`/invoice/${i.id}`}>عرض / PDF</Link>}
            {['issued', 'partially_paid', 'overdue', 'paid'].includes(i.status) && <>
              <input placeholder="مبلغ إشعار دائن" inputMode="decimal" value={c.amount} onChange={e => setCn({ ...cn, [i.id]: { ...c, amount: e.target.value } })} style={{ maxWidth: 130 }} />
              <input placeholder="السبب" value={c.reason} onChange={e => setCn({ ...cn, [i.id]: { ...c, reason: e.target.value } })} style={{ maxWidth: 200 }} />
              <button className="btn ghost" style={{ padding: '3px 10px' }} disabled={!c.amount || c.reason.trim().length < 3} onClick={() => credit(i.id)}>إصدار إشعار دائن</button></>}
          </div>
        </div>) })}
    </Card>
  </>
}

// ------------------------------------------------------------------ transfers
function Transfers({ run }: Props) {
  const [status, setStatus] = useState('submitted')
  const [rows, setRows] = useState<any[]>([])
  const [note, setNote] = useState<Record<string, string>>({})
  const [invs, setInvs] = useState<any[]>([])
  const [m, setM] = useState({ invoice: '', amount: '', ref: '', date: new Date().toISOString().slice(0, 10) })
  const load = () => run(async () => {
    const [p, i] = await Promise.all([rpc('admin_invoice_payments', { p_status: status || null }), rpc('admin_invoices', { p_status: null, p_month: null })])
    setRows(p ?? []); setInvs((i ?? []).filter((x: any) => ['issued', 'partially_paid', 'overdue'].includes(x.invoice.status)))
  })
  useEffect(() => { load() }, [status])
  const review = (id: string, approve: boolean) => run(async () => { await rpc('admin_review_invoice_payment', { p_payment: id, p_approve: approve, p_note: note[id] || null }); await load() },
    approve ? 'تم اعتماد التحويل وتحديث رصيد الفاتورة' : 'تم رفض التحويل')
  const proof = async (path: string) => {
    const { data, error } = await supabase.storage.from('invoice-payment-proofs').createSignedUrl(path, 120)
    if (error) alert(error.message); else window.open(data.signedUrl, '_blank', 'noopener')
  }
  const record = () => run(async () => {
    await rpc('admin_record_invoice_payment', { p_invoice: m.invoice, p_amount_halalas: toHalalas(m.amount), p_reference: m.ref, p_transfer_date: m.date })
    setM({ ...m, amount: '', ref: '' }); await load()
  }, 'تم تسجيل الدفعة بعد المطابقة البنكية')
  return <>
    <Card title="تحويلات مرسلة من الموردين" right={<select value={status} onChange={e => setStatus(e.target.value)}>
      <option value="submitted">بانتظار التحقق</option><option value="verified">معتمدة</option><option value="rejected">مرفوضة</option><option value="">الكل</option></select>}>
      <p className="muted" style={{ fontSize: 12, marginTop: 0 }}>لا يُعتبر التحويل سداداً إلا بعد اعتماده هنا بعد مطابقته مع كشف حساب رواء البنكي.</p>
      {rows.length === 0 ? <p className="muted">لا توجد تحويلات.</p> :
        <Table head={['الفاتورة', 'المورد', 'المبلغ', 'المرجع', 'تاريخ التحويل', 'الإثبات', 'الحالة', '']}>
          {rows.map(p => <tr key={p.id}>
            <td style={td} dir="ltr">{p.invoice_no}</td><td style={td}>{p.supplier_name}</td><td style={td}>{riyal(p.amount_halalas)}</td>
            <td style={td} dir="ltr">{p.reference ?? '—'}</td><td style={td}>{fmtDate(p.transfer_date)}</td>
            <td style={td}>{p.proof_path ? <button className="btn ghost" style={{ padding: '2px 6px' }} onClick={() => proof(p.proof_path)}>عرض</button> : '—'}</td>
            <td style={td}>{p.status}</td>
            <td style={td}>{p.status === 'submitted' && <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
              <input placeholder="ملاحظة" value={note[p.id] ?? ''} onChange={e => setNote({ ...note, [p.id]: e.target.value })} style={{ maxWidth: 140 }} />
              <button className="btn" style={{ padding: '2px 8px' }} onClick={() => review(p.id, true)}>اعتماد</button>
              <button className="btn ghost" style={{ padding: '2px 8px' }} onClick={() => review(p.id, false)}>رفض</button></div>}</td></tr>)}
        </Table>}
    </Card>
    <Card title="تسجيل دفعة مطابقة بنكياً">
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(160px,1fr))', gap: 8 }}>
        <div className="field"><label>الفاتورة</label><select value={m.invoice} onChange={e => setM({ ...m, invoice: e.target.value })}><option value="">—</option>
          {invs.map(x => <option key={x.invoice.id} value={x.invoice.id}>{x.invoice.invoice_no} — {x.supplier_name} (متبقي {riyal(x.balance_halalas)})</option>)}</select></div>
        <div className="field"><label>المبلغ (ر.س)</label><input inputMode="decimal" value={m.amount} onChange={e => setM({ ...m, amount: e.target.value })} /></div>
        <div className="field"><label>مرجع التحويل</label><input value={m.ref} onChange={e => setM({ ...m, ref: e.target.value })} /></div>
        <div className="field"><label>تاريخ التحويل</label><input type="date" value={m.date} onChange={e => setM({ ...m, date: e.target.value })} /></div>
      </div>
      <button className="btn" disabled={!m.invoice || !m.amount || m.ref.trim().length < 3} onClick={record}>تسجيل الدفعة</button>
    </Card>
  </>
}

// ------------------------------------------------------------------ arrears, suspensions, disputes, alerts
function Arrears({ run }: Props) {
  const [od, setOd] = useState<any[]>([])
  const [alerts, setAlerts] = useState<any[]>([])
  const [disputes, setDisputes] = useState<any[]>([])
  const [note, setNote] = useState<Record<string, string>>({})
  const load = () => run(async () => {
    const [i, a, d] = await Promise.all([rpc('admin_invoices', { p_status: 'overdue', p_month: null }), rpc('admin_finance_alerts', { p_include_resolved: false }), rpc('admin_disputes', { p_open_only: true })])
    setOd(i ?? []); setAlerts(a ?? []); setDisputes(d ?? [])
  })
  useEffect(() => { load() }, [])
  const suspend = (sup: string, s: boolean, force = false) => run(async () => {
    await rpc('admin_set_orders_suspended', { p_supplier: sup, p_suspend: s, p_reason: note[sup] || (s ? 'تأخر سداد فاتورة العمولات' : 'تمت التسوية'), p_force: force }); await load()
  }, s ? 'تم تعليق استقبال الطلبات الجديدة (الطلبات القائمة والسجلات لا تتأثر)' : 'تم استئناف استقبال الطلبات')
  const resolve = (id: string) => run(async () => { await rpc('admin_resolve_finance_alert', { p_alert: id, p_note: note[id] || 'تمت المعالجة' }); await load() })
  const dispute = (id: string, st: string) => run(async () => { await rpc('admin_resolve_dispute', { p_dispute: id, p_status: st, p_note: note[id] || null }); await load() }, 'تم تحديث النزاع')
  return <>
    <Card title={`فواتير متأخرة (${od.length})`}>
      {od.length === 0 ? <p className="muted">لا توجد متأخرات.</p> :
        <Table head={['الفاتورة', 'المورد', 'المتبقي', 'الاستحقاق', 'أيام التأخر', 'إجراء']}>
          {od.map(x => <tr key={x.invoice.id}>
            <td style={td}><Link to={`/invoice/${x.invoice.id}`} dir="ltr">{x.invoice.invoice_no}</Link></td><td style={td}>{x.supplier_name}</td>
            <td style={td}>{riyal(x.balance_halalas)}</td><td style={td}>{fmtDate(x.invoice.due_date)}</td><td style={{ ...td, color: '#b00020' }}>{x.days_overdue}</td>
            <td style={td}><div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
              <input placeholder="السبب" value={note[x.invoice.supplier_id] ?? ''} onChange={e => setNote({ ...note, [x.invoice.supplier_id]: e.target.value })} style={{ maxWidth: 140 }} />
              <button className="btn ghost" style={{ padding: '2px 8px' }} onClick={() => suspend(x.invoice.supplier_id, true)}>تعليق الطلبات الجديدة</button>
              <button className="btn ghost" style={{ padding: '2px 8px' }} onClick={() => suspend(x.invoice.supplier_id, false)}>استئناف</button></div></td></tr>)}
        </Table>}
      <p className="muted" style={{ fontSize: 12 }}>التعليق يتطلب انقضاء مهلة الإنذار المحددة في الإعدادات بعد الاستحقاق، ولا يمس الطلبات القائمة أو السجلات المالية.</p>
    </Card>
    <Card title={`تنبيهات مالية مفتوحة (${alerts.length})`}>
      {alerts.length === 0 ? <p className="muted">لا توجد تنبيهات.</p> :
        <Table head={['التاريخ', 'النوع', 'المورد', 'التفاصيل', '']}>
          {alerts.map(a => <tr key={a.id}><td style={td}>{new Date(a.created_at).toLocaleString('ar-SA')}</td><td style={td}>{a.kind}</td><td style={td}>{a.supplier_name ?? '—'}</td>
            <td style={{ ...td, fontSize: 11 }}><code dir="ltr">{JSON.stringify(a.details ?? a.payload ?? {})}</code></td>
            <td style={td}><button className="btn ghost" style={{ padding: '2px 8px' }} onClick={() => resolve(a.id)}>تمت المعالجة</button></td></tr>)}
        </Table>}
    </Card>
    <Card title={`نزاعات الدفع (${disputes.length})`}>
      {disputes.length === 0 ? <p className="muted">لا توجد نزاعات مفتوحة.</p> :
        <Table head={['الطلب', 'المورد', 'المبلغ', 'السبب', 'الحالة', '']}>
          {disputes.map(d => <tr key={d.id}><td style={td} dir="ltr">{String(d.order_id).slice(0, 8)}</td><td style={td}>{d.supplier_name}</td><td style={td}>{riyal(d.order_total)}</td>
            <td style={td}>{d.reason}</td><td style={td}>{d.status}</td>
            <td style={td}><div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
              <input placeholder="ملاحظة" value={note[d.id] ?? ''} onChange={e => setNote({ ...note, [d.id]: e.target.value })} style={{ maxWidth: 130 }} />
              {d.status === 'open' && <button className="btn ghost" style={{ padding: '2px 8px' }} onClick={() => dispute(d.id, 'under_review')}>قيد المراجعة</button>}
              <button className="btn ghost" style={{ padding: '2px 8px' }} onClick={() => dispute(d.id, 'resolved_customer')}>لصالح العميل</button>
              <button className="btn ghost" style={{ padding: '2px 8px' }} onClick={() => dispute(d.id, 'resolved_supplier')}>لصالح المورد</button></div></td></tr>)}
        </Table>}
    </Card>
  </>
}

// ------------------------------------------------------------------ direct-payment orders (refunds)
function DirectOrders({ run }: Props) {
  const [rows, setRows] = useState<any[]>([])
  const [rf, setRf] = useState<Record<string, { amount: string; reason: string }>>({})
  const load = () => run(async () => setRows(await rpc('admin_direct_orders', { p_limit: 300 }) ?? []))
  useEffect(() => { load() }, [])
  const refund = (o: any) => {
    const r = rf[o.id] ?? { amount: '', reason: '' }
    const amt = toHalalas(r.amount)
    if (!confirm(`استرجاع ${riyal(amt)} ر.س عبر بوابة المورد؟ سيُخصم ما يقابله من العمولة.`)) return
    run(async () => {
      const { ok, data } = await callFn('order-refund', { order_id: o.id, amount_halalas: amt, reason: r.reason.trim() })
      if (!ok) throw new Error(data?.error ?? 'تعذّر تنفيذ الاسترجاع')
      setRf({ ...rf, [o.id]: { amount: '', reason: '' } }); await load()
    }, 'تم إرسال الاسترجاع إلى بوابة المورد وتسجيله')
  }
  return <Card title="طلبات محصّلة مباشرة لحساب المورد">
    <p className="muted" style={{ fontSize: 12, marginTop: 0 }}>تصبح هذه الطلبات «مدفوعة» فقط بعد تأكيد موثّق من بوابة المورد (Webhook)، ولا يمكن تعديل حالة الدفع يدوياً. الاسترجاع يتم عبر بوابة المورد نفسها.</p>
    {rows.length === 0 ? <p className="muted">لا توجد طلبات دفع مباشر بعد.</p> :
      <Table head={['الطلب', 'التاريخ', 'المورد', 'المبلغ', 'الدفع', 'الحالة', 'العمولة', 'مسترجع', 'ملاحظات', 'استرجاع']}>
        {rows.map(o => { const r = rf[o.id] ?? { amount: '', reason: '' }; return <tr key={o.id}>
          <td style={td} dir="ltr">{String(o.id).slice(0, 8)}</td><td style={td}>{fmtDate(o.created_at)}</td><td style={td}>{o.supplier_name}</td>
          <td style={td}>{riyal(o.payable_halalas)}</td><td style={td}>{o.payment_status}</td><td style={td}>{o.status}</td>
          <td style={td}>{riyal(o.commission_halalas)}</td><td style={td}>{o.refunded_halalas ? riyal(o.refunded_halalas) : '—'}</td>
          <td style={td}>{[o.payment_flag, o.open_dispute ? 'نزاع مفتوح' : null].filter(Boolean).join(' · ') || '—'}</td>
          <td style={td}>{o.payment_status === 'paid' && (o.refunded_halalas ?? 0) < o.payable_halalas && <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
            <input placeholder="المبلغ" inputMode="decimal" value={r.amount} onChange={e => setRf({ ...rf, [o.id]: { ...r, amount: e.target.value } })} style={{ maxWidth: 80 }} />
            <input placeholder="السبب" value={r.reason} onChange={e => setRf({ ...rf, [o.id]: { ...r, reason: e.target.value } })} style={{ maxWidth: 120 }} />
            <button className="btn ghost" style={{ padding: '2px 8px' }} disabled={!r.amount || r.reason.trim().length < 3} onClick={() => refund(o)}>استرجاع</button></div>}</td></tr> })}
      </Table>}
  </Card>
}

// ------------------------------------------------------------------ reports
function Reports() {
  const y = new Date().getFullYear()
  const [from, setFrom] = useState(`${y}-01-01`)
  const [to, setTo] = useState(new Date().toISOString().slice(0, 10))
  const [rep, setRep] = useState<any>(null)
  const [err, setErr] = useState<string | null>(null)
  const load = async () => { setErr(null); try { setRep(await rpc('admin_finance_report', { p_from: from, p_to: to })) } catch (e: any) { setErr(e.message) } }
  useEffect(() => { load() }, [])
  const csv = () => {
    const lines = [['month', 'orders', 'original_sales', 'base_commission', 'markup_commission', 'total_commission'].join(','),
      ...(rep?.by_month ?? []).map((m: any) => [m.month, m.orders, riyal(m.original_sales_halalas), riyal(m.base_commission_halalas), riyal(m.markup_commission_halalas), riyal(m.total_commission_halalas)].join(','))]
    const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + lines.join('\n')], { type: 'text/csv' })); a.download = `rawaa-commissions-${from}-${to}.csv`; a.click()
  }
  const inv = rep?.invoices ?? {}
  return <>
    <Card title="الفترة" right={<button className="btn ghost" disabled={!rep} onClick={csv}>تصدير CSV</button>}>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
        <input type="date" value={from} onChange={e => setFrom(e.target.value)} /><input type="date" value={to} onChange={e => setTo(e.target.value)} />
        <button className="btn" onClick={load}>عرض</button></div>
      {err && <div className="note">{err}</div>}
    </Card>
    {rep && <>
      <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginBottom: 14 }}>
        {[['المُفوتر', inv.issued_halalas], ['المحصّل', inv.paid_halalas], ['إشعارات دائنة', inv.credited_halalas], ['المستحق القائم', inv.outstanding_halalas], ['الاسترجاعات', rep.refunds_halalas]].map(([l, v]) =>
          <div key={l as string} className="card" style={{ flex: '1 1 140px', textAlign: 'center', padding: 12 }}><div style={{ fontSize: 20, fontWeight: 700, color: 'var(--green)' }}>{riyal(v as number)}</div><div className="muted" style={{ fontSize: 12 }}>{l as string} (ر.س)</div></div>)}
        <div className="card" style={{ flex: '1 1 140px', textAlign: 'center', padding: 12 }}><div style={{ fontSize: 20, fontWeight: 700, color: '#b00020' }}>{inv.overdue_count ?? 0}</div><div className="muted" style={{ fontSize: 12 }}>فواتير متأخرة</div></div>
      </div>
      <Card title="حسب الشهر">
        <Table head={['الشهر', 'الطلبات', 'المبيعات الأصلية', 'العمولة الأساسية', 'الزيادات', 'إجمالي العمولة']}>
          {rep.by_month.map((m: any) => <tr key={m.month}><td style={td}>{String(m.month).slice(0, 7)}</td><td style={td}>{m.orders}</td><td style={td}>{riyal(m.original_sales_halalas)}</td>
            <td style={td}>{riyal(m.base_commission_halalas)}</td><td style={td}>{riyal(m.markup_commission_halalas)}</td><td style={td}><strong>{riyal(m.total_commission_halalas)}</strong></td></tr>)}
        </Table>
      </Card>
      <Card title="حسب المورد">
        <Table head={['المورد', 'العمولات في الفترة', 'المستحق القائم']}>
          {rep.by_supplier.map((s: any) => <tr key={s.supplier_id}><td style={td}>{s.supplier}</td><td style={td}>{riyal(s.total_commission_halalas)}</td><td style={td}>{riyal(s.outstanding_halalas)}</td></tr>)}
        </Table>
      </Card>
    </>}
  </>
}

// ------------------------------------------------------------------ finance settings
function Settings({ run }: Props) {
  const [s, setS] = useState<any>(null)
  const [f, setF] = useState<any>({})
  const load = () => run(async () => { const d = await rpc('admin_finance_settings'); setS(d); setF(d) })
  useEffect(() => { load() }, [])
  if (!s) return null
  const set = (k: string, v: unknown) => setF({ ...f, [k]: v })
  const save = () => run(async () => {
    const keys = ['commission_rate_bp', 'commission_on_markup', 'vat_rate_bp', 'platform_vat_registered', 'platform_vat_number', 'platform_legal_name', 'platform_cr_number',
      'platform_address', 'platform_bank_name', 'platform_iban', 'platform_account_holder', 'invoice_due_day', 'reminder_days_before', 'suspension_grace_days',
      'auto_issue_invoices', 'contract_reaccept_grace_days']
    const p: Record<string, unknown> = {}
    for (const k of keys) if (JSON.stringify(f[k]) !== JSON.stringify(s[k])) p[k] = f[k]
    if (Object.keys(p).length === 0) return
    await rpc('admin_update_finance_settings', { p }); await load()
  }, 'تم حفظ الإعدادات وتسجيلها في سجل التدقيق')
  const flag = (k: string, v: boolean, warn: string) => { if (confirm(warn)) run(async () => { await rpc('admin_update_finance_settings', { p: { [k]: v } }); await load() }, 'تم التحديث') }
  const num = (k: string, label: string, hint?: string) => <div className="field"><label>{label}</label><input inputMode="numeric" value={f[k] ?? ''} onChange={e => set(k, e.target.value === '' ? null : Number(e.target.value.replace(/\D/g, '')))} />{hint && <p className="muted" style={{ fontSize: 11 }}>{hint}</p>}</div>
  const txt = (k: string, label: string, ltr = false) => <div className="field"><label>{label}</label><input dir={ltr ? 'ltr' : undefined} value={f[k] ?? ''} onChange={e => set(k, e.target.value || null)} /></div>
  const chk = (k: string, label: string) => <label style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '6px 0' }}><input type="checkbox" checked={!!f[k]} onChange={e => set(k, e.target.checked)} /> {label}</label>
  return <>
    <Card title="تشغيل نظام الدفع المباشر للمورد">
      <p style={{ fontSize: 14, margin: 0 }}>الحالة: <strong>{s.direct_payments_enabled ? 'مفعّل' : 'غير مفعّل (الوضع الحالي للمنصة مستمر)'}</strong></p>
      <p className="muted" style={{ fontSize: 12 }}>عند التفعيل: لا تظهر للعملاء إلا منتجات الموردين المكتملة بياناتهم والمعتمدة وسيلة دفعهم والقابلين للعقد الساري، ويُحصَّل كل طلب عبر بوابة المورد مباشرة.</p>
      <button className="btn" onClick={() => flag('direct_payments_enabled', !s.direct_payments_enabled, s.direct_payments_enabled ? 'إيقاف الدفع المباشر وإعادة المنصة للوضع السابق؟' : 'تفعيل الدفع المباشر؟ تأكد من نشر العقد بعد مراجعته قانونياً واعتماد وسائل دفع الموردين.')}>
        {s.direct_payments_enabled ? 'إيقاف' : 'تفعيل'}</button>
      <hr />
      <p style={{ fontSize: 14, margin: 0 }}>اعتماد الحسابات الحية لـ Tap: <strong>{s.tap_live_contract_confirmed ? 'مؤكد' : 'غير مؤكد'}</strong></p>
      <p className="muted" style={{ fontSize: 12 }}>لا تُعتمد مفاتيح Tap الحية للموردين إلا بعد تأكيد كتابي من Tap بأن التحصيل يتم مباشرة لحساب المورد دون رسوم شهرية غير معتمدة.</p>
      <button className="btn ghost" onClick={() => flag('tap_live_contract_confirmed', !s.tap_live_contract_confirmed, 'هل حصلت على تأكيد مكتوب من Tap؟')}>{s.tap_live_contract_confirmed ? 'إلغاء التأكيد' : 'تسجيل التأكيد'}</button>
    </Card>
    <Card title="العمولات والضريبة">
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(200px,1fr))', gap: 8 }}>
        {num('commission_rate_bp', 'العمولة الأساسية (نقطة أساس، 500 = 5%)', `الحالي: ${pct(f.commission_rate_bp)}`)}
        {num('vat_rate_bp', 'نسبة ضريبة القيمة المضافة (نقطة أساس)', `الحالي: ${pct(f.vat_rate_bp)}`)}
      </div>
      {chk('commission_on_markup', 'احتساب العمولة الأساسية على الزيادة السعرية أيضاً (فقط إذا نص عليه العقد)')}
      {chk('platform_vat_registered', 'رواء مسجلة في ضريبة القيمة المضافة (تُضاف الضريبة على فواتير العمولة)')}
      {f.platform_vat_registered && txt('platform_vat_number', 'الرقم الضريبي لرواء', true)}
    </Card>
    <Card title="بيانات رواء في الفواتير">
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(200px,1fr))', gap: 8 }}>
        {txt('platform_legal_name', 'الاسم النظامي')}{txt('platform_cr_number', 'السجل التجاري', true)}{txt('platform_address', 'العنوان')}
        {txt('platform_bank_name', 'البنك')}{txt('platform_iban', 'الآيبان', true)}{txt('platform_account_holder', 'اسم صاحب الحساب')}
      </div>
    </Card>
    <Card title="الفوترة والتحصيل">
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit,minmax(200px,1fr))', gap: 8 }}>
        {num('invoice_due_day', 'يوم الاستحقاق من الشهر التالي')}{num('reminder_days_before', 'التذكير قبل الاستحقاق (أيام)')}
        {num('suspension_grace_days', 'مهلة الإنذار قبل التعليق (أيام)')}{num('contract_reaccept_grace_days', 'مهلة قبول إصدار العقد الجديد (أيام)')}
      </div>
      {chk('auto_issue_invoices', 'إصدار الفواتير تلقائياً عند إقفال الشهر')}
    </Card>
    <button className="btn" onClick={save}>حفظ الإعدادات</button>
  </>
}
