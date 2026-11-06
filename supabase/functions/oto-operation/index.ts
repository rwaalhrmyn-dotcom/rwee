import { createOtoOperation } from "../_shared/oto-handler.ts";
Deno.serve(
  createOtoOperation({
    url: Deno.env.get("SUPABASE_URL"),
    publishableKey: Deno.env.get("RIWA_SUPABASE_PUBLISHABLE_KEY"),
    secretKey:
      Deno.env.get("RIWA_SUPABASE_SECRET_KEY") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
    refreshToken: Deno.env.get("OTO_REFRESH_TOKEN"),
    environment: Deno.env.get("OTO_ENVIRONMENT") ?? "sandbox",
    allowProductionExport: Deno.env.get("OTO_ALLOW_PRODUCTION_EXPORT"),
    allowedOrigins: Deno.env.get("RIWA_ALLOWED_ORIGINS"),
  }),
);
