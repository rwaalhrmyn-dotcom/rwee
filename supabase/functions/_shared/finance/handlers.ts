// Supplier-direct payment handlers. Pure functions over injected dependencies so the same
// code runs in Supabase Edge Functions (Deno) and in unit tests (Node).
import { hmacSha256Hex, openSecret, sealSecret, timingSafeEqual } from "./crypto.ts";
import { chargeHashMessage, createCharge, createRefund, type Fetch, getCharge, getRefund, keyHint, keyMode, refundStatus, toHalalas, verifyKey } from "./tap.ts";

export interface Deps {
  env: { GATEWAY_SECRETS_KEY: string; SITE_URL: string; SUPABASE_URL: string; CRON_SECRET?: string };
  fetch: Fetch;
  getUserId(authHeader: string): Promise<string | null>;
  userRpc(authHeader: string, fn: string, args: Record<string, unknown>): Promise<{ data: any; error: any }>;
  serviceRpc(fn: string, args: Record<string, unknown>): Promise<{ data: any; error: any }>;
  log(msg: string, extra?: unknown): void;
}
export interface Result { status: number; body: Record<string, unknown> }

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ok = (body: Record<string, unknown>, status = 200): Result => ({ status, body });
const fail = (status: number, error: string, extra: Record<string, unknown> = {}): Result => ({ status, body: { error, ...extra } });
const dbMessage = (e: any) => String(e?.message ?? e ?? "error").slice(0, 300);

// ---------------------------------------------------------------- supplier connects its own gateway
export async function connectGateway(d: Deps, auth: string, body: any): Promise<Result> {
  const uid = await d.getUserId(auth);
  if (!uid) return fail(401, "authentication required");
  const supplierId = String(body?.supplier_id ?? "");
  const secret = String(body?.secret_key ?? "").trim();
  const merchantId = body?.merchant_id ? String(body.merchant_id).trim().slice(0, 120) : null;
  if (!UUID.test(supplierId)) return fail(400, "invalid supplier");
  if ((body?.provider ?? "tap") !== "tap") return fail(400, "unsupported payment gateway");
  const mode = keyMode(secret);
  if (!mode) return fail(400, "invalid Tap secret key format (sk_test_... / sk_live_...)");
  const mine = await d.userRpc(auth, "my_supplier_ids", {});
  if (mine.error) return fail(403, dbMessage(mine.error));
  if (!(mine.data ?? []).map(String).includes(supplierId)) return fail(403, "not your supplier account");
  const check = await verifyKey(d.fetch, secret);
  if (check === "invalid") return fail(400, "Tap rejected this key; check it in your Tap dashboard");
  if (check === "unreachable") return fail(503, "Tap could not be reached to verify the key; try again shortly");
  const sealed = await sealSecret(secret, d.env.GATEWAY_SECRETS_KEY, supplierId);
  const r = await d.serviceRpc("svc_store_gateway_credentials", {
    p_supplier: supplierId, p_user: uid, p_provider: "tap", p_mode: mode, p_hint: keyHint(secret), p_merchant: merchantId,
    p_check_status: check, p_ciphertext: sealed.ciphertext, p_iv: sealed.iv,
  });
  if (r.error) return fail(400, dbMessage(r.error));
  d.log("gateway connected", { supplierId, mode });
  return ok({ ...(r.data ?? {}), mode, key_hint: keyHint(secret) });
}

// ---------------------------------------------------------------- customer pays the supplier directly
export async function createCheckout(d: Deps, auth: string, body: any): Promise<Result> {
  const uid = await d.getUserId(auth);
  if (!uid) return fail(401, "authentication required");
  const orderId = String(body?.order_id ?? "");
  if (!UUID.test(orderId)) return fail(400, "invalid order");
  const ctx = await d.serviceRpc("svc_charge_context", { p_order: orderId, p_user: uid });
  if (ctx.error) return fail(409, dbMessage(ctx.error));
  const c = ctx.data;
  let secret: string;
  try { secret = await openSecret(c.ciphertext, c.iv, d.env.GATEWAY_SECRETS_KEY, c.supplier_id); }
  catch { return fail(500, "supplier gateway credentials unavailable"); }
  let charge;
  try {
    charge = await createCharge(d.fetch, secret, {
      amountHalalas: Number(c.amount_halalas), orderId, supplierId: c.supplier_id, customerName: c.recipient_name, phone: c.phone,
      merchantId: c.merchant_id, description: `Rawaa order ${orderId.slice(0, 8)} — ${c.supplier_name}`,
      redirectUrl: `${d.env.SITE_URL}/payment/callback?order=${orderId}`, webhookUrl: `${d.env.SUPABASE_URL}/functions/v1/supplier-payment-webhook`,
    });
  } catch (e) { d.log("charge failed", { orderId, e: String(e) }); return fail(502, "payment page could not be created"); }
  const rec = await d.serviceRpc("svc_record_charge_initiated", {
    p_order: orderId, p_provider: "tap", p_charge_id: charge.id, p_amount: Number(c.amount_halalas), p_mode: c.mode, p_user: uid,
  });
  if (rec.error) d.log("record initiated failed", { orderId, e: dbMessage(rec.error) });
  return ok({ url: charge.url, charge_id: charge.id, supplier: c.supplier_name, amount_halalas: c.amount_halalas });
}

