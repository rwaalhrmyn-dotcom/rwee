# دليل تفعيل الدخول (Authentica) والدفع (Tap) — رِواء الحرمين

كل الكود جاهز في المستودع. ما يلي يُنفَّذ مرة واحدة من يملك وصول Supabase (المشروع `zyfrdlqjmuapkvhrdihn`).

## المتطلبات
- Supabase CLI، وتسجيل الدخول: `supabase login` ثم `supabase link --project-ref zyfrdlqjmuapkvhrdihn`
- مفتاح Authentica (تم التحقق أنه يعمل): `$2y$10$...` (يُفضّل تدويره)
- مفتاح Tap السرّي التجريبي: `sk_test_...` (من Tap Dashboard → goSell → API Credentials)

## 1) تطبيق ترحيل الدفع ونشر الوظائف
```bash
supabase db push
supabase functions deploy authentica-send-sms
supabase functions deploy authentica-send-email
supabase functions deploy tap-create-charge
supabase functions deploy tap-webhook --no-verify-jwt
```

## 2) ضبط الأسرار
```bash
supabase secrets set \
  AUTHENTICA_API_KEY='$2y$10$...' \
  AUTHENTICA_SMS_METHOD=sms \
  TAP_SECRET_KEY='sk_test_...' \
  SITE_URL='https://rwaalhrmyn.store'
```

## 3) تفعيل خطّافات الدخول (لوحة Supabase)
Authentication → Hooks:
- Send SMS hook (HTTPS) → `https://zyfrdlqjmuapkvhrdihn.supabase.co/functions/v1/authentica-send-sms`
- Send Email hook (HTTPS) → `https://zyfrdlqjmuapkvhrdihn.supabase.co/functions/v1/authentica-send-email`
- انسخ hook secret (`v1,whsec_...`) لكلٍّ وأضفه:
```bash
supabase secrets set AUTHENTICA_SMS_HOOK_SECRET='v1,whsec_...' AUTHENTICA_EMAIL_HOOK_SECRET='v1,whsec_...'
```
Authentication → Providers: فعّل Phone (و/أو Email).

## 4) إعداد webhook الدفع في Tap
Tap Dashboard → Webhooks → أضف:
`https://zyfrdlqjmuapkvhrdihn.supabase.co/functions/v1/tap-webhook`

## 5) اختبار
- الدخول: rwaalhrmyn.store/customer/login → أدخل جوالك → يصلك الرمز.
- الدفع: أضف منتجاً → السلة → إتمام الطلب → يحوّلك لصفحة دفع Tap (ببطاقة اختبار Tap) → بعد الدفع يعود لصفحة التأكيد ويُسجَّل الدفع تلقائياً.

## ملاحظات
- الواجهة تعمل الآن حتى قبل تفعيل الدفع: الطلب يُسجَّل ويظهر تأكيد "سيتواصل معك فريقنا".
- بعد تفعيل Tap، يتحوّل زر الإتمام تلقائياً لصفحة الدفع دون أي تعديل كود.
- دوّر مفتاح Authentica ومفتاح Supabase السرّي اللذين ظهرا سابقاً.
