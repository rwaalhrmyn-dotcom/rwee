import { supabase } from './supabase'

// Referral links: https://rwaalhrmyn.store/?ref=CODE (customers) or /supplier/register?ref=CODE (suppliers).
// The code is kept on this device for 30 days; the server re-checks every rule (status, self-referral…).
const KEY = 'rawaa_ref'
const DAYS = 30

export function captureReferral(search: string) {
  const code = new URLSearchParams(search).get('ref')?.trim().toUpperCase()
  if (!code || !/^[A-Z0-9]{6,12}$/.test(code)) return
  try { localStorage.setItem(KEY, JSON.stringify({ code, at: Date.now() })) } catch { /* storage blocked */ }
  supabase.rpc('track_affiliate_click', { p_code: code }).then(() => {}, () => {})
}

export function getReferral(): string | null {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) || 'null')
    if (v?.code && Date.now() - v.at < DAYS * 86400000) return v.code
  } catch { /* ignore */ }
  return null
}

export const AFF_STATUS: Record<string, { label: string; color: string }> = {
  pending: { label: 'بانتظار الاعتماد', color: '#1f5fa8' },
  trial: { label: 'فترة التجربة', color: '#8a6d1d' },
  trial_ended: { label: 'انتهت التجربة — بانتظار قرار الإدارة', color: '#b00020' },
  active: { label: 'مستمر (فعّال)', color: 'var(--green)' },
  suspended: { label: 'موقوف', color: '#b00020' },
  terminated: { label: 'منتهٍ', color: '#6a7a71' },
  rejected: { label: 'مرفوض', color: '#6a7a71' },
}
export const EARN_STATE: Record<string, string> = {
  pending: 'بانتظار اكتمال الطلب', awaiting_collection: 'بانتظار تحصيل رواء لعمولتها', payable: 'مستحقة للصرف', void: 'ملغاة',
}
export const SIDE: Record<string, string> = { sales: 'مبيعات عبر رابطك', supplier: 'مورد جذبته' }
