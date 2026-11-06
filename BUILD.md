# بناء ونشر رِواء الحرمين (الواجهة الأمامية المعاد بناؤها)

مشروع Vite + React + TypeScript، يتصل بالواجهة الخلفية الحيّة على Supabase (zyfrdlqjmuapkvhrdihn).

## تطوير محلي
```bash
npm install
npm run dev        # http://localhost:5173
```

## بناء الإنتاج
```bash
npm run build      # يُخرج إلى dist/ (غير متتبّع في git — artifact)
npm run preview
```

## متغيرات البيئة (اختيارية — لها قيم افتراضية عامة للإنتاج)
```
VITE_SUPABASE_URL=https://zyfrdlqjmuapkvhrdihn.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

## النشر على Hostinger
محتوى `dist/` (ومعه public/.htaccess لإعادة توجيه SPA) يُرفع إلى:
`/home/u381823366/domains/rwaalhrmyn.store/public_html/`

## الحالة
- ✅ البوابات: المتجر، المنتجات، الموردون، السلة، دخول العميل/المورد/الإدارة.
- بُنيت بناءً على: المخطط الحيّ (18 جدولاً، 30 RPC)، تدفقات المصادقة الحقيقية، وهوية التصميم الأصلية.
- النسخة الأصلية المنشورة محفوظة في `reference/live-hostinger-build/`.
- ⚠️ إعادة بناء تدريجية: الأساس والتدفقات الرئيسية جاهزة؛ تُستكمل صفحات التسجيل/الطلبات/المخزون/العقود تباعاً.
