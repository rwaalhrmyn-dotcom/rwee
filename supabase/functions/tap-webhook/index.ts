// Tap webhook: verifies a charge server-side and records the payment.
// Runs as service_role; never trusts the client.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  try {
    const tapKey = Deno.env.get("TAP_SECRET_KEY");
    const supaUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    if (!tapKey) return new Response("not configured", { status: 500 });

    const payload = await req.json().catch(() => ({}));
    const chargeId = String(payload?.id ?? "");
    if (!/^chg_/.test(chargeId)) return new Response("ignored", { status: 200 });

    // Re-fetch the charge from Tap (never trust the webhook body for status).
    const res = await fetch(`https://api.tap.company/v2/charges/${chargeId}`, {
      headers: { Authorization: `Bearer ${tapKey}` },
    });
    const charge = await res.json();
    const status = charge?.status;
    const orderId = charge?.reference?.order ?? charge?.metadata?.order_id;
    if (!orderId) return new Response("no order ref", { status: 200 });

    if (status === "CAPTURED") {
      const supa = createClient(supaUrl, serviceKey);
      const { error } = await supa.rpc("record_gateway_payment", {
        p_order_id: orderId, p_reference: chargeId, p_gateway: "tap",
      });
      if (error && !String(error.message).includes("already recorded")) {
        return new Response("record failed: " + error.message, { status: 500 });
      }
    }
    // Acknowledge all other statuses (INITIATED/FAILED/DECLINED) without recording.
    return new Response("ok", { status: 200 });
  } catch (e) {
    return new Response("err: " + String(e), { status: 500 });
  }
});
