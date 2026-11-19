import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { Badge, BLOCKERS, ENTITY_TYPES, MISSING, PROFILE_STATUS, bankFromIban, isValidSaIban, isValidSaVat, normalizeIban } from '../../lib/finance'

type Profile = Record<string, any>

export default function SupplierPayments() {
  const [sup, setSup] = useState<{ id: string; name: string } | null>(null)
  const [info, setInfo] = useState<any>(null)
  const [f, setF] = useState<Profile>({ entity_type: '', legal_name: '', cr_number: '', account_holder_name: '', bank_name: '', iban: '', vat_registered: true, tax_number: '', vat_certificate_path: '' })
  const [cert, setCert] = useState<File | null>(null)
  const [pm, setPm] = useState({ link: '', cod: false, instructions: '' })
  const [msg, setMsg] = useState<string | null>(null); const [busy, setBusy] = useState(false)

  const load = async (id: string) => {
    const { data, error } = await supabase.rpc('my_payment_profile', { p_supplier: id })
    if (error) { setMsg(error.message); return }
    setInfo(data)
    const p = data?.profile
    if (p) setF((x: Profile) => ({ ...x, entity_type: p.entity_type ?? '', legal_name: p.legal_name ?? '', cr_number: p.cr_number ?? '', account_holder_name: p.account_holder_name ?? '',
      bank_name: p.bank_name ?? '', iban: p.iban ?? '', vat_registered: !!p.vat_registered, tax_number: p.tax_number ?? '', vat_certificate_path: p.vat_certificate_path ?? '' }))
    if (p) setPm({ link: p.payment_link ?? '', cod: !!p.accepts_cod, instructions: p.payment_instructions ?? '' })
  }
  useEffect(() => { (async () => {
    const { data } = await supabase.rpc('my_supplier_dashboard')
    const s = Array.isArray(data) ? data.find((x: any) => x.approval_status === 'approved') : null
    if (s) { setSup({ id: s.id, name: s.name }); await load(s.id) } else setMsg('لا توجد منشأة معتمدة مرتبطة بحسابك بعد.')
  })() }, [])

  const set = (k: string, v: unknown) => setF((x: Profile) => ({ ...x, [k]: v }))
  const ibanOk = !f.iban || isValidSaIban(f.iban)
  const detected = f.iban ? bankFromIban(f.iban) : null

  const save = async () => {
    if (!sup) return
    setBusy(true); setMsg(null)
    try {
      let certPath = f.vat_certificate_path
      if (f.vat_registered && cert) {
        const { data: { user } } = await supabase.auth.getUser()
        const ext = cert.name.split('.').pop() || 'pdf'
        const path = `${user!.id}/vat-certificate-${Date.now()}.${ext}`
        const up = await supabase.storage.from('seller-documents').upload(path, cert, { upsert: false })
        if (up.error) throw new Error('تعذّر رفع الشهادة: ' + up.error.message)
        certPath = path
      }
      const { data, error } = await supabase.rpc('supplier_save_payment_profile', { p_supplier: sup.id, p: { ...f, iban: normalizeIban(f.iban), vat_certificate_path: certPath } })
      if (error) throw new Error(error.message)
      setMsg(data?.change_request ? 'تم إرسال التعديل للمراجعة. تبقى بياناتك المعتمدة الحالية سارية حتى تعتمد الإدارة التغيير.'
        : data?.status === 'pending' ? 'اكتملت البيانات وأُرسلت للتحقق من الإدارة.' : 'تم الحفظ. أكمل الحقول الناقصة.')
      setCert(null); await load(sup.id)
    } catch (e: any) { setMsg(e.message) } finally { setBusy(false) }
  }

  const linkOk = !pm.link.trim() || /^https:\/\/\S{4,}$/.test(pm.link.trim())
  const savePm = async () => {
    if (!sup) return
    setBusy(true); setMsg(null)
    const { data, error } = await supabase.rpc('supplier_set_payment_methods', { p_supplier: sup.id, p_link: pm.link.trim() || null, p_cod: pm.cod, p_instructions: pm.instructions.trim() || null })
    setBusy(false)
    if (error) { setMsg('تعذّر الحفظ: ' + error.message); return }
    setMsg(data?.status === 'pending' ? 'تم الحفظ وإرسال طرق الدفع للتحقق من الإدارة. يتوقف استقبال الطلبات حتى الاعتماد.' : 'تم حفظ طرق استلام الدفع.')
    await load(sup.id)
  }

  const p = info?.profile
  const field = (label: string, node: any, hint?: string) => <div className="field"><label>{label}</label>{node}{hint && <p className="muted" style={{ fontSize: 12, marginTop: 3 }}>{hint}</p>}</div>

  return (
    <section style={{ padding: '32px 0', maxWidth: 680 }}>
      <Link to="/supplier" className="muted">→ لوحة المورد</Link>
      <h2 style={{ color: 'var(--green)' }}>إعدادات الدفع واستلام المستحقات</h2>
      <p className="muted" style={{ fontSize: 14 }}>يدفع العميل لك مباشرة عبر رابط الدفع الخاص بك أو نقداً عند الاستلام — لا تمر أموالك بحساب منصة رواء، وتُسدَّد عمولة المنصة شهرياً. لا يمكنك استقبال طلبات مدفوعة حتى تكتمل هذه البيانات ويتم التحقق منها.</p>
      {msg && <div className="note" style={{ margin: '10px 0' }}>{msg}</div>}
      {sup && <div className="card" style={{ marginBottom: 14 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <strong>{sup.name}</strong>
          <Badge s={p?.status ?? 'incomplete'} map={PROFILE_STATUS} />
        </div>
        {p?.status_reason && <p className="muted" style={{ fontSize: 13 }}>ملاحظة الإدارة: {p.status_reason}</p>}
        {info?.missing?.length > 0 && <p style={{ fontSize: 13, margin: '8px 0 0' }}>ناقص: {info.missing.map((m: string) => MISSING[m] ?? m).join('، ')}</p>}
        {info?.blockers?.length > 0
          ? <ul style={{ fontSize: 13, margin: '8px 0 0', paddingInlineStart: 18 }}>{info.blockers.map((b: string) => <li key={b}>{BLOCKERS[b] ?? b}</li>)}</ul>
          : info && <p style={{ fontSize: 13, color: 'var(--green)', margin: '8px 0 0' }}>✓ حسابك مفعّل لاستقبال الطلبات المدفوعة.</p>}
        {info?.pending_change && <div className="note" style={{ marginTop: 10 }}>لديك طلب تعديل ({info.pending_change.fields.map((x: string) => MISSING[x] ?? x).join('، ')}) بانتظار اعتماد الإدارة.</div>}
      </div>}

      {sup && <div className="card">
        <h3 style={{ marginTop: 0, fontSize: 15, color: 'var(--green)' }}>بيانات المنشأة والحساب البنكي</h3>
        {field('نوع المنشأة *', <select value={f.entity_type} onChange={e => set('entity_type', e.target.value)}><option value="">— اختر —</option>{Object.entries(ENTITY_TYPES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select>)}
        {field('اسم المنشأة التجاري *', <input value={f.legal_name} onChange={e => set('legal_name', e.target.value)} />)}
        {field('رقم السجل التجاري (10 أرقام) *', <input value={f.cr_number} inputMode="numeric" onChange={e => set('cr_number', e.target.value.replace(/\D/g, '').slice(0, 10))} />)}
        {field('اسم صاحب الحساب البنكي *', <input value={f.account_holder_name} onChange={e => set('account_holder_name', e.target.value)} />, 'يجب أن يطابق اسم المنشأة المسجلة.')}
        {field('رقم الآيبان السعودي *', <input dir="ltr" value={f.iban} onChange={e => set('iban', normalizeIban(e.target.value).slice(0, 24))} placeholder="SA0000000000000000000000" />,
          !f.iban ? undefined : ibanOk ? `✓ آيبان صحيح${detected ? ' — ' + detected : ''}` : '✗ الآيبان غير صحيح (تحقق من الأرقام)')}
        {field('اسم البنك *', <input value={f.bank_name} onChange={e => set('bank_name', e.target.value)} placeholder={detected ?? ''} />)}
        <label style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '8px 0' }}>
          <input type="checkbox" checked={!!f.vat_registered} onChange={e => set('vat_registered', e.target.checked)} /> منشأتي مسجلة في ضريبة القيمة المضافة
        </label>
        {f.vat_registered && <>
          {field('الرقم الضريبي (15 رقماً) *', <input inputMode="numeric" value={f.tax_number} onChange={e => set('tax_number', e.target.value.replace(/\D/g, '').slice(0, 15))} />,
            f.tax_number && !isValidSaVat(f.tax_number) ? 'الرقم الضريبي يبدأ وينتهي بالرقم 3' : 'تُضاف الضريبة على أسعار منتجاتك وتصدر فواتير المبيعات باسمك.')}
          {field('شهادة التسجيل الضريبي *', <input type="file" accept="application/pdf,image/jpeg,image/png" onChange={e => setCert(e.target.files?.[0] || null)} />,
            f.vat_certificate_path ? '✓ شهادة مرفوعة — ارفع ملفاً جديداً لاستبدالها' : undefined)}
        </>}
        <button className="btn" style={{ width: '100%' }} disabled={busy || !ibanOk} onClick={save}>{busy ? 'جارٍ الحفظ…' : 'حفظ البيانات ←'}</button>
      </div>}

      {sup && <div className="card" style={{ marginTop: 14 }}>
        <h3 style={{ marginTop: 0, fontSize: 15, color: 'var(--green)' }}>طرق استلام ثمن الطلبات من العملاء</h3>
        <p className="muted" style={{ fontSize: 13 }}>يدفع العميل لك مباشرة. فعّل طريقة واحدة على الأقل: رابط الدفع الخاص بمنشأتك (من بنكك أو أي مزوّد دفع تتعامل معه) و/أو الدفع عند الاستلام. أي تعديل على هذه الطرق بعد الاعتماد يُراجع من الإدارة قبل استئناف استقبال الطلبات.</p>
        {field('رابط الدفع الخاص بك', <input dir="ltr" value={pm.link} onChange={e => setPm({ ...pm, link: e.target.value })} placeholder="https://…" />,
          !pm.link ? 'اختياري إذا فعّلت الدفع عند الاستلام.' : linkOk ? '✓ رابط صالح' : '✗ يجب أن يبدأ الرابط بـ https://')}
        <label style={{ display: 'flex', gap: 8, alignItems: 'center', margin: '8px 0' }}>
          <input type="checkbox" checked={pm.cod} onChange={e => setPm({ ...pm, cod: e.target.checked })} /> أقبل الدفع نقداً عند الاستلام
        </label>
        {field('تعليمات الدفع للعميل (اختياري)', <textarea rows={2} maxLength={500} value={pm.instructions} onChange={e => setPm({ ...pm, instructions: e.target.value })} />)}
        <button className="btn" style={{ width: '100%' }} disabled={busy || !linkOk || (!pm.link.trim() && !pm.cod)} onClick={savePm}>{busy ? 'جارٍ الحفظ…' : 'حفظ طرق الدفع ←'}</button>
      </div>}
    </section>
  )
}
