// Creates a Tap charge for an order and returns the hosted payment URL.
// Called by the authenticated customer from checkout.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405, headers: cors });
  try {
    const tapKey = Deno.env.get("TAP_SECRET_KEY");
    const siteUrl = Deno.env.get("SITE_URL") ?? "https://rwaalhrmyn.store";
    const supaUrl = Deno.env.get("SUPABASE_URL")!;
    if (!tapKey) return json({ error: "payment not configured" }, 500);

    const authHeader = req.headers.get("Authorization") ?? "";
    const supa = createClient(supaUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user } } = await supa.auth.getUser();
    if (!user) return json({ error: "authentication required" }, 401);

    const body = await req.json();
    const orderId = String(body.order_id ?? "");
    if (!/^[0-9a-f-]{36}$/.test(orderId)) return json({ error: "invalid order" }, 400);

    // read the order (RLS: owner can read own order)
    const { data: order, error } = await supa
      .from("orders")
      .select("id,customer_id,subtotal_halalas,delivery_halalas,recipient_name,phone,status,payment_status")
      .eq("id", orderId).maybeSingle();
    if (error || !order) return json({ error: "order not found" }, 404);
    if (order.payment_status === "paid") return json({ error: "already paid" }, 409);

    const amount = ((order.subtotal_halalas ?? 0) + (order.delivery_halalas ?? 0)) / 100;
    if (amount <= 0) return json({ error: "invalid amount" }, 400);

    const charge = await fetch("https://api.tap.company/v2/charges", {
      method: "POST",
      headers: { Authorization: `Bearer ${tapKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        amount, currency: "SAR",
        customer: { first_name: order.recipient_name || "Customer", phone: phoneObj(order.phone) },
        source: { id: "src_all" }, // card (mada/Visa/MC) + Apple Pay
        threeDSecure: true, save_card: false,
        description: `Order ${orderId}`,
        reference: { order: orderId },
        order: { id: orderId },
        metadata: { order_id: orderId },
        redirect: { url: `${siteUrl}/payment/callback?order=${orderId}` },
        post: { url: `${supaUrl}/functions/v1/tap-webhook` },
      }),
    });
    const result = await charge.json();
    const url = result?.transaction?.url;
    if (!url) return json({ error: "charge failed", detail: result?.errors ?? result }, 502);
    return json({ url, charge_id: result.id });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function phoneObj(p: string) {
  const digits = (p || "").replace(/\D/g, "").replace(/^966/, "").replace(/^0/, "");
  return { country_code: "966", number: digits || "500000000" };
}
function json(o: unknown, status = 200) {
  return new Response(JSON.stringify(o), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
