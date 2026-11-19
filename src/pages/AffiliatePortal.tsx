import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { riyal, pct, isValidSaIban, normalizeIban } from '../lib/finance'
import { AFF_STATUS, EARN_STATE, SIDE } from '../lib/affiliate'

// Commission marketer portal: sign-in like the rest of the site (mobile OTP or Google) -> registration
// (e-mail is a plain contact field) with the electronic agreement -> dashboard with referral links,
// visits, orders, earnings and payouts.
export default function AffiliatePortal() {
  const [user, setUser] = useState<{ id: string; email?: string } | null | undefined>(undefined)
  const [data, setData] = useState<any>(undefined)
  const load = async () => {
    const { data: { session } } = await supabase.auth.getSession()
    setUser(session?.user ? { id: session.user.id, email: session.user.email ?? undefined } : null)
    if (session) { const r = await supabase.rpc('my_affiliate'); setData(r.data ?? null) } else setData(null)
  }
  useEffect(() => { load() }, [])

  return (
    <section style={{ padding: '32px 0', maxWidth: 820 }}>
      <h2 style={{ color: 'var(--green)' }}>التسويق بالعمولة — رِواء الحرمين</h2>
      {user === undefined ? <p className="muted">جارٍ التحميل…</p>
        : !user ? <SignIn />
        : data === undefined ? <p className="muted">جارٍ التحميل…</p>
        : data === null ? <Register email={user.email ?? ''} onDone={load} />
        : <Dashboard d={data} onChange={load} />}
    </section>
  )
}

function Intro() {
  const [t, setT] = useState<any>(null)
  useEffect(() => { supabase.rpc('affiliate_terms_public').then(r => setT(r.data)) }, [])
  return <div className="card" style={{ marginBottom: 14 }}>
    <p style={{ marginTop: 0 }}>اربح عمولة من جانبين: <strong>المبيعات</strong> التي تأتي عبر رابطك، و<strong>الموردين</strong> الذين تجذبهم للمنصة.</p>
    <ul style={{ fontSize: 14, margin: 0, paddingInlineStart: 18 }}>
      <li>تحدد الإدارة نسبتي العمولة عند اعتماد انضمامك، وتُحتسب من صافي ربح رواء المتحقق فعلياً.</li>
      <li>فترة تجربة {t?.trial_days ?? 30} يوماً، ثم تقرر الإدارة الاستمرار.</li>
      <li>لا تُستحق أي مبالغ إلا بعد تحقق ربح فعلي وتحصيله من المورد. الحد الأدنى للصرف {riyal(t?.min_payout_halalas ?? 10000)} ر.س.</li>
    </ul>
  </div>
}

function SignIn() {
  return <>
    <Intro />
    <div className="card">
      <p style={{ marginTop: 0 }}>سجّل الدخول أولاً (برقم الجوال أو حساب Google) ثم أكمل نموذج الانضمام وتوقيع الاتفاقية.</p>
      <Link className="btn" to="/customer/login?redirect=/affiliate" style={{ display: 'block', textAlign: 'center' }}>تسجيل الدخول والمتابعة ←</Link>
    </div>
  </>
}

