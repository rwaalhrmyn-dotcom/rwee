// Deno-only wiring for the finance handlers (Supabase clients, env, HTTP helpers).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import type { Deps, Result } from "./handlers.ts";

export const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("SITE_URL") ?? "https://rwaalhrmyn.store",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

export function respond(r: Result): Response {
  return new Response(JSON.stringify(r.body), { status: r.status, headers: { ...cors, "Content-Type": "application/json" } });
}

export function makeDeps(): Deps {
  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const asUser = (auth: string) => createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  return {
    env: {
      GATEWAY_SECRETS_KEY: Deno.env.get("GATEWAY_SECRETS_KEY") ?? "",
      SITE_URL: Deno.env.get("SITE_URL") ?? "https://rwaalhrmyn.store",
      SUPABASE_URL: url,
      CRON_SECRET: Deno.env.get("CRON_SECRET") ?? "",
    },
    fetch: (input, init) => fetch(input, init),
    async getUserId(auth) {
      if (!auth.startsWith("Bearer ")) return null;
      const { data } = await asUser(auth).auth.getUser();
      return data?.user?.id ?? null;
    },
    async userRpc(auth, fn, args) { return await asUser(auth).rpc(fn, args); },
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