// ---------------------------------------------------------------- gateway webhook (never trusts the payload)
export async function processWebhook(d: Deps, headers: Headers, payload: any): Promise<Result> {
  const id = String(payload?.id ?? "");
  const isCharge = /^chg_[A-Za-z0-9_]+$/.test(id);
  const isRefund = /^re_[A-Za-z0-9_]+$/.test(id);
  if (!isCharge && !isRefund) return ok({ ignored: "unsupported event" });
  const orderId = String(isCharge ? (payload?.reference?.order ?? payload?.metadata?.order_id ?? "")
                                  : (payload?.reference?.merchant ?? payload?.metadata?.order_id ?? ""));
  if (!UUID.test(orderId)) return ok({ ignored: "no order reference" });
  const sec = await d.serviceRpc("svc_order_gateway_secret", { p_order: orderId });
  if (sec.error) return fail(500, dbMessage(sec.error));
  if (!sec.data) return ok({ ignored: "unknown order" });
  let secret: string;
  try { secret = await openSecret(sec.data.ciphertext, sec.data.iv, d.env.GATEWAY_SECRETS_KEY, sec.data.supplier_id); }
  catch { return fail(500, "credentials unavailable"); }

  if (isCharge) {
    const ch = await getCharge(d.fetch, secret, id);   // authoritative: fetched with the supplier's own key
    if (!ch) return ok({ ignored: "charge not found on supplier account" });
    const chOrder = String(ch?.reference?.order ?? ch?.metadata?.order_id ?? "");
    if (chOrder !== orderId) return ok({ ignored: "order reference mismatch" });
    const sig = headers.get("hashstring");
    if (sig) {
      const expect = await hmacSha256Hex(secret, chargeHashMessage(ch));
      if (!timingSafeEqual(expect, sig)) d.log("hashstring mismatch (state taken from API re-fetch)", { id });
    }
    const r = await d.serviceRpc("svc_process_charge", {
      p_provider: "tap", p_charge_id: String(ch.id), p_order: orderId, p_provider_status: String(ch.status ?? ""),
      p_amount_halalas: toHalalas(ch.amount ?? 0), p_currency: String(ch.currency ?? ""), p_mode: keyMode(secret),
    });
    if (r.error) return fail(500, dbMessage(r.error));
    return ok({ outcome: r.data });
  }
  const rf = await getRefund(d.fetch, secret, id);
  if (!rf) return ok({ ignored: "refund not found on supplier account" });
  const r = await d.serviceRpc("svc_record_refund", {
    p_order: orderId, p_refund_id: String(rf.id), p_charge_id: String(rf.charge_id ?? sec.data.charge_id ?? ""), p_amount: toHalalas(rf.amount ?? 0),
    p_status: refundStatus(String(rf.status ?? "")), p_reason: String(rf.reason ?? "استرجاع"), p_requested_by: null,
  });
  if (r.error) return fail(500, dbMessage(r.error));
  return ok({ refund: (r.data as any)?.status ?? "recorded" });
}

// ---------------------------------------------------------------- operator-initiated refund
export async function refundOrder(d: Deps, auth: string, body: any): Promise<Result> {
  const uid = await d.getUserId(auth);
  if (!uid) return fail(401, "authentication required");
  const op = await d.userRpc(auth, "am_i_finance_operator", {});
  if (op.error || op.data !== true) return fail(403, "operators only");
  const orderId = String(body?.order_id ?? "");
  const amount = Number(body?.amount_halalas);
  const reason = String(body?.reason ?? "").trim();
  if (!UUID.test(orderId) || !Number.isInteger(amount) || amount <= 0 || reason.length < 3 || reason.length > 500) return fail(400, "invalid refund request");
  const sec = await d.serviceRpc("svc_order_gateway_secret", { p_order: orderId });
  if (sec.error || !sec.data) return fail(409, "order has no supplier gateway");
  if (!sec.data.charge_id) return fail(409, "order has no captured payment");
  const refundable = Number(sec.data.payable_halalas ?? 0) - Number(sec.data.refunded_halalas ?? 0);
  if (amount > refundable) return fail(400, `refund exceeds refundable amount (${refundable})`);
  let secret: string;
  try { secret = await openSecret(sec.data.ciphertext, sec.data.iv, d.env.GATEWAY_SECRETS_KEY, sec.data.supplier_id); }
  catch { return fail(500, "credentials unavailable"); }
  let rf;
  try { rf = await createRefund(d.fetch, secret, sec.data.charge_id, amount, reason, orderId, `${d.env.SUPABASE_URL}/functions/v1/supplier-payment-webhook`); }
  catch (e) { d.log("refund failed", { orderId, e: String(e) }); return fail(502, "the gateway rejected the refund"); }
  const r = await d.serviceRpc("svc_record_refund", {
    p_order: orderId, p_refund_id: String(rf.id), p_charge_id: sec.data.charge_id, p_amount: amount, p_status: refundStatus(String(rf.status ?? "")),
    p_reason: reason, p_requested_by: uid,
  });
  if (r.error) return fail(500, dbMessage(r.error));
  return ok({ refund_id: rf.id, status: refundStatus(String(rf.status ?? "")) });
}

// ---------------------------------------------------------------- scheduled billing (fallback when pg_cron is unavailable)
export async function runBilling(d: Deps, headers: Headers): Promise<Result> {
  const given = headers.get("x-cron-secret") ?? "";
  if (!d.env.CRON_SECRET || !timingSafeEqual(given, d.env.CRON_SECRET)) return fail(401, "unauthorized");
  const r = await d.serviceRpc("run_billing_jobs", {});
  if (r.error) return fail(500, dbMessage(r.error));
  return ok({ result: r.data });
}