function Register({ email, onDone }: { email: string; onDone: () => void }) {
  const [c, setC] = useState<any>(null)
  const [f, setF] = useState({ full_name: '', email, phone: '', city: '', channels: '', bank_name: '', iban: '', account_holder_name: '' })
  const [agree, setAgree] = useState(false); const [signer, setSigner] = useState('')
  const [msg, setMsg] = useState<string | null>(null); const [busy, setBusy] = useState(false)
  useEffect(() => { supabase.rpc('current_affiliate_contract').then(r => setC(r.data)) }, [])
  const set = (k: string, v: string) => setF({ ...f, [k]: v })
  const ibanOk = !f.iban || isValidSaIban(f.iban)
  const submit = async () => {
    setBusy(true); setMsg(null)
    const { error } = await supabase.rpc('affiliate_register', { p: { ...f, iban: normalizeIban(f.iban) }, p_contract_version: c.version_id,
      p_contract_hash: c.body_sha256, p_signer_name: signer.trim(), p_agreed: agree })
    setBusy(false)
    if (error) setMsg('تعذّر التسجيل: ' + error.message); else onDone()
  }
  const field = (k: keyof typeof f, label: string, extra: any = {}) => <div className="field"><label>{label}</label><input value={f[k]} onChange={e => set(k, e.target.value)} {...extra} /></div>
  return <>
    <Intro />
    <div className="card">
      {field('full_name', 'الاسم الكامل *')}
      {field('email', 'البريد الإلكتروني *', { type: 'email', dir: 'ltr', placeholder: 'name@example.com' })}
      {field('phone', 'رقم الجوال (للتواصل)', { inputMode: 'numeric', placeholder: '05xxxxxxxx' })}
      {field('city', 'المدينة')}
      {field('channels', 'قنوات التسويق (حسابات التواصل، موقع، مجموعات…)')}
      <h4 style={{ fontSize: 14, marginBottom: 4 }}>حساب استلام المستحقات (يمكن إضافته لاحقاً)</h4>
      {field('bank_name', 'اسم البنك')}
      <div className="field"><label>الآيبان</label><input dir="ltr" value={f.iban} onChange={e => set('iban', normalizeIban(e.target.value).slice(0, 24))} placeholder="SA…" />
        {!ibanOk && <p className="muted" style={{ fontSize: 12, color: '#b00020' }}>الآيبان غير صحيح</p>}</div>
      {field('account_holder_name', 'اسم صاحب الحساب (يجب أن يكون باسمك)')}
      <h3 style={{ fontSize: 15, color: 'var(--green)' }}>{c?.title ?? 'الاتفاقية'}</h3>
      <pre style={{ whiteSpace: 'pre-wrap', fontFamily: 'inherit', fontSize: 13, maxHeight: 360, overflow: 'auto', background: 'var(--bg-soft,#f7faf8)', padding: 12, borderRadius: 8, border: '1px solid var(--line)' }}>{c?.body_ar ?? 'جارٍ تحميل الاتفاقية…'}</pre>
      <p className="muted" style={{ fontSize: 11 }}>الإصدار <span dir="ltr">{c?.version_id}</span> · بصمة النص <span dir="ltr">{String(c?.body_sha256 ?? '').slice(0, 16)}…</span></p>
      <div className="field"><label>اكتب اسمك الكامل للتوقيع الإلكتروني *</label><input value={signer} onChange={e => setSigner(e.target.value)} /></div>
      <label style={{ display: 'flex', gap: 8, alignItems: 'flex-start', margin: '8px 0' }}>
        <input type="checkbox" checked={agree} onChange={e => setAgree(e.target.checked)} style={{ marginTop: 4 }} />
        <span style={{ fontSize: 14 }}>قرأت الاتفاقية كاملة وأوافق عليها وأقرّ بأن هذا التوقيع الإلكتروني ملزم لي، وأنه لا يحق لي المطالبة بأي مبالغ ما لم يتحقق ربح فعلي عن طريقي.</span>
      </label>
      {msg && <div className="note" style={{ margin: '8px 0' }}>{msg}</div>}
      <button className="btn" style={{ width: '100%' }} disabled={busy || !c || !agree || f.full_name.trim().length < 3 || !/^\S+@\S+\.\S+$/.test(f.email.trim()) || signer.trim() !== f.full_name.trim() || !ibanOk} onClick={submit}>
        {busy ? 'جارٍ الإرسال…' : 'توقيع الاتفاقية وإرسال طلب الانضمام ←'}</button>
      {agree && signer.trim() && signer.trim() !== f.full_name.trim() && <p className="muted" style={{ fontSize: 12 }}>يجب أن يطابق اسم التوقيع الاسم الكامل.</p>}
    </div>
  </>
}

