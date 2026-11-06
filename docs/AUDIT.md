# تقرير فحص رِواء الحرمين — 2026-11-06

## المصدر الذي سُحب منه
Hostinger (shared) · المستخدم `u381823366` · 4 مواقع كلها نفس نسخة الإنتاج:
- `rwaalhrmyn.store` (الأساسي) + 3 نطاقات `*.hostingersite.com`.
- **لا قاعدة بيانات على الاستضافة** (0). **لا كود مصدري** — فقط مجلد `dist` المبني.
- `.htaccess` يحجب صراحةً `src/ supabase/ tests/ scripts/ node_modules/` وأرشيفات `site.zip/app.zip` — تأكيد أن المصدر لا يُنشر.

## الواجهة الخلفية (Supabase)
- المشروع الحيّ المستخدم فعلياً: `zyfrdlqjmuapkvhrdihn` (والمفتاح العام يخصّه). **خارج صلاحية تكامل MCP الحالي.**
- مشروع آخر في الحساب المربوط `jtddvnmzoixsdhkvhdrl` باسم "رواء الحرمين" لكنه **فارغ تماماً** (ليس الإنتاج).

## حالة التشغيل
- الموقع الحيّ: HTTP 200، React يُركّب، لا أخطاء console، المتجر يظهر. ✅ (لقطة: docs/live-home.png)

## الموجود / الناقص
| العنصر | الحالة |
|---|---|
| نسخة الإنتاج المبنية (dist) | ✅ مسحوبة ومحفوظة |
| عقد الخلفية (جداول/دوال/وظائف/تخزين) | ✅ موثّق من الحزمة |
| واجهة المتجر + بوابات العميل/المورد/الإدارة | ✅ موجودة (مبنية) |
| الكود المصدري (TS/React) | ❌ غير موجود على Hostinger — في ~/rwaa-site أو مستودع منفصل |
| ملفات supabase/migrations و functions (المصدر) | ❌ غير موجودة على Hostinger |
| مخطط قاعدة البيانات الفعلي + الترحيلات | ⏳ يتطلب صلاحية مشروع zyfrdlqjmuapkvhrdihn |
| مستودع GitHub | ⏳ GitHub غير مربوط بالجلسة |

## لم يُنفَّذ أي تعديل
لم تُكتب أو تُحذف أي بيانات على أي مشروع Supabase ولا على الاستضافة. قراءة فقط + سحب نسخة.

## مراجعة وإصلاح (نفس اليوم)
- قُلّم `dist/` ليطابق موقع الإنتاج `rwaalhrmyn.store` بالضبط: index.html + index-TW1Gmtf4.js + index-sRk8resP.css + browser-BEwlWy-4.js + hero.png + favicon.svg + .htaccess.
- نُقلت حزم النطاقات الفرعية الثلاثة (نسخ أقدم من نفس التطبيق) إلى `hostinger-variants/` للأرشفة.
- تحقّق محلي: الخدمة الثابتة تُركّب التطبيق (#root=40353 بايت، 0 أخطاء console) مطابقةً للإنتاج.
- ملاحظة: الروابط العميقة (/admin، /supplier…) تحتاج خادماً يعيد التوجيه لـ index.html؛ `.htaccess` يفعل ذلك على Apache/Hostinger.

## تحديث (حزمة المالك المرفوعة 2026-11-06)
- أُضيفت الشعارات الرسمية في `brand/`، وبيان المشروع في `supabase/PROJECT_MANIFEST.json`.
- تصحيح: وظائف Edge **أربع** (authentica-send-sms/email, oto-operation, oto-webhook) — كانت موثّقة واحدة فقط من الحزمة.
- أُضيفت أسماء الترحيلات الـ15 بإصداراتها كملفات هيكلية فارغة في supabase/migrations/.
- تأكيد: مصدر البوابات على **ChatGPT Sites** لا GitHub؛ لا يوجد مستودع كود مصدري متاح. الكود الكامل وSQL وStorage تحتاج وصول المالك.

## تحديث (تصدير ChatGPT المُتحقَّق 2026-11-06)
- ChatGPT أكّد رؤية المشروع الحيّ (15 ترحيلاً + 4 وظائف ACTIVE) لكنه **لم يستطع نقل الكود المصدري ولا الـ SQL** من واجهاته — مثل نتيجتنا تماماً.
- المُضاف المفيد: `.env.example` بأسماء متغيرات البيئة الحقيقية (AUTHENTICA_*, OTO_*, SUPABASE_*). بلا أي قيم/أسرار.
- **خلاصة قاطعة:** مصدر React/TS للبوابات الأربع والـ SQL الفعلي غير قابل للتصدير عبر ChatGPT ولا عبر تكاملاتي. الطريق الوحيد = وصول المالك عبر Supabase CLI.

## استخراج حيّ عبر المفتاح السرّي (2026-11-06)
تم استخراج البنية الحيّة من مشروع zyfrdlqjmuapkvhrdihn مباشرةً (قراءة فقط عبر PostgREST):
- **17 جدولاً** بكامل الأعمدة والأنواع وNOT NULL والافتراضيات والمفاتيح الأساسية/الأجنبية → `supabase/schema/reconstructed_schema.sql` + `docs/SCHEMA.md`.
- **30 دالة RPC** (أكثر من 25 المستخرجة سابقاً) → `docs/RPC_FUNCTIONS.md`.
- **3 حاويات تخزين** → `supabase/STORAGE_BUCKETS.md` (منها `rwaa-project-source` الخاصة، **فارغة حالياً**).
- بنية PostgREST الخام → `supabase/schema/postgrest_openapi.json`.

**لا يزال ناقصاً (يحتاج Management API/PAT أو db dump):**
- أجسام الترحيلات الـ15 الفعلية (جدول supabase_migrations غير مكشوف عبر REST).
- مصدر الوظائف الأربع (authentica-send-sms/email, oto-operation, oto-webhook).
- سياسات RLS، المشغّلات، قيود CHECK، الفهارس، وأجسام دوال RPC.

## دمج المصدر الخلفي الجزئي (تصدير ChatGPT 2026-11-06)
- ✅ **7 ترحيلات حقيقية بأجسامها** (SQL كامل): initial_commerce (19KB), suppliers_and_facility_needs, order_customization, separate_portal_access, customer_loyalty, required_receipt_after_payment, supplier_inventory_management.
- ✅ **مصدر الوظائف الأربع** (index.ts) + deno.json.
- ⚠️ **ناقص بعد:** 8 ترحيلات (ما زالت هياكل)، ومجلد `_shared/` للوظائف (تستورد منه، فلا تُنشر بدونه)، وكامل الواجهة الأمامية `src/`.

## دمج الملفات المشتركة للوظائف (تصدير 2026-11-06)
- ✅ أُضيف `supabase/functions/_shared/`: authentica.ts (7KB), oto-handler.ts (5KB), oto.ts (11.6KB).
- الآن الوظائف الأربع مكتملة التبعيات وقابلة للنشر عبر `supabase functions deploy`.
- ⚠️ يبقى ناقصاً: 8 ترحيلات، وكامل الواجهة الأمامية `src/`.
