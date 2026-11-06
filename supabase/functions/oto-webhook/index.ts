import { createOtoWebhook } from "../_shared/oto.ts";
import { backend } from "../_shared/oto-handler.ts";
Deno.serve(
  createOtoWebhook(
    {
      orderStatus: Deno.env.get("OTO_ORDER_STATUS_WEBHOOK_SECRET"),
      shipmentError: Deno.env.get("OTO_SHIPMENT_ERROR_WEBHOOK_SECRET"),
    },
    async (event) => {
      const service = backend({
        url: Deno.env.get("SUPABASE_URL"),
        secretKey:
          Deno.env.get("RIWA_SUPABASE_SECRET_KEY") ??
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
      });
      await service.rpc("ingest_oto_event", {
        p_fingerprint: event.fingerprint,
        p_order_id: event.order_id,
        p_event_type: event.event_type,
        p_value: event.value,
        p_event_at: event.event_at,
      });
    },
  ),
);
