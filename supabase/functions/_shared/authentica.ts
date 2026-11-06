import { Webhook } from "standardwebhooks";

type HookKind = "email" | "sms";
type Config = {
  apiKey?: string;
  hookSecrets?: string;
  templateId?: string;
  smsMethod?: string;
};
type Delivery = {
  method: "email" | "sms" | "whatsapp";
  otp: string;
  template_id: number;
  email?: string;
  phone?: string;
};
function object(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}
function delivery(kind: HookKind, payload: unknown, config: Config): Delivery {
  const event = object(payload);
  const user = object(event.user);
  if (typeof user.id !== "string" || !user.id || user.is_anonymous === true)
    throw new Error("Invalid account");
  const template = Number(config.templateId ?? "1");
  if (!Number.isSafeInteger(template) || template < 1)
    throw new Error("Invalid template");
  if (kind === "email") {
    const data = object(event.email_data);
    // Other account actions need their own templates and verification UI.
    if (
      !["signup", "magiclink", "email"].includes(String(data.email_action_type))
    )
      throw new Error("Unsupported email action");
    if (
      typeof user.email !== "string" ||
      user.email.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(user.email) ||
      typeof data.token !== "string" ||
      !/^\d{6}$/.test(data.token)
    )
      throw new Error("Invalid email event");
    return {
      method: "email",
      email: user.email,
      otp: data.token,
      template_id: template,
    };
  }
  const otp = object(event.sms).otp;
  const rawPhone = typeof user.phone === "string" ? user.phone : "";
  // Phone-change confirmation needs the new verified destination's own flow.
  // Sending its code to the old phone could confirm a number the user does not own.
  if (
    [user.new_phone, user.phone_change].some(
      (value) => typeof value === "string" && value.length > 0,
    )
  )
    throw new Error("Unsupported phone change");
  const phone = rawPhone.startsWith("+") ? rawPhone : "+" + rawPhone;
  const method = config.smsMethod ?? "sms";
  if (
    !/^\+[1-9]\d{7,14}$/.test(phone) ||
    typeof otp !== "string" ||
    !/^\d{6}$/.test(otp) ||
    !["sms", "whatsapp"].includes(method)
  )
    throw new Error("Invalid phone event");
  return {
    method: method as "sms" | "whatsapp",
    phone,
    otp,
    template_id: template,
  };
}
function json(status: number, body: object) {
  const error = (body as { error?: string }).error;
  return new Response(
    JSON.stringify(
      error ? { error: { http_code: status, message: error } } : body,
    ),
    {
      status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    },
  );
}
async function smallBody(request: Request) {
  const reader = request.body?.getReader();
  if (!reader) return "";
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let size = 0;
  let body = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) return body + decoder.decode();
      size += value.byteLength;
      if (size > 32_768) {
        await reader.cancel();
        return null;
      }
      body += decoder.decode(value, { stream: true });
    }
  } finally {
    reader.releaseLock();
  }
}
export function createAuthenticaHook(
  kind: HookKind,
  config: Config,
  send: typeof fetch = fetch,
) {
  // Best-effort deduplication within this function instance, not a global ledger.
  const sent = new Map<
    string,
    { digest: string; expires: number; promise: Promise<boolean> }
  >();
  return async (request: Request): Promise<Response> => {
    if (request.method !== "POST")
      return json(405, { error: "Method not allowed" });
    if (!config.apiKey || !config.hookSecrets)
      return json(503, { error: "Authentication delivery is not configured" });
    if (
      !request.headers
        .get("content-type")
        ?.toLowerCase()
        .startsWith("application/json")
    )
      return json(415, { error: "JSON required" });
    if (Number(request.headers.get("content-length")) > 32_768)
      return json(413, { error: "Request too large" });
    let raw: string | null;
    try {
      raw = await smallBody(request);
    } catch {
      return json(400, { error: "Invalid request" });
    }
    if (raw === null) return json(413, { error: "Request too large" });
    const id = request.headers.get("webhook-id") ?? "";
    const timestamp = request.headers.get("webhook-timestamp") ?? "";
    if (!id || id.length > 160 || !/^\d{1,12}$/.test(timestamp))
      return json(401, { error: "Invalid signature" });
    let payload: unknown;
    let verified = false;
    for (const secret of config.hookSecrets.split("|").slice(0, 3)) {
      try {
        payload = new Webhook(secret.replace(/^v1,/, "")).verify(
          raw,
          Object.fromEntries(request.headers),
        );
        verified = true;
        break;
      } catch {
        /* No provider request is made until signature verification succeeds. */
      }
    }
    if (!verified) return json(401, { error: "Invalid signature" });
    let message: Delivery;
    try {
      message = delivery(kind, payload, config);
    } catch {
      return json(400, { error: "Unsupported authentication event" });
    }
    const digest = Array.from(
      new Uint8Array(
        await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw)),
      ),
    )
      .map((byte) => byte.toString(16).padStart(2, "0"))
      .join("");
    const now = Date.now();
    for (const [key, entry] of sent) if (entry.expires < now) sent.delete(key);
    const prior = sent.get(id);
    if (prior && prior.digest !== digest)
      return json(409, { error: "Conflicting event" });
    if (!prior && sent.size >= 512)
      return json(503, { error: "Please retry later" });
    const promise =
      prior?.promise ??
      (async () => {
        try {
          const response = await send(
            "https://api.authentica.sa/api/v2/send-otp",
            {
              method: "POST",
              headers: {
                "X-Authorization": config.apiKey!,
                Accept: "application/json",
                "Content-Type": "application/json",
              },
              body: JSON.stringify(message),
              signal: AbortSignal.timeout(3000),
              redirect: "error",
            },
          );
          if (!response.ok) return false;
          const result: unknown = await response.json();
          return object(result).success === true;
        } catch {
          return false;
        }
      })();
    if (!prior) sent.set(id, { digest, promise, expires: now + 300_000 });
    const success = await promise;
    if (!success) {
      if (sent.get(id)?.promise === promise) sent.delete(id);
      return json(502, {
        error: "Authentication message could not be delivered",
      });
    }
    // Supabase, rather than this delivery provider, validates and consumes the OTP.
    return json(200, {});
  };
}
