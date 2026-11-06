import { createAuthenticaHook } from "../_shared/authentica.ts";

Deno.serve(
  createAuthenticaHook("sms", {
    apiKey: Deno.env.get("AUTHENTICA_API_KEY"),
    hookSecrets: Deno.env.get("AUTHENTICA_SMS_HOOK_SECRET"),
    templateId: Deno.env.get("AUTHENTICA_SMS_TEMPLATE_ID"),
    smsMethod: Deno.env.get("AUTHENTICA_SMS_METHOD"),
  }),
);
