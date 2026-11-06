# tap-webhook
يستقبل إشعار Tap، يتحقق من الدفعة عبر GET /v2/charges/{id}، ويسجّل الدفع service-role.
الأسرار: TAP_SECRET_KEY. ينشر بـ: supabase functions deploy tap-webhook --no-verify-jwt
