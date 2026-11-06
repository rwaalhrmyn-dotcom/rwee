# رِواء الحرمين — rwaalhrmyn.store

سوق المياه والمصاحف ومستلزمات المساجد في مكة والمدينة وجدة والطائف، مع خدمات توصيل.

> **تنبيه مهم:** هذا المستودع يحتوي **النسخة المبنية (production build)** التي سُحبت من استضافة Hostinger،
> **وليس** الكود المصدري (TypeScript/React). الاستضافة لا تحوي إلا مجلد `dist` المُصغّر.
> الكود المصدري القابل للتعديل يعيش في `~/rwaa-site` على جهاز المالك أو في مستودع منفصل لم يُربط بعد.

## المكدّس التقني
- **الواجهة:** تطبيق صفحة واحدة React + Vite (عربي RTL، خط IBM Plex Sans Arabic).
- **الخلفية:** Supabase — المشروع `zyfrdlqjmuapkvhrdihn` (منطقة eu-north-1).
- **الشحن:** تكامل OTO عبر وظيفة Edge باسم `oto-operation`.
- **الاستضافة:** Hostinger (shared)، المستخدم `u381823366`، الدومين `rwaalhrmyn.store`.

## المحتوى
- `dist/` — ملفات الموقع كما هي منشورة على Hostinger (index.html, assets, hero.png, favicon, .htaccess).
- `BACKEND_CONTRACT.md` — الجداول والدوال (RPC) ووظائف Edge وseالتخزين التي يستدعيها الموقع (مستخرجة من الحزمة).
- `docs/AUDIT.md` — تقرير الفحص الكامل: الموجود والناقص.

## التشغيل محلياً (خدمة النسخة المبنية)
```bash
cd dist && python3 -m http.server 8080
```
ثم افتح http://localhost:8080 — سيتصل بـ Supabase الإنتاجي مباشرة.

## إعادة النشر على Hostinger
محتوى `dist/` يُرفع إلى `/home/u381823366/domains/rwaalhrmyn.store/public_html/`.


## الواجهة الأمامية (معاد بناؤها)
مصدر React/TS قابل للتعديل والبناء في `src/` — انظر `BUILD.md`. النسخة الأصلية المنشورة محفوظة في `reference/live-hostinger-build/`.
