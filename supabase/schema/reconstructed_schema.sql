-- مخطط مُعاد بناؤه من البنية الحيّة (PostgREST OpenAPI) لمشروع zyfrdlqjmuapkvhrdihn
-- يشمل: الأعمدة، الأنواع، NOT NULL، الافتراضيات، المفاتيح الأساسية والأجنبية.
-- لا يشمل: سياسات RLS، المشغّلات (triggers)، قيود CHECK، الفهارس، وأجسام الدوال — تُجلب بـ supabase db dump.
-- غير رسمي: إعادة بناء تقريبية للبنية، لا بديل عن db dump الرسمي.

CREATE TABLE IF NOT EXISTS public."admin_audit_logs" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "actor_id" uuid,
  "action" text NOT NULL,
  "entity_type" text NOT NULL,
  "entity_id" text,
  "changed_fields" text[] NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."admin_profiles" (
  "user_id" uuid NOT NULL,
  "role" text NOT NULL,
  "status" text NOT NULL DEFAULT 'active',
  "permissions" text[] NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "updated_at" timestamptz NOT NULL DEFAULT now(),
  "login_mode" text NOT NULL DEFAULT 'password_totp',
  PRIMARY KEY ("user_id")
);

CREATE TABLE IF NOT EXISTS public."checkout_services" (
  "code" text NOT NULL,
  "price_halalas" integer NOT NULL,
  "active" boolean NOT NULL DEFAULT true,
  PRIMARY KEY ("code")
);

CREATE TABLE IF NOT EXISTS public."deliveries" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "order_id" uuid NOT NULL,
  "courier_id" uuid NOT NULL,
  "reviewer_id" uuid NOT NULL,
  "status" text NOT NULL DEFAULT 'scheduled',
  "recipient_confirmed_at" timestamptz,
  "reviewed_at" timestamptz,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."delivery_evidence" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "delivery_id" uuid NOT NULL,
  "uploaded_by" uuid NOT NULL,
  "object_path" text NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."facility_needs" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "manager_id" uuid NOT NULL,
  "facility_name" text NOT NULL,
  "city" text NOT NULL,
  "category" text NOT NULL,
  "description" text NOT NULL,
  "quantity" integer NOT NULL,
  "status" text NOT NULL DEFAULT 'open',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."loyalty_settings" (
  "id" boolean NOT NULL DEFAULT true,
  "enabled" boolean NOT NULL DEFAULT true,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."order_items" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "order_id" uuid NOT NULL,
  "product_id" uuid NOT NULL,
  "product_name" text NOT NULL,
  "unit_price_halalas" integer NOT NULL,
  "quantity" integer NOT NULL,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."orders" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "customer_id" uuid NOT NULL,
  "request_id" uuid NOT NULL,
  "city" text NOT NULL,
  "address" text NOT NULL,
  "recipient_name" text NOT NULL,
  "phone" text NOT NULL,
  "subtotal_halalas" bigint NOT NULL,
  "delivery_halalas" integer,
  "status" text NOT NULL DEFAULT 'pending',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "intent" text NOT NULL DEFAULT 'standard',
  "beneficiary_name" text,
  "print_name" boolean NOT NULL DEFAULT false,
  "print_phrase_key" text,
  "print_custom_phrase" text,
  "print_language" text,
  "customization_fee_halalas" integer NOT NULL DEFAULT 0,
  "loyalty_discount_halalas" bigint NOT NULL DEFAULT 0,
  "loyalty_eligible" boolean NOT NULL DEFAULT false,
  "total_halalas" bigint,
  "payment_status" text NOT NULL DEFAULT 'unpaid',
  "paid_at" timestamptz,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."products" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "name" text NOT NULL,
  "description" text NOT NULL DEFAULT '',
  "category" text NOT NULL,
  "price_halalas" integer NOT NULL,
  "stock" integer NOT NULL DEFAULT 0,
  "unit" text NOT NULL,
  "cities" text[] NOT NULL,
  "active" boolean NOT NULL DEFAULT false,
  "featured" boolean NOT NULL DEFAULT false,
  "supplier_id" uuid,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  "inventory_version" integer NOT NULL DEFAULT 1,
  "archived" boolean NOT NULL DEFAULT false,
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."profiles" (
  "id" uuid NOT NULL,
  "full_name" text NOT NULL,
  "phone" text NOT NULL,
  "city" text NOT NULL,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."quote_requests" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "customer_id" uuid NOT NULL,
  "organization_name" text NOT NULL,
  "contact_phone" text NOT NULL,
  "city" text NOT NULL,
  "details" text NOT NULL,
  "status" text NOT NULL DEFAULT 'pending',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."seller_applications" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_id" uuid NOT NULL,
  "business_name" text NOT NULL,
  "commercial_registration" text NOT NULL,
  "phone" text NOT NULL,
  "city" text NOT NULL,
  "category" text NOT NULL,
  "document_path" text NOT NULL,
  "status" text NOT NULL DEFAULT 'pending',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."shipments" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "order_id" uuid NOT NULL,
  "supplier_id" uuid NOT NULL,
  "provider_order_id" text NOT NULL,
  "pickup_code" text NOT NULL,
  "package_weight" numeric NOT NULL,
  "package_count" integer NOT NULL,
  "export_state" text NOT NULL DEFAULT 'draft',
  "provider_status" text,
  "tracking_number" text,
  "carrier" text,
  "tracking_url" text,
  "last_event_at" timestamptz,
  "last_synced_at" timestamptz,
  "operation_id" uuid,
  "operation_kind" text,
  "operation_started_at" timestamptz,
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."subscription_requests" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "customer_id" uuid NOT NULL,
  "frequency" text NOT NULL,
  "city" text NOT NULL,
  "details" text NOT NULL,
  "status" text NOT NULL DEFAULT 'requested',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS public."supplier_contract_versions" (
  "version_id" text NOT NULL,
  "body_ar" text NOT NULL,
  "body_sha256" text NOT NULL,
  "published" boolean NOT NULL DEFAULT false,
  "is_current" boolean NOT NULL DEFAULT false,
  "published_at" timestamptz,
  PRIMARY KEY ("version_id")
);

CREATE TABLE IF NOT EXISTS public."suppliers" (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "owner_id" uuid NOT NULL,
  "name" text NOT NULL,
  "cities" text[] NOT NULL,
  "approval_status" text NOT NULL DEFAULT 'pending',
  "created_at" timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY ("id")
);

-- المفاتيح الأجنبية
ALTER TABLE public."deliveries" ADD CONSTRAINT "deliveries_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES public."orders" ("id");
ALTER TABLE public."delivery_evidence" ADD CONSTRAINT "delivery_evidence_delivery_id_fkey" FOREIGN KEY ("delivery_id") REFERENCES public."deliveries" ("id");
ALTER TABLE public."order_items" ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES public."orders" ("id");
ALTER TABLE public."order_items" ADD CONSTRAINT "order_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES public."products" ("id");
ALTER TABLE public."products" ADD CONSTRAINT "products_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES public."suppliers" ("id");
ALTER TABLE public."shipments" ADD CONSTRAINT "shipments_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES public."orders" ("id");
ALTER TABLE public."shipments" ADD CONSTRAINT "shipments_supplier_id_fkey" FOREIGN KEY ("supplier_id") REFERENCES public."suppliers" ("id");
