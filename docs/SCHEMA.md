# مخطط قاعدة البيانات (public) — مُستخرَج من PostgREST OpenAPI

المشروع: zyfrdlqjmuapkvhrdihn · عدد الجداول/المناظر: 17

## admin_audit_logs  (7 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- actor_id: uuid
- action: text [NOT NULL]
- entity_type: text [NOT NULL]
- entity_id: text
- changed_fields: text[] [NOT NULL]
- created_at: timestamp with time zone [NOT NULL, default=now()]

## admin_profiles  (7 عمود)
- user_id: uuid [PK, NOT NULL]
- role: text [NOT NULL]
- status: text [NOT NULL, default=active]
- permissions: text[] [NOT NULL]
- created_at: timestamp with time zone [NOT NULL, default=now()]
- updated_at: timestamp with time zone [NOT NULL, default=now()]
- login_mode: text [NOT NULL, default=password_totp]

## checkout_services  (3 عمود)
- code: text [PK, NOT NULL]
- price_halalas: int32 [NOT NULL]
- active: boolean [NOT NULL, default=True]

## deliveries  (8 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- order_id: uuid [FK->orders.id, NOT NULL]
- courier_id: uuid [NOT NULL]
- reviewer_id: uuid [NOT NULL]
- status: text [NOT NULL, default=scheduled]
- recipient_confirmed_at: timestamp with time zone
- reviewed_at: timestamp with time zone
- created_at: timestamp with time zone [NOT NULL, default=now()]

## delivery_evidence  (5 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- delivery_id: uuid [FK->deliveries.id, NOT NULL]
- uploaded_by: uuid [NOT NULL]
- object_path: text [NOT NULL]
- created_at: timestamp with time zone [NOT NULL, default=now()]

## facility_needs  (9 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- manager_id: uuid [NOT NULL]
- facility_name: text [NOT NULL]
- city: text [NOT NULL]
- category: text [NOT NULL]
- description: text [NOT NULL]
- quantity: int32 [NOT NULL]
- status: text [NOT NULL, default=open]
- created_at: timestamp with time zone [NOT NULL, default=now()]

## loyalty_settings  (2 عمود)
- id: boolean [PK, NOT NULL, default=True]
- enabled: boolean [NOT NULL, default=True]

## order_items  (6 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- order_id: uuid [FK->orders.id, NOT NULL]
- product_id: uuid [FK->products.id, NOT NULL]
- product_name: text [NOT NULL]
- unit_price_halalas: int32 [NOT NULL]
- quantity: int32 [NOT NULL]

## orders  (23 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- customer_id: uuid [NOT NULL]
- request_id: uuid [NOT NULL]
- city: text [NOT NULL]
- address: text [NOT NULL]
- recipient_name: text [NOT NULL]
- phone: text [NOT NULL]
- subtotal_halalas: int64 [NOT NULL]
- delivery_halalas: int32
- status: text [NOT NULL, default=pending]
- created_at: timestamp with time zone [NOT NULL, default=now()]
- intent: text [NOT NULL, default=standard]
- beneficiary_name: text
- print_name: boolean [NOT NULL, default=False]
- print_phrase_key: text
- print_custom_phrase: text
- print_language: text
- customization_fee_halalas: int32 [NOT NULL, default=0]
- loyalty_discount_halalas: int64 [NOT NULL, default=0]
- loyalty_eligible: boolean [NOT NULL, default=False]
- total_halalas: int64
- payment_status: text [NOT NULL, default=unpaid]
- paid_at: timestamp with time zone

## products  (14 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- name: text [NOT NULL]
- description: text [NOT NULL, default=]
- category: text [NOT NULL]
- price_halalas: int32 [NOT NULL]
- stock: int32 [NOT NULL, default=0]
- unit: text [NOT NULL]
- cities: text[] [NOT NULL]
- active: boolean [NOT NULL, default=False]
- featured: boolean [NOT NULL, default=False]
- supplier_id: uuid [FK->suppliers.id]
- created_at: timestamp with time zone [NOT NULL, default=now()]
- inventory_version: int32 [NOT NULL, default=1]
- archived: boolean [NOT NULL, default=False]

## profiles  (5 عمود)
- id: uuid [PK, NOT NULL]
- full_name: text [NOT NULL]
- phone: text [NOT NULL]
- city: text [NOT NULL]
- created_at: timestamp with time zone [NOT NULL, default=now()]

## quote_requests  (8 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- customer_id: uuid [NOT NULL]
- organization_name: text [NOT NULL]
- contact_phone: text [NOT NULL]
- city: text [NOT NULL]
- details: text [NOT NULL]
- status: text [NOT NULL, default=pending]
- created_at: timestamp with time zone [NOT NULL, default=now()]

## seller_applications  (10 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- owner_id: uuid [NOT NULL]
- business_name: text [NOT NULL]
- commercial_registration: text [NOT NULL]
- phone: text [NOT NULL]
- city: text [NOT NULL]
- category: text [NOT NULL]
- document_path: text [NOT NULL]
- status: text [NOT NULL, default=pending]
- created_at: timestamp with time zone [NOT NULL, default=now()]

## shipments  (18 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- order_id: uuid [FK->orders.id, NOT NULL]
- supplier_id: uuid [FK->suppliers.id, NOT NULL]
- provider_order_id: text [NOT NULL]
- pickup_code: text [NOT NULL]
- package_weight: numeric [NOT NULL]
- package_count: int32 [NOT NULL]
- export_state: text [NOT NULL, default=draft]
- provider_status: text
- tracking_number: text
- carrier: text
- tracking_url: text
- last_event_at: timestamp with time zone
- last_synced_at: timestamp with time zone
- operation_id: uuid
- operation_kind: text
- operation_started_at: timestamp with time zone
- created_at: timestamp with time zone [NOT NULL, default=now()]

## subscription_requests  (7 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- customer_id: uuid [NOT NULL]
- frequency: text [NOT NULL]
- city: text [NOT NULL]
- details: text [NOT NULL]
- status: text [NOT NULL, default=requested]
- created_at: timestamp with time zone [NOT NULL, default=now()]

## supplier_contract_versions  (6 عمود)
- version_id: text [PK, NOT NULL]
- body_ar: text [NOT NULL]
- body_sha256: text [NOT NULL]
- published: boolean [NOT NULL, default=False]
- is_current: boolean [NOT NULL, default=False]
- published_at: timestamp with time zone

## suppliers  (6 عمود)
- id: uuid [PK, NOT NULL, default=gen_random_uuid()]
- owner_id: uuid [NOT NULL]
- name: text [NOT NULL]
- cities: text[] [NOT NULL]
- approval_status: text [NOT NULL, default=pending]
- created_at: timestamp with time zone [NOT NULL, default=now()]

