# عقد الواجهة الخلفية (Supabase) — مُستخرج من حزمة الإنتاج

المشروع: `zyfrdlqjmuapkvhrdihn.supabase.co` · المفتاح العام (publishable) مضمّن في الواجهة.

> استُخرجت الأسماء التالية من ملف الحزمة `dist/assets/index-TW1Gmtf4.js`. تمثّل ما **يستدعيه الموقع**،
> وهي مرجع لإعادة بناء المخطط إن لزم. (المخطط الفعلي موجود في مشروع Supabase نفسه، وهو حالياً خارج صلاحية هذا التكامل.)

## الجداول (`.from(...)`)
- `profiles`
- `products`
- `suppliers`
- `orders`
- `deliveries`
- `shipments`
- `checkout_services`
- `facility_needs`
- `loyalty_settings`
- `quote_requests`
- `seller_applications`
- `subscription_requests`

## الدوال المخزّنة (`.rpc(...)`)
accept_supplier_contract · admin_audit_page · admin_supplier_contract_acceptances ·
confirm_delivery_receipt · my_admin_session · my_admin_sessions · my_loyalty_wallet ·
my_portal_access · my_supplier_accounts · my_supplier_contract · place_order ·
prepare_oto_shipment · record_verified_payment · review_delivery · revoke_my_admin_session ·
set_loyalty_enabled · set_printing_service_price · shipping_candidates ·
submit_delivery_evidence · supplier_adjust_stock · supplier_archive_product ·
supplier_import_products · supplier_order_summaries · supplier_products · supplier_save_product

## وظائف Edge (`functions.invoke`)
- `oto-operation` — عمليات شحن OTO (body: `{shipment_id, action}`).

## حاويات التخزين (`storage.from(...)`)
- `delivery-evidence` — أدلّة التسليم.
- `seller-documents` — وثائق البائعين.

## المسارات (Routing) — أربع واجهات
- **المتجر/العميل:** `/` `/products` `/bundles` `/suppliers` `/cart` `/checkout` `/orders` `/account` `/needs` `/loyalty` `/gifts` `/sadaqah` `/business` `/delivery` `/shipping` `/privacy` `/terms`
- **بوابة العميل:** `/customer` `/customer/login` `/customer/register` `/customer/account` `/customer/cart` `/customer/orders` `/customer/delivery` `/customer/needs` `/customer/shipping` `/customer/auth/callback`
- **بوابة المورد/البائع:** `/supplier` `/seller` `/supplier/login` `/supplier/register` `/supplier/application` `/supplier/contract` `/supplier/inventory` `/supplier/orders` `/supplier/shipping` `/supplier/auth/callback`
- **لوحة الإدارة:** `/admin` `/admin/login` `/admin/contract` `/admin/security` `/admin/shipping` `/admin/auth/callback`

---

## تحديث موثّق (من حزمة المالك PROJECT_MANIFEST.json)

**اسم المشروع:** `riwa-alharamain` · **المرجع:** `zyfrdlqjmuapkvhrdihn`

**البوابات (مستضافة على ChatGPT Sites):**
- المتجر: https://riwa-alharamain.mshykhynasr070.chatgpt.site/
- المورد: https://riwa-supplier.mshykhynasr070.chatgpt.site/
- العميل: https://riwa-customer.mshykhynasr070.chatgpt.site/
- الإدارة: https://riwa-admin.mshykhynasr070.chatgpt.site/
- (نسخة إضافية منشورة على Hostinger: https://rwaalhrmyn.store/)

**وظائف Edge (4 — جميعها ACTIVE):**
- `authentica-send-sms` — إرسال SMS عبر Authentica.
- `authentica-send-email` — إرسال بريد عبر Authentica.
- `oto-operation` — عمليات شحن OTO.
- `oto-webhook` — استقبال إشعارات OTO.

**الترحيلات (15 — بالإصدارات الفعلية):**
20261031045601 initial_commerce · 20261031045607 suppliers_and_facility_needs ·
20261031045634 order_customization · 20261031050045 separate_portal_access ·
20261031050528 customer_loyalty · 20261031050538 required_receipt_after_payment ·
20261031050707 supplier_inventory_management · 20261031050713 western_region_cities ·
20261031050728 verified_account_sessions · 20261031050757 verified_phone_authentica ·
20261031050806 oto_shipments_and_verified_events · 20261031052209 streamline_read_policies_and_shipment_events ·
20261104202728 supplier_electronic_contracts · 20261104205854 admin_security_foundation ·
20261105144138 admin_password_login_policy

> ملفات `supabase/migrations/*.sql` موجودة بأسمائها الصحيحة لكن **فارغة من الـ SQL الفعلي** — تُملأ بـ `supabase db dump`.
