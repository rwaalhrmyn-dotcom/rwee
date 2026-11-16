// Tap Payments adapter used with the SUPPLIER's own secret key, so funds settle in the
// supplier's Tap account (no split payments, nothing passes through Rawaa's account).
// fetch is injected so the module is testable and runtime-agnostic.

export type Fetch = (input: string, init?: RequestInit) => Promise<Response>;
const API = "https://api.tap.company/v2";

export const toSar = (halalas: number) => Math.round(halalas) / 100;
export const toHalalas = (sar: number | string) => Math.round(Number(sar) * 100);

export function keyMode(secret: string): "test" | "live" | null {
  if (/^sk_test_[A-Za-z0-9]{8,}$/.test(secret)) return "test";
  if (/^sk_live_[A-Za-z0-9]{8,}$/.test(secret)) return "live";
  return null;
}

export const keyHint = (secret: string) => secret.slice(-4).replace(/[^A-Za-z0-9_]/g, "");

// Authenticates the key without moving money: retrieving an unknown charge returns an
// auth error (401/403) for a bad key and "not found"/validation (400/404) for a valid one.
export async function verifyKey(fetchFn: Fetch, secret: string): Promise<"valid" | "invalid" | "unreachable"> {
  try {
    const r = await fetchFn(`${API}/charges/chg_rawaa_key_check_000000`, { headers: { Authorization: `Bearer ${secret}` } });
    if (r.status === 401 || r.status === 403) return "invalid";
    if (r.ok || r.status === 400 || r.status === 404) return "valid";
    return "unreachable";
  } catch {
    return "unreachable";
  }
}

export interface ChargeInput {
  amountHalalas: number; orderId: string; supplierId: string; customerName: string; phone: string;
  redirectUrl: string; webhookUrl: string; merchantId?: string | null; description: string;
}

export function phoneObj(p: string) {
  const digits = (p || "").replace(/\D/g, "").replace(/^966/, "").replace(/^0/, "");
  return { country_code: "966", number: digits || "500000000" };
}

export async function createCharge(fetchFn: Fetch, secret: string, c: ChargeInput) {
  const body: Record<string, unknown> = {
    amount: toSar(c.amountHalalas), currency: "SAR", threeDSecure: true, save_card: false,
    description: c.description, customer: { first_name: c.customerName || "Customer", phone: phoneObj(c.phone) },
    source: { id: "src_all" }, reference: { transaction: c.orderId, order: c.orderId },
    metadata: { order_id: c.orderId, supplier_id: c.supplierId, platform: "rawaa" },
    redirect: { url: c.redirectUrl }, post: { url: c.webhookUrl },
  };
  if (c.merchantId) body.merchant = { id: c.merchantId };
  const r = await fetchFn(`${API}/charges`, { method: "POST", headers: { Authorization: `Bearer ${secret}`, "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j?.id || !j?.transaction?.url) throw new Error(`tap charge failed: ${r.status} ${JSON.stringify(j?.errors ?? j).slice(0, 300)}`);
  return { id: String(j.id), url: String(j.transaction.url), status: String(j.status ?? "INITIATED") };
}

export async function getCharge(fetchFn: Fetch, secret: string, id: string) {
  const r = await fetchFn(`${API}/charges/${encodeURIComponent(id)}`, { headers: { Authorization: `Bearer ${secret}` } });
  if (!r.ok) return null;
  return await r.json();
}

export async function createRefund(fetchFn: Fetch, secret: string, chargeId: string, amountHalalas: number, reason: string, orderId: string, webhookUrl: string) {
  const r = await fetchFn(`${API}/refunds`, {
    method: "POST", headers: { Authorization: `Bearer ${secret}`, "Content-Type": "application/json" },
    body: JSON.stringify({ charge_id: chargeId, amount: toSar(amountHalalas), currency: "SAR", reason, reference: { merchant: orderId },
      metadata: { order_id: orderId, platform: "rawaa" }, post: { url: webhookUrl } }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j?.id) throw new Error(`tap refund failed: ${r.status} ${JSON.stringify(j?.errors ?? j).slice(0, 300)}`);
  return j;
}

export async function getRefund(fetchFn: Fetch, secret: string, id: string) {
  const r = await fetchFn(`${API}/refunds/${encodeURIComponent(id)}`, { headers: { Authorization: `Bearer ${secret}` } });
  if (!r.ok) return null;
  return await r.json();
}

export function refundStatus(tapStatus: string): "pending" | "succeeded" | "failed" {
  const s = (tapStatus || "").toUpperCase();
  if (s === "REFUNDED" || s === "SUCCEEDED") return "succeeded";
  if (["FAILED", "CANCELLED", "DECLINED", "REJECTED"].includes(s)) return "failed";
  return "pending";
}

// Tap webhook "hashstring" (HMAC-SHA256 with the merchant secret). Advisory only: the
// authoritative state always comes from re-fetching the object with the supplier key.
export function chargeHashMessage(ch: any): string {
  const amount = Number(ch?.amount ?? 0).toFixed(2);
  return `x_id${ch?.id ?? ""}x_amount${amount}x_currency${ch?.currency ?? ""}x_gateway_reference${ch?.reference?.gateway ?? ""}` +
    `x_payment_reference${ch?.reference?.payment ?? ""}x_status${ch?.status ?? ""}x_created${ch?.transaction?.created ?? ""}`;
}
