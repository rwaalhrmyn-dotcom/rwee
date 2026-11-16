// Deno-only wiring for the finance handlers (Supabase service client, env, HTTP helpers).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import type { Deps, Result } from "./handlers.ts";

export const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("SITE_URL") ?? "https://rwaalhrmyn.store",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

export function respond(r: Result): Response {
  return new Response(JSON.stringify(r.body), { status: r.status, headers: { ...cors, "Content-Type": "application/json" } });
}

export function makeDeps(): Deps {
  const service = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  return {
    env: { CRON_SECRET: Deno.env.get("CRON_SECRET") ?? "" },
    async serviceRpc(fn, args) { return await service.rpc(fn, args); },
    log(msg, extra) { console.log(JSON.stringify({ msg, extra })); },
  };
}

export async function handle(req: Request, run: (d: Deps, req: Request) => Promise<Result>): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return respond({ status: 405, body: { error: "method not allowed" } });
  try { return respond(await run(makeDeps(), req)); }
  catch (e) { console.error(e); return respond({ status: 500, body: { error: "internal error" } }); }
}
