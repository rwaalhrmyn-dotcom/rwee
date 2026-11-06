import { createClient } from '@supabase/supabase-js'

// الواجهة الأمامية تستخدم المفتاح العام (publishable) — آمن للمتصفح، تماماً كالنسخة الأصلية.
// القيم تُقرأ من متغيرات البيئة، مع قيمة افتراضية عامة للمشروع الإنتاجي.
const url =
  import.meta.env.VITE_SUPABASE_URL ??
  'https://jtddvnmzoixsdhkvhdrl.supabase.co'
const publishableKey =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ??
  'sb_publishable_wmzdNw0TQ97J85tL4I-rEw_4NjhUQi6'

export const supabase = createClient(url, publishableKey, {
  auth: { persistSession: true, autoRefreshToken: true },
})

export const SUPABASE_URL = url
