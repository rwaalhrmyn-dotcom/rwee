# علاقات قاعدة البيانات (ERD) — من المفاتيح الأجنبية الحيّة

```
orders ──1:N── order_items            (order_items.order_id → orders.id)
orders ──1:N── deliveries             (deliveries.order_id → orders.id)
deliveries ──1:N── delivery_evidence  (delivery_evidence.delivery_id → deliveries.id)
```
> المفاتيح الأجنبية الصريحة المستخرجة من البنية الحيّة (7 علاقات). بقية الروابط (مثل products.supplier_id، orders.customer_id)
> قد تكون منطقية عبر الدوال/RLS دون قيد FK صريح؛ تُأكَّد عند جلب المخطط الكامل بـ db dump.

## الكيانات الرئيسية
- **التجارة:** products · orders · order_items · checkout_services
- **الموردون:** suppliers · supplier_contract_versions · seller_applications
- **التوصيل والشحن:** deliveries · delivery_evidence · shipments
- **العملاء والولاء:** profiles · loyalty_settings
- **الإدارة:** admin_profiles · admin_audit_logs
- **الطلبات والاحتياجات:** facility_needs · quote_requests · subscription_requests
