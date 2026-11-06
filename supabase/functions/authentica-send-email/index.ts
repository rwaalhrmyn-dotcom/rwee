import { createAuthenticaHook } from "../_shared/authentica.ts";

Deno.serve(
  createAuthenticaHook("email", {
    apiKey: Deno.env.get("AUTHENTICA_API_KEY"),
    hookSecrets: Deno.env.get("AUTHENTICA_EMAIL_HOOK_SECRET"),
    templateId: Deno.env.get("AUTHENTICA_EMAIL_TEMPLATE_ID"),
  }),
);
