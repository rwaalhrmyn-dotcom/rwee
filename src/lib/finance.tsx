import { supabase, SUPABASE_URL } from './supabase'

export const PROFILE_STATUS: Record<string, { label: string; color: string }> = {
  incomplete: { label: 'غير مكتمل', color: '#8a6d1d' },
  pending: { label: 'قيد التحقق', color: '#1f5fa8' },
  active: { label: 'مفعل', color: 'var(--green)' },
  suspended: { label: 'موقوف', color: '#b00020' },
}

export const INVOICE_STATUS: Record<string, { label: string; color: string }> = {
  draft: { label: 'مسودة', color: '#6a7a71' },
  issued: { label: 'صادرة', color: '#1f5fa8' },
  partially_paid: { label: 'مدفوعة جزئياً', color: '#8a6d1d' },
  paid: { label: 'مدفوعة', color: 'var(--green)' },
  overdue: { label: 'متأخرة', color: '#b00020' },
  cancelled: { label: 'ملغاة بتسوية نظامية', color: '#6a7a71' },
}

export const BLOCKERS: Record<string, string> = {
  not_approved: 'المنشأة غير معتمدة بعد',
  payment_profile_incomplete: 'إعدادات الدفع واستلام المستحقات غير مكتملة',
  payment_pending_review: 'وسيلة الدفع قيد التحقق من الإدارة',
  payment_suspended: 'وسيلة الدفع موقوفة',
  contract_not_accepted: 'يلزم قبول الإصدار الحالي من اتفاقية المورد',
  orders_suspended: 'استقبال الطلبات الجديدة معلّق (تأخر سداد)',
}

export const MISSING: Record<string, string> = {
  entity_type: 'نوع المنشأة', legal_name: 'الاسم التجاري', cr_number: 'رقم السجل التجاري', account_holder_name: 'اسم صاحب الحساب',
  bank_name: 'اسم البنك', iban: 'آيبان سعودي صحيح', vat_certificate: 'الرقم الضريبي وشهادة التسجيل', gateway: 'ربط بوابة الدفع', gateway_invalid: 'مفتاح البوابة مرفوض',
}

export const ENTITY_TYPES: Record<string, string> = { factory: 'مصنع', distributor: 'موزع', trader: 'تاجر' }

export const riyal = (halalas: number | null | undefined) => ((Number(halalas || 0)) / 100).toFixed(2)
export const toHalalas = (v: string) => Math.round(Number(String(v).replace(/[^\d.]/g, '')) * 100)
export const pct = (bp: number | null | undefined) => `${(Number(bp || 0) / 100).toFixed(Number(bp || 0) % 100 ? 2 : 0)}%`

export const normalizeIban = (v: string) => v.toUpperCase().replace(/[^A-Z0-9]/g, '')
export function isValidSaIban(v: string): boolean {
  const s = normalizeIban(v)
  if (!/^SA\d{22}$/.test(s)) return false
  const r = s.slice(4) + '2810' + s.slice(2, 4)
  let m = 0
  for (const ch of r) m = (m * 10 + Number(ch)) % 97
  return m === 1
}
const BANKS: Record<string, string> = { '05': 'مصرف الإنماء', '10': 'البنك الأهلي السعودي', '15': 'بنك البلاد', '20': 'بنك الرياض', '30': 'البنك العربي الوطني',
  '40': 'البنك الأهلي السعودي', '45': 'البنك السعودي الأول', '50': 'البنك السعودي الأول', '55': 'البنك السعودي الفرنسي', '60': 'بنك الجزيرة',
  '65': 'البنك السعودي للاستثمار', '80': 'مصرف الراجحي' }
export const bankFromIban = (v: string) => BANKS[normalizeIban(v).slice(4, 6)] ?? null
export const isValidSaVat = (v: string) => /^3\d{13}3$/.test(v)

export async function callFn(name: string, body: unknown): Promise<{ ok: boolean; data: any }> {
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return { ok: false, data: { error: 'يلزم تسجيل الدخول' } }
  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${session.access_token}` }, body: JSON.stringify(body),
    })
    const data = await res.json().catch(() => ({}))
    return { ok: res.ok, data }
  } catch (e) { return { ok: false, data: { error: String(e) } } }
}

export function Badge({ s, map }: { s: string; map: Record<string, { label: string; color: string }> }) {
  const v = map[s] ?? { label: s, color: '#6a7a71' }
  return <span className="badge" style={{ background: v.color, color: '#fff' }}>{v.label}</span>
}
