export type OtoConfig = {
  refreshToken?: string;
  environment?: string;
  allowProductionExport?: string;
};
export type OtoStatus = {
  status: string;
  tracking_number: string | null;
  carrier: string | null;
  tracking_url: string | null;
};
export function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}
export async function boundedJson(
  response: Response | Request,
  limit = 65536,
): Promise<unknown> {
  if (!response.body) throw new Error("Missing body");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel();
        throw new Error("Body limit");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const data = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    data.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return JSON.parse(new TextDecoder().decode(data));
}
export function safeTrackingUrl(value: unknown): string | null {
  if (typeof value !== "string" || value.length > 2048) return null;
  try {
    const u = new URL(value);
    return u.protocol === "https:" &&
      u.hostname === "app.tryoto.com" &&
      !u.port &&
      !u.username &&
      !u.password
      ? u.href
      : null;
  } catch {
    return null;
  }
}
function text(value: unknown, max: number): string | null {
  return typeof value === "string" &&
    value.length <= max &&
    !/[\u0000-\u001f]/.test(value)
    ? value || null
    : null;
}
export function parseStatus(value: unknown, expectedOrder: string): OtoStatus {
  const body = record(value);
  if (
    body.success !== true ||
    body.orderId !== expectedOrder ||
    typeof body.status !== "string" ||
    !/^[A-Za-z0-9_-]{1,80}$/.test(body.status)
  )
    throw new Error("Invalid provider status");
  return {
    status: body.status,
    tracking_number: text(body.dcTrackingNumber, 160),
    carrier: text(body.deliveryCompany, 100),
    tracking_url: safeTrackingUrl(body.trackingUrl),
  };
}
export function exportPayload(value: unknown) {
  const p = record(value);
  const c = record(p.customer);
  const sourceItems = p.items;
  if (
    typeof p.orderId !== "string" ||
    !/^riwa-[a-f0-9-]{73}$/.test(p.orderId) ||
    typeof p.pickupLocationCode !== "string" ||
    !/^[A-Za-z0-9_-]{1,80}$/.test(p.pickupLocationCode) ||
    p.currency !== "SAR" ||
    p.payment_method !== "paid" ||
    p.amount_due !== 0 ||
    p.createShipment !== false ||
    !Number.isFinite(p.amount) ||
    Number(p.amount) <= 0 ||
    !Array.isArray(sourceItems) ||
    sourceItems.length < 1 ||
    sourceItems.length > 99
  )
    throw new Error("Invalid export");
  const name = text(c.name, 100),
    address = text(c.address, 1000),
    city = text(c.city, 80);
  let mobile =
    typeof c.mobile === "string" ? c.mobile.replace(/[\s()-]/g, "") : "";
  if (/^05\d{8}$/.test(mobile)) mobile = "+966" + mobile.slice(1);
  else if (mobile.startsWith("00")) mobile = "+" + mobile.slice(2);
  else if (/^[1-9]\d{7,14}$/.test(mobile)) mobile = "+" + mobile;
  if (
    !name ||
    !address ||
    !city ||
    !/^\+[1-9]\d{7,14}$/.test(mobile) ||
    c.country !== "SA" ||
    !Number.isFinite(p.packageWeight) ||
    Number(p.packageWeight) < 0.01 ||
    Number(p.packageWeight) > 1000 ||
    !Number.isInteger(p.packageCount) ||
    Number(p.packageCount) < 1 ||
    Number(p.packageCount) > 99
  )
    throw new Error("Invalid shipping details");
  const items = sourceItems.map((item: unknown) => {
    const i = record(item);
    if (
      !text(i.name, 160) ||
      !text(i.sku, 80) ||
      !Number.isInteger(i.quantity) ||
      Number(i.quantity) < 1 ||
      Number(i.quantity) > 99 ||
      !Number.isFinite(i.price) ||
      Number(i.price) <= 0
    )
      throw new Error("Invalid shipping item");
    return { name: i.name, sku: i.sku, price: i.price, quantity: i.quantity };
  });
  const total = items.reduce(
    (sum, i) => sum + Math.round(Number(i.price) * 100) * Number(i.quantity),
    0,
  );
  if (total !== Math.round(Number(p.amount) * 100))
    throw new Error("Invalid merchandise amount");
  return {
    orderId: p.orderId,
    parentOrderId: p.parentOrderId,
    pickupLocationCode: p.pickupLocationCode,
    createShipment: false,
    payment_method: "paid",
    amount: p.amount,
    amount_due: 0,
    currency: "SAR",
    packageWeight: p.packageWeight,
    packageCount: p.packageCount,
    customer: { name, address, city, mobile, country: "SA" },
    items,
  };
}
export function createOtoClient(
  config: OtoConfig,
  fetcher: typeof fetch = fetch,
  clock = Date.now,
) {
  if (
    !config.refreshToken ||
    config.refreshToken.length < 16 ||
    /[\r\n]/.test(config.refreshToken) ||
    !["sandbox", "production"].includes(config.environment ?? "sandbox")
  )
    throw new Error("OTO not configured");
  const base =
    config.environment === "production"
      ? "https://api.tryoto.com/rest/v2/"
      : "https://staging-api.tryoto.com/rest/v2/";
  let cached: { value: string; expiry: number } | undefined;
  let refreshing: Promise<string> | undefined;
  async function request(path: string, body: unknown, token?: string) {
    return await fetcher(base + path, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        ...(token ? { Authorization: "Bearer " + token } : {}),
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(8000),
      redirect: "error",
    });
  }
  async function token() {
    if (cached && cached.expiry > clock()) return cached.value;
    if (refreshing) return refreshing;
    refreshing = (async () => {
      const response = await request("refreshToken", {
        refresh_token: config.refreshToken,
      });
      if (!response.ok) throw new Error("OTO authentication failed");
      const data = record(await boundedJson(response));
      const ttl = Number(data.expires_in);
      if (
        data.success !== true ||
        typeof data.access_token !== "string" ||
        !data.access_token ||
        data.access_token.length > 16000 ||
        /[\r\n]/.test(data.access_token) ||
        !Number.isFinite(ttl) ||
        ttl < 60 ||
        ttl > 3600
      )
        throw new Error("OTO authentication failed");
      cached = {
        value: data.access_token,
        expiry: clock() + ttl * 1000 - 30000,
      };
      return cached.value;
    })();
    try {
      return await refreshing;
    } finally {
      refreshing = undefined;
    }
  }
  return {
    async status(orderId: string) {
      if (!/^[A-Za-z0-9_-]{1,160}$/.test(orderId))
        throw new Error("Invalid order reference");
      let credential = await token();
      let response = await request("orderStatus", { orderId }, credential);
      if (response.status === 401) {
        if (cached?.value === credential) cached = undefined;
        credential = await token();
        response = await request("orderStatus", { orderId }, credential);
      }
      if (!response.ok) throw new Error("OTO status unavailable");
      return parseStatus(await boundedJson(response), orderId);
    },
    async createOrder(value: unknown) {
      if (
        config.environment === "production" &&
        config.allowProductionExport !== "true"
      )
        throw new Error("Production export disabled");
      const payload = exportPayload(value);
      const credential = await token();
      // Never retry a mutation whose outcome is unknown. Refresh status to reconcile it.
      const response = await request("createOrder", payload, credential);
      if (!response.ok) throw new Error("OTO export outcome unknown");
      const data = record(await boundedJson(response));
      if (
        data.success !== true ||
        !/^[1-9][0-9]{0,30}$/.test(String(data.otoId ?? ""))
      )
        throw new Error("OTO export outcome unknown");
    },
  };
}
export type OtoEvent = {
  fingerprint: string;
  order_id: string;
  event_type: "orderStatus" | "shipmentError";
  value: string;
  event_at: string;
};
function timestamp(value: unknown): number {
  if (typeof value !== "string") return Number.NaN;
  const iso = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(value)
    ? value.replace(" ", "T") + "Z"
    : value;
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(iso))
    return Number.NaN;
  const parsed = Date.parse(iso);
  return Number.isFinite(parsed) &&
    new Date(parsed).toISOString().slice(0, 19) === iso.slice(0, 19)
    ? parsed
    : Number.NaN;
}
export function createOtoWebhook(
  secrets: { orderStatus?: string; shipmentError?: string },
  persist: (event: OtoEvent) => Promise<void>,
  clock = Date.now,
) {
  return async (request: Request) => {
    const reply = (status: number) =>
      new Response(JSON.stringify({ accepted: status === 200 }), {
        status,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      });
    if (request.method !== "POST") return reply(405);
    const routeKind = new URL(request.url).pathname.split("/").pop();
    if (routeKind !== "orderStatus" && routeKind !== "shipmentError")
      return reply(404);
    const secret = secrets[routeKind];
    if (
      !secret ||
      secret.length < 32 ||
      secrets.orderStatus === secrets.shipmentError
    )
      return reply(503);
    let event: OtoEvent;
    try {
      const body = record(await boundedJson(request, 16384));
      const kind = routeKind;
      if (body.webhookType !== undefined && body.webhookType !== kind)
        return reply(400);
      const orderId = body.orderId,
        value =
          kind === "orderStatus" ? body.status : String(body.errorCode ?? ""),
        time = timestamp(body.timestamp);
      if (
        typeof orderId !== "string" ||
        !/^[A-Za-z0-9_-]{1,160}$/.test(orderId) ||
        typeof value !== "string" ||
        !/^[A-Za-z0-9_-]{1,80}$/.test(value) ||
        !Number.isFinite(time) ||
        Math.abs(clock() - time) > 300000 ||
        typeof body.signature !== "string" ||
        !/^[A-Za-z0-9+/]{43}=$/.test(body.signature)
      )
        return reply(401);
      const message = orderId + ":" + value + ":" + body.timestamp;
      const bytes = new TextEncoder().encode(message);
      const key = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["verify"],
      );
      const signature = Uint8Array.from(atob(body.signature), (c) =>
        c.charCodeAt(0),
      );
      if (!(await crypto.subtle.verify("HMAC", key, signature, bytes)))
        return reply(401);
      const digest = await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(kind + ":" + message),
      );
      event = {
        fingerprint: Array.from(new Uint8Array(digest), (x) =>
          x.toString(16).padStart(2, "0"),
        ).join(""),
        order_id: orderId,
        event_type: kind,
        value,
        event_at: new Date(time).toISOString(),
      };
      // Only signed fields survive. Tracking URLs and carrier error messages are not signed.
    } catch {
      return reply(400);
    }
    try {
      await persist(event);
      return reply(200);
    } catch {
      return reply(503);
    }
  };
}
