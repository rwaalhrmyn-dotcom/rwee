import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../../lib/supabase'
import { Badge, BLOCKERS, ENTITY_TYPES, MISSING, PROFILE_STATUS, bankFromIban, callFn, isValidSaIban, isValidSaVat, normalizeIban } from '../../lib/finance'

type Profile = Record<string, any>

export default function SupplierPayments() {
  const [sup, setSup] = useState<{ id: string; name: string } | null>(null)
  const [info, setInfo] = useState<any>(null)
  const [f, setF] = useState<Profile>({ entity_type: '', legal_name: '', cr_number: '', account_holder_name: '', bank_name: '', iban: '', vat_registered: true, tax_number: '', vat_certificate_path: '' })
  const [cert, setCert] = useState<File | null>(null)
  const [key, setKey] = useState(''); const [merchant, setMerchant] = useState('')
  const [msg, setMsg] = useState<string | null>(null); const [busy, setBusy] = useState(false)

  const load = async (id: string) => {
    const { data, error } = await supabase.rpc('my_payment_profile', { p_supplier: id })
    if (error) { setMsg(error.message); return }
    setInfo(data)
    const p = data?.profile
    if (p) setF((x: Profile) => ({ ...x, entity_type: p.entity_type ?? '', legal_name: p.legal_name ?? '', cr_number: p.cr_number ?? '', account_holder_name: p.account_holder_name ?? '',
      bank_name: p.bank_name ?? '', iban: p.iban ?? '', vat_registered: !!p.vat_registered, tax_number: p.tax_number ?? '', vat_certificate_path: p.vat_certificate_path ?? '' }))
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

  const connect = async () => {
    if (!sup) return
    setBusy(true); setMsg(null)
    const { ok, data } = await callFn('supplier-gateway', { supplier_id: sup.id, provider: 'tap', secret_key: key.trim(), merchant_id: merchant.trim() || null })
    setKey('')
    setBusy(false)
    if (!ok) { setMsg('تعذّر ربط البوابة: ' + (data?.error ?? 'خطأ')); return }
    setMsg(data?.change_request ? 'تم التحقق من المفتاح وإرسال تغيير البوابة لمراجعة الإدارة.' : `تم التحقق من المفتاح لدى Tap (${data.mode === 'live' ? 'حساب حي' : 'وضع تجريبي'}) وحفظه مشفّراً.`)
    await load(sup.id)
  }

  const p = info?.profile
  const field = (label: string, node: any, hint?: string) => <div className="field"><label>{label}</label>{node}{hint && <p className="muted" style={{ fontSize: 12, marginTop: 3 }}>{hint}</p>}</div>

  return (
    <section style={{ padding: '32px 0', maxWidth: 680 }}>
      <Link to="/supplier" className="muted">→ لوحة المورد</Link>
      <h2 style={{ color: 'var(--green)' }}>إعدادات الدفع واستلام المستحقات</h2>
      <p className="muted" style={{ fontSize: 14 }}>يدفع العميل مرة واحدة، ويُحصَّل ثمن طلبك عبر بوابة الدفع الخاصة بك مباشرة إلى حسابك — لا تمر أموالك بحساب منصة رواء. لا يمكنك استقبال طلبات مدفوعة حتى تكتمل هذه البيانات ويتم التحقق منها.</p>
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
        {info?.pending_change && <div className="note" style={{ marginTop: 10 }}>لديك طلب تعديل ({info.pending_change.fields.map((x: string) => MISSING[x] ?? x).join('، ')}{info.pending_change.gateway ? '، بوابة الدفع' : ''}) بانتظار اعتماد الإدارة.</div>}
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
        <h3 style={{ marginTop: 0, fontSize: 15, color: 'var(--green)' }}>بوابة الدفع الإلكترونية الخاصة بك</h3>
        <p className="muted" style={{ fontSize: 13 }}>البوابة المدعومة حالياً: <strong>Tap Payments</strong>. أدخل المفتاح السري لحساب منشأتك في Tap؛ نتحقق منه مع Tap ونحفظه مشفّراً على الخادم فقط، ولا يُعرض مرة أخرى.</p>
        {p?.gateway_provider && <p style={{ fontSize: 13 }}>المرتبط حالياً: Tap · {p.gateway_mode === 'live' ? 'حساب حي' : 'وضع تجريبي'} · مفتاح ينتهي بـ <code dir="ltr">…{p.gateway_key_hint}</code> · التحقق: {p.gateway_check_status === 'valid' ? '✓ ناجح' : p.gateway_check_status}</p>}
        {field('المفتاح السري (Secret Key)', <input dir="ltr" type="password" autoComplete="off" value={key} onChange={e => setKey(e.target.value)} placeholder="sk_live_… أو sk_test_…" />)}
        {field('معرّف التاجر لدى Tap (اختياري)', <input dir="ltr" value={merchant} onChange={e => setMerchant(e.target.value)} />)}
        <button className="btn" style={{ width: '100%' }} disabled={busy || !/^sk_(live|test)_/.test(key.trim())} onClick={connect}>{busy ? 'جارٍ التحقق…' : 'ربط البوابة والتحقق ←'}</button>
      </div>}
    </section>
  )
}
