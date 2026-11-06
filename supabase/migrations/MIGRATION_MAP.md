# خريطة الترحيلات → الكائنات (استدلالية من الأسماء)

> **استدلالي** من أسماء الترحيلات مقابل الجداول الحيّة — لتسهيل الفهم فقط. المحتوى الفعلي يُجلب بـ db dump.

| الإصدار | الاسم | الكائنات المرجّحة |
|---|---|---|
| 20261031045601 | initial_commerce | products, orders, order_items, checkout_services, profiles |
| 20261031045607 | suppliers_and_facility_needs | suppliers, facility_needs, seller_applications |
| 20261031045634 | order_customization | order_items (تخصيص), quote_requests |
| 20261031050045 | separate_portal_access | my_portal_access(RPC), صلاحيات البوابات |
| 20261031050528 | customer_loyalty | loyalty_settings, my_loyalty_wallet(RPC) |
| 20261031050538 | required_receipt_after_payment | record_verified_payment(RPC), حقول الإيصال |
| 20261031050707 | supplier_inventory_management | supplier_products/adjust_stock/save/import (RPC) |
| 20261031050713 | western_region_cities | بيانات مدن المنطقة الغربية |
| 20261031050728 | verified_account_sessions | my_admin_sessions/revoke (RPC), جلسات موثّقة |
| 20261031050757 | verified_phone_authentica | تكامل authentica (SMS), تحقق الهاتف |
| 20261031050806 | oto_shipments_and_verified_events | shipments, prepare_oto_shipment/ingest_oto_event (RPC) |
| 20261031052209 | streamline_read_policies_and_shipment_events | سياسات RLS للقراءة, أحداث الشحن |
| 20261104202728 | supplier_electronic_contracts | supplier_contract_versions, accept_supplier_contract (RPC) |
| 20261104205854 | admin_security_foundation | admin_profiles, admin_audit_logs, set_admin_staff (RPC) |
| 20261105144138 | admin_password_login_policy | admin_profiles.login_mode, سياسة الدخول |
