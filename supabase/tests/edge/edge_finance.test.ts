// End-to-end tests for the supplier-direct payment Edge Function handlers: the real
// handler code runs against the real dev database (SQL functions + RLS), with Tap
// replaced by an in-memory fake that enforces per-account key ownership.
// Run: npm test   (rebuilds the local dev DB first; requires supabase/dev/rebuild.sh)
import { test } from "node:test";
import assert from "node:assert/strict";
import { execSync } from "node:child_process";
import pg from "pg";
import { runBilling, timingSafeEqual, type Deps } from "../../functions/_shared/finance/handlers.ts";

execSync(new URL("../../dev/rebuild.sh", import.meta.url).pathname, { stdio: "ignore" });
const pool = new pg.Pool({ host: "127.0.0.1", user: "postgres", password: process.env.PGPASSWORD ?? "rawaa-dev-only", database: process.env.PGDATABASE ?? "rwaa_dev" });

const ADMIN = "00000000-0000-0000-0000-0000000000a0", S1 = "00000000-0000-0000-0000-0000000000b1", S2 = "00000000-0000-0000-0000-0000000000b2";
const C1 = "00000000-0000-0000-0000-0000000000c1", COURIER = "00000000-0000-0000-0000-0000000000d1";

async function sql(text: string, params: unknown[] = []) { return (await pool.query(text, params)).rows; }

const fnMeta = new Map<string, { argNames: string[]; set: boolean; void: boolean }>();
async function rpc(role: "authenticated" | "service_role", uid: string | null, fn: string, args: Record<string, unknown>) {
  const c = await pool.connect();
  try {
    await c.query("begin");
    const sid = uid ? (await c.query("select id from auth.sessions where user_id=$1 limit 1", [uid])).rows[0]?.id : null;
    const claims = role === "service_role" ? { role: "service_role" } : { sub: uid, role: "authenticated", session_id: sid, aal: "aal1", amr: [{ method: "password" }] };
    await c.query("select set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims)]);
    if (!fnMeta.has(fn)) {
      const m = (await c.query(`select proretset as set, prorettype = 'void'::regtype as void from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname='public' and proname=$1 and coalesce((select array_agg(x order by x) from unnest(coalesce(proargnames,'{}')) x), '{}') @> $2::text[] limit 1`, [fn, Object.keys(args)])).rows[0];
      fnMeta.set(fn, { argNames: Object.keys(args), set: m?.set ?? false, void: m?.void ?? false });
    }
    const meta = fnMeta.get(fn)!;
    await c.query(`set local role ${role}`);
    const names = Object.keys(args);
    const call = `public.${fn}(${names.map((k, i) => `${k} => $${i + 1}`).join(", ")})`;
    const vals = names.map((k) => (args[k] !== null && typeof args[k] === "object" ? JSON.stringify(args[k]) : args[k]));
    let data: unknown = null;
    if (meta.void) await c.query(`select ${call}`, vals);
    else {
      const r = await c.query(`select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) as data from ${call} as x`, vals);
      data = meta.set ? r.rows[0].data : r.rows[0].data[0] ?? null;
    }
    await c.query("commit");
    return { data, error: null };
  } catch (e: any) {
    await c.query("rollback");
    return { data: null, error: { message: e.message } };
  } finally { c.release(); }
}

// ---------------------------------------------------------------- fake Tap (per-account isolation)
const deps: Deps = {
  env: { CRON_SECRET: "cron-secret-test" },
  serviceRpc: (fn, args) => rpc("service_role", null, fn, args),
  log: () => {},
};

test("E1 constant-time secret comparison", () => {
  assert.equal(timingSafeEqual("abc", "abc"), true);
  assert.equal(timingSafeEqual("abc", "abd"), false);
  assert.equal(timingSafeEqual("abc", "abcd"), false);
});

test("E2 billing runner requires the cron secret and runs the jobs", async () => {
  assert.equal((await runBilling(deps, new Headers())).status, 401);
  assert.equal((await runBilling(deps, new Headers({ "x-cron-secret": "wrong" }))).status, 401);
  assert.equal((await runBilling({ ...deps, env: {} }, new Headers({ "x-cron-secret": "" }))).status, 401);
  const r = await runBilling(deps, new Headers({ "x-cron-secret": "cron-secret-test" }));
  assert.equal(r.status, 200, JSON.stringify(r.body));
});

test("E3 Tap service entry points are retired for the service role", async () => {
  const r = await rpc("service_role", null, "svc_process_charge", { p_provider: "tap", p_charge_id: "chg_X", p_order: "00000000-0000-0000-0000-000000000000",
    p_provider_status: "CAPTURED", p_amount_halalas: 1, p_currency: "SAR", p_mode: "test" });
  assert.ok(r.error && /permission denied/i.test(r.error.message), JSON.stringify(r));
  await pool.end();
});