function Dashboard({ d, onChange }: { d: any; onChange: () => void }) {
  const p = d.profile, s = d.summary, st = AFF_STATUS[p.effective_status] ?? { label: p.status, color: 'var(--muted)' }
  const [copied, setCopied] = useState<string | null>(null)
  const [showContract, setShowContract] = useState(false)
  const [bank, setBank] = useState({ bank: p.bank_name ?? '', iban: '', holder: p.account_holder_name ?? '' })
  const [msg, setMsg] = useState<string | null>(null)
  const origin = location.origin
  const links = [['رابط المبيعات (للعملاء)', `${origin}/?ref=${p.code}`], ['رابط جذب الموردين', `${origin}/supplier/register?ref=${p.code}`]]
  const copy = async (v: string) => { try { await navigator.clipboard.writeText(v); setCopied(v); setTimeout(() => setCopied(null), 1500) } catch { /* ignore */ } }
  const earning = ['trial', 'active'].includes(p.effective_status)
  const saveBank = async () => {
    setMsg(null)
    const { error } = await supabase.rpc('affiliate_update_payout_details', { p_bank: bank.bank, p_iban: normalizeIban(bank.iban), p_holder: bank.holder })
    if (error) setMsg(error.message); else { setMsg('تم حفظ بيانات الحساب.'); onChange() }
  }
  const kpi = (label: string, v: string, hint?: string) => <div className="card" style={{ flex: '1 1 150px', textAlign: 'center', padding: 12 }} title={hint}>
    <div style={{ fontSize: 19, fontWeight: 700, color: 'var(--green)' }}>{v}</div><div className="muted" style={{ fontSize: 12 }}>{label}</div></div>
  return <>
    <div className="card" style={{ marginBottom: 14 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
        <strong>{p.full_name} · <span dir="ltr">{p.code}</span></strong>
        <span className="badge" style={{ background: st.color, color: '#fff' }}>{st.label}</span>
      </div>
      <p style={{ fontSize: 13, margin: '8px 0 0' }}>
        {p.trial_started_at && <>فترة التجربة: {String(p.trial_started_at).slice(0, 10)} — {String(p.trial_ends_at).slice(0, 10)} · </>}
        عمولة المبيعات: <strong>{pct(p.sales_rate_bp)}</strong> · عمولة جذب الموردين: <strong>{pct(p.supplier_rate_bp)}</strong> <span className="muted">(من صافي ربح رواء المتحقق)</span>
      </p>
      {p.status_reason && <p className="muted" style={{ fontSize: 13 }}>ملاحظة الإدارة: {p.status_reason}</p>}
      {p.status === 'pending' && <div className="note" style={{ marginTop: 8 }}>طلبك قيد المراجعة. يبدأ رابطك بالعمل وتبدأ فترة التجربة بعد اعتماد الإدارة.</div>}
    </div>

    {earning && <div className="card" style={{ marginBottom: 14 }}>
      <h3 style={{ marginTop: 0, fontSize: 15, color: 'var(--green)' }}>روابطك</h3>
      {links.map(([l, v]) => <div key={v} style={{ display: 'flex', gap: 6, alignItems: 'center', marginBottom: 6, flexWrap: 'wrap' }}>
        <span style={{ fontSize: 13, minWidth: 150 }}>{l}</span>
        <input readOnly dir="ltr" value={v} style={{ flex: 1, minWidth: 200 }} onFocus={e => e.target.select()} />
        <button className="btn ghost" style={{ padding: '4px 10px' }} onClick={() => copy(v)}>{copied === v ? '✓ نُسخ' : 'نسخ'}</button>
      </div>)}
      <p className="muted" style={{ fontSize: 12, marginBottom: 0 }}>يُنسب لك الطلب إذا أتمّه العميل خلال {d.terms?.cookie_days ?? 30} يوماً من زيارته عبر رابطك. الإحالة الذاتية والطلبات الوهمية تُلغى وفق الاتفاقية.</p>
    </div>}

    <div style={{ display: 'flex', gap: 10, flexWrap: 'wrap', marginBottom: 14 }}>
      {kpi('زيارات (30 يوماً)', String(s.clicks_30d))}
      {kpi('طلبات عبر رابطك', String(s.orders))}
      {kpi('موردون جذبتهم', String(s.referred_suppliers))}
      {kpi('بانتظار اكتمال الطلبات', riyal(s.pending_halalas))}
      {kpi('بانتظار تحصيل رواء', riyal(s.awaiting_collection_halalas), 'تستحق بعد سداد المورد لعمولة رواء')}
      {kpi('المصروف لك', riyal(s.paid_halalas))}
      {kpi('الرصيد القابل للصرف', riyal(s.balance_halalas))}
    </div>

    <div className="card" style={{ marginBottom: 14, overflowX: 'auto' }}>
      <h3 style={{ marginTop: 0, fontSize: 15, color: 'var(--green)' }}>العمليات والأرباح</h3>
      {d.orders.length === 0 ? <p className="muted">لا توجد عمليات بعد.</p> :
        <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}><thead><tr>{['الطلب', 'التاريخ', 'المصدر', 'قيمة الطلب', 'ربحك', 'الحالة'].map(h => <th key={h} style={{ textAlign: 'start', padding: 6, borderBottom: '1px solid var(--line)' }}>{h}</th>)}</tr></thead>
          <tbody>{d.orders.map((o: any, i: number) => <tr key={o.ref + i}><td style={{ padding: 6 }} dir="ltr">{o.ref}</td><td style={{ padding: 6 }}>{String(o.created_at).slice(0, 10)}</td>
            <td style={{ padding: 6 }}>{SIDE[o.side] ?? o.side}</td><td style={{ padding: 6 }}>{riyal(o.payable_halalas)}</td><td style={{ padding: 6 }}><strong>{riyal(o.earning_halalas)}</strong></td>
            <td style={{ padding: 6 }}>{EARN_STATE[o.state] ?? o.state}{o.void_reason ? ` — ${o.void_reason}` : ''}</td></tr>)}</tbody></table>}
    </div>

    {d.suppliers.length > 0 && <div className="card" style={{ marginBottom: 14 }}>
      <h3 style={{ marginTop: 0, fontSize: 15, color: 'var(--green)' }}>الموردون الذين جذبتهم</h3>
      {d.suppliers.map((x: any) => <div key={x.name} style={{ fontSize: 13 }}>{x.name} · {pct(x.rate_bp)} · {x.selling ? 'يبيع الآن' : 'لم يبدأ البيع'}</div>)}
    </div>}

    <div className="card" style={{ marginBottom: 14 }}>
      <h3 style={{ marginTop: 0, fontSize: 15, color: 'var(--green)' }}>المدفوعات وحساب الاستلام</h3>
      {d.payouts.length === 0 ? <p className="muted" style={{ fontSize: 13 }}>لم تُصرف مبالغ بعد. الحد الأدنى للصرف {riyal(d.terms?.min_payout_halalas)} ر.س.</p>
        : d.payouts.map((x: any, i: number) => <div key={i} style={{ fontSize: 13 }}>{String(x.paid_at).slice(0, 10)} · {riyal(x.amount_halalas)} ر.س · مرجع <span dir="ltr">{x.reference}</span></div>)}
      <p style={{ fontSize: 13 }}>الحساب الحالي: {p.bank_name ?? '—'} · <span dir="ltr">{p.iban_masked ?? '—'}</span> · {p.account_holder_name ?? '—'}</p>
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
        <input placeholder="اسم البنك" value={bank.bank} onChange={e => setBank({ ...bank, bank: e.target.value })} style={{ maxWidth: 160 }} />
        <input placeholder="الآيبان الجديد" dir="ltr" value={bank.iban} onChange={e => setBank({ ...bank, iban: normalizeIban(e.target.value).slice(0, 24) })} style={{ maxWidth: 230 }} />
        <input placeholder="اسم صاحب الحساب" value={bank.holder} onChange={e => setBank({ ...bank, holder: e.target.value })} style={{ maxWidth: 180 }} />
        <button className="btn ghost" disabled={!!bank.iban && !isValidSaIban(bank.iban)} onClick={saveBank}>حفظ</button>
      </div>
      {msg && <div className="note" style={{ marginTop: 8 }}>{msg}</div>}
    </div>

    {d.contract && <div className="card">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: 13 }}>الاتفاقية الموقّعة: {d.contract.title} · وقّعها {d.contract.signer} في {new Date(d.contract.accepted_at).toLocaleString('ar-SA')}</span>
        <button className="btn ghost" style={{ padding: '4px 10px' }} onClick={() => setShowContract(!showContract)}>{showContract ? 'إخفاء' : 'عرض'}</button>
      </div>
      {showContract && <pre style={{ whiteSpace: 'pre-wrap', fontFamily: 'inherit', fontSize: 13, marginTop: 10 }}>{d.contract.body_ar}</pre>}
    </div>}
  </>
}
