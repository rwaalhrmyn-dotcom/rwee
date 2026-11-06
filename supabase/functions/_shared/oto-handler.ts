import { boundedJson, createOtoClient, record, type OtoConfig } from "./oto.ts";
export type BackendConfig = {
  url?: string;
  publishableKey?: string;
  secretKey?: string;
  allowedOrigins?: string;
};
export function backend(config: BackendConfig, fetcher: typeof fetch = fetch) {
  const url = new URL(config.url ?? "");
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.pathname !== "/" ||
    url.search ||
    url.hash ||
    !config.secretKey
  )
    throw new Error("Backend not configured");
  const root = url.origin;
  return {
    async user(token: string) {
      if (!config.publishableKey) throw new Error("Backend not configured");
      const response = await fetcher(root + "/auth/v1/user", {
        headers: { apikey: config.publishableKey, Authorization: token },
        signal: AbortSignal.timeout(8000),
        redirect: "error",
      });
      if (!response.ok) throw new Error("Invalid session");
      const user = record(await boundedJson(response));
      if (
        typeof user.id !== "string" ||
        user.is_anonymous === true ||
        !(user.email_confirmed_at || user.phone_confirmed_at)
      )
        throw new Error("Unverified user");
    },
    async rpc(name: string, args: object, token?: string) {
      const key = token ? config.publishableKey : config.secretKey;
      if (!key) throw new Error("Backend not configured");
      const headers: Record<string, string> = {
        apikey: key,
        "Content-Type": "application/json",
        Accept: "application/json",
      };
      if (token) headers.Authorization = token;
      else if (key.startsWith("eyJ")) headers.Authorization = "Bearer " + key;
      const response = await fetcher(root + "/rest/v1/rpc/" + name, {
        method: "POST",
        headers,
        body: JSON.stringify(args),
        signal: AbortSignal.timeout(8000),
        redirect: "error",
      });
      if (!response.ok) throw new Error("Database operation denied");
      return await boundedJson(response);
    },
  };
}
export function createOtoOperation(
  config: BackendConfig & OtoConfig,
  fetcher: typeof fetch = fetch,
) {
  let api: ReturnType<typeof createOtoClient> | undefined;
  return async (request: Request) => {
    const origin = request.headers.get("Origin");
    const origins = (config.allowedOrigins ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      Vary: "Origin",
    };
    if (origin && !origins.includes(origin))
      return new Response("{}", { status: 403, headers });
    if (origin)
      Object.assign(headers, {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Headers":
          "authorization, apikey, content-type, x-client-info",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      });
    const reply = (status: number) =>
      new Response(JSON.stringify({ ok: status === 200 }), { status, headers });
    if (request.method === "OPTIONS")
      return new Response(null, { status: 204, headers });
    if (request.method !== "POST") return reply(405);
    const token = request.headers.get("Authorization") ?? "";
    if (!/^Bearer [A-Za-z0-9_.-]{20,8192}$/.test(token)) return reply(401);
    let service: ReturnType<typeof backend>;
    try {
      service = backend(config, fetcher);
      api ??= createOtoClient(config, fetcher);
    } catch {
      return reply(503);
    }
    try {
      await service.user(token);
    } catch {
      return reply(401);
    }
    let id: string, action: string;
    try {
      const body = record(await boundedJson(request, 2048));
      id = String(body.shipment_id ?? "");
      action = String(body.action ?? "");
      if (
        Object.keys(body).some((k) => !["shipment_id", "action"].includes(k)) ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
          id,
        ) ||
        !["export", "refresh"].includes(action)
      )
        return reply(400);
    } catch {
      return reply(400);
    }
    if (
      action === "export" &&
      config.environment === "production" &&
      config.allowProductionExport !== "true"
    )
      return reply(409);
    let claim: Record<string, unknown>;
    try {
      claim = record(
        await service.rpc(
          "claim_oto_operation",
          { p_shipment_id: id, p_action: action },
          token,
        ),
      );
      if (
        typeof claim.operation_id !== "string" ||
        typeof claim.provider_order_id !== "string"
      )
        throw new Error("Invalid claim");
    } catch {
      return reply(409);
    }
    let success = false,
      result: object = {};
    try {
      if (action === "export") await api!.createOrder(claim.payload);
      else result = await api!.status(String(claim.provider_order_id));
      success = true;
    } catch {
      success = false;
    }
    try {
      const completed = await service.rpc("complete_oto_operation", {
        p_shipment_id: id,
        p_operation_id: claim.operation_id,
        p_success: success,
        p_result: result,
      });
      return reply(success && completed === true ? 200 : 502);
    } catch {
      return reply(503);
    }
  };
}
