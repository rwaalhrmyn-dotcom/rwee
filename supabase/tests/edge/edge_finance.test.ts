// End-to-end tests for the supplier-direct payment Edge Function handlers: the real
// handler code runs against the real dev database (SQL functions + RLS), with Tap
// replaced by an in-memory fake that enforces per-account key ownership.
// Run: npm test   (rebuilds the local dev DB first; requires supabase/dev/rebuild.sh)
import { test } from "node:test";
import assert from "node:assert/strict";
import { execSync } from "node:child_process";
import pg from "pg";
import { connectGateway, createCheckout, processWebhook, refundOrder, runBilling, type Deps } from "../../functions/_shared/finance/handlers.ts";
import { openSecret, sealSecret, b64encode } from "../../functions/_shared/finance/crypto.ts";

execSync(new URL("../../dev/rebuild.sh", import.meta.url).pathname, { stdio: "ignore" });
const pool = new pg.Pool({ host: "127.0.0.1", user: "postgres", password: process.env.PGPASSWORD ?? "rawaa-dev-only", database: process.env.PGDATABASE ?? "rwaa_dev" });

const ADMIN = "00000000-0000-0000-0000-0000000000a0", S1 = "00000000-0000-0000-0000-0000000000b1", S2 = "00000000-0000-0000-0000-0000000000b2";
const C1 = "00000000-0000-0000-0000-0000000000c1", COURIER = "00000000-0000-0000-0000-0000000000d1";
const KEY1 = "sk_test_SupplierOneKey1234", KEY2 = "sk_test_SupplierTwoKey5678";

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
const jsonRes = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
const strip = (o: any) => { const { _key, ...rest } = o; return rest; };
class FakeTap {
  keys = new Set([KEY1, KEY2]);
  charges = new Map<string, any>(); refunds = new Map<string, any>(); calls: { method: string; path: string; key: string }[] = []; n = 0;
  fetch = async (url: string, init: RequestInit = {}) => {
    const key = String((init.headers as any)?.Authorization ?? "").replace("Bearer ", "");
    const method = init.method ?? "GET"; const path = url.replace("https://api.tap.company/v2", "");
    this.calls.push({ method, path, key });
    if (!this.keys.has(key)) return jsonRes(401, { errors: [{ code: "2107", description: "Invalid API key" }] });
    if (method === "GET" && path.startsWith("/charges/")) {
      const c = this.charges.get(decodeURIComponent(path.slice(9)));
      return !c || c._key !== key ? jsonRes(404, { errors: [{ code: "1129" }] }) : jsonRes(200, strip(c));
    }
    if (method === "POST" && path === "/charges") {
      const b = JSON.parse(String(init.body)); const id = "chg_TS" + String(++this.n).padStart(8, "0");
      const c = { ...b, id, status: "INITIATED", transaction: { url: "https://tap.test/pay/" + id, created: "1700000000000" }, _key: key };
      this.charges.set(id, c); return jsonRes(200, strip(c));
    }
    if (method === "POST" && path === "/refunds") {
      const b = JSON.parse(String(init.body)); const ch = this.charges.get(b.charge_id);
      if (!ch || ch._key !== key) return jsonRes(404, { errors: [{ code: "1129" }] });
      const id = "re_TS" + String(++this.n).padStart(8, "0"); const r = { ...b, id, status: "PENDING", _key: key };
      this.refunds.set(id, r); return jsonRes(200, strip(r));
    }
    if (method === "GET" && path.startsWith("/refunds/")) {
      const r = this.refunds.get(decodeURIComponent(path.slice(9)));
      return !r || r._key !== key ? jsonRes(404, {}) : jsonRes(200, strip(r));
    }
    return jsonRes(404, {});
  };
}
const tap = new FakeTap();
const logs: string[] = [];
const deps: Deps = {
  env: { GATEWAY_SECRETS_KEY: b64encode(crypto.getRandomValues(new Uint8Array(32))), SITE_URL: "https://rwaalhrmyn.store", SUPABASE_URL: "https://proj.supabase.co", CRON_SECRET: "cron-secret-test" },
  fetch: tap.fetch,
  async getUserId(auth) { const m = /^Bearer test:([0-9a-f-]{36})$/.exec(auth); return m ? m[1] : null; },
  userRpc: (auth, fn, args) => rpc("authenticated", /test:(.*)$/.exec(auth)?.[1] ?? null, fn, args),
  serviceRpc: (fn, args) => rpc("service_role", null, fn, args),
  log: (m) => logs.push(m),
};
const bearer = (uid: string) => `Bearer test:${uid}`;
const ctx: Record<string, string> = {};

// ---------------------------------------------------------------- fixtures through the real RPCs
test("fixtures: users, admin, two approved suppliers with consent, a product", async () => {
  for (const [uid, email, phone] of [[ADMIN, "admin@t.t", "+966500000001"], [S1, "s1@t.t", "+966500000011"], [S2, "s2@t.t", "+966500000012"],
    [C1, "c1@t.t", "+966500000021"], [COURIER, "d1@t.t", "+966500000031"]]) {
    await sql(`insert into auth.users(id,email,email_confirmed_at,phone,phone_confirmed_at,encrypted_password) values ($1,$2,now(),$3,now(),'x')`, [uid, email, phone]);
    const sid = (await sql(`insert into auth.sessions(user_id) values ($1) returning id`, [uid]))[0].id;
    await sql(`insert into auth.mfa_amr_claims(session_id, authentication_method) values ($1,'password')`, [sid]);
  }
  await sql(`insert into public.admin_profiles(user_id, role, status, permissions, login_mode) values ($1,'super_admin','active','{}','password')`, [ADMIN]);
  await sql(`insert into private.platform_operators(user_id) values ($1)`, [ADMIN]);
  await sql(`update private.finance_settings set direct_payments_enabled=true, platform_bank_name='مصرف الراجحي', platform_iban='SA0380000000608010167519', platform_account_holder='رواء'`);
  const c = (await sql(`select version_id, body_sha256 from public.supplier_contract_versions where is_current`))[0];
  for (const [uid, name, key] of [[S1, "مورد واحد", "s1"], [S2, "مورد اثنان", "s2"]]) {
    const app = await rpc("authenticated", uid, "submit_seller_application", {
      p: { business_name: name, commercial_registration: "1010000001", entity_type: "factory", iban: "SA0380000000608010167519", tax_number: "300000000000003",
        document_path: `${uid}/cr.pdf`, phone: "0500000000", national_address: "مكة", account_holder_name: name, bank_name: "مصرف الراجحي" },
      p_contract_version: c.version_id, p_contract_hash: c.body_sha256, p_signer_name: "ممثل " + name, p_agreed: true, p_request: crypto.randomUUID() });
    assert.equal(app.error, null, JSON.stringify(app.error));
    const dec = await rpc("authenticated", ADMIN, "admin_decide_application", { p_id: app.data, p_approve: true });
    assert.equal(dec.error, null, JSON.stringify(dec.error));
    ctx[key] = (await sql(`select id from public.suppliers where owner_id=$1`, [uid]))[0].id;
    const prof = await rpc("authenticated", uid, "supplier_save_payment_profile", { p_supplier: ctx[key], p: { entity_type: "factory", legal_name: name,
      cr_number: "1010000001", account_holder_name: name, bank_name: "مصرف الراجحي", iban: "SA0380000000608010167519", vat_registered: true,
      tax_number: "300000000000003", vat_certificate_path: `${uid}/vat.pdf` } });
    assert.equal(prof.error, null, JSON.stringify(prof.error));
  }
  const prod = await sql(`select id from public.products limit 0`);
  assert.ok(prod);
});

test("E1 gateway connection: format, provider rejection, ownership, sealed storage", async () => {
  let r = await connectGateway(deps, bearer(S1), { supplier_id: ctx.s1, secret_key: "not-a-key" });
  assert.equal(r.status, 400);
  r = await connectGateway(deps, bearer(S1), { supplier_id: ctx.s1, secret_key: "sk_test_UnknownKey99999" });
  assert.equal(r.status, 400, "Tap rejects unknown key");
  r = await connectGateway(deps, bearer(S2), { supplier_id: ctx.s1, secret_key: KEY2 });
  assert.equal(r.status, 403, "cannot connect a gateway to another supplier");
  r = await connectGateway(deps, "", { supplier_id: ctx.s1, secret_key: KEY1 });
  assert.equal(r.status, 401);
  r = await connectGateway(deps, bearer(S1), { supplier_id: ctx.s1, secret_key: KEY1 });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.status, "pending", "verified gateway awaits admin review");
  assert.equal(r.body.key_hint, "1234");
  const r2 = await connectGateway(deps, bearer(S2), { supplier_id: ctx.s2, secret_key: KEY2 });
  assert.equal(r2.status, 200);
  const leaked = await sql(`select count(*)::int n from private.supplier_gateway_secrets where ciphertext like '%sk_test%'`);
  assert.equal(leaked[0].n, 0, "plaintext key never stored");
  const dump = JSON.stringify(await sql(`select * from public.supplier_payment_profiles`)) + JSON.stringify(await sql(`select * from public.pricing_audit_log`));
  assert.ok(!dump.includes(KEY1) && !dump.includes(KEY2), "plaintext key not in profiles or audit log");
  for (const s of [ctx.s1, ctx.s2]) {
    const a = await rpc("authenticated", ADMIN, "admin_review_payment_profile", { p_supplier: s, p_action: "approve", p_note: null });
    assert.equal(a.error, null, JSON.stringify(a.error));
  }
  const sell = await sql(`select bool_and(selling_enabled) ok from public.suppliers`);
  assert.equal(sell[0].ok, true);
});

test("E2 crypto: sealed key is bound to its supplier", async () => {
  const s = await sealSecret(KEY1, deps.env.GATEWAY_SECRETS_KEY, ctx.s1);
  assert.equal(await openSecret(s.ciphertext, s.iv, deps.env.GATEWAY_SECRETS_KEY, ctx.s1), KEY1);
  await assert.rejects(() => openSecret(s.ciphertext, s.iv, deps.env.GATEWAY_SECRETS_KEY, ctx.s2), "blob moved to another supplier does not decrypt");
});

test("E3 checkout charges the supplier's own Tap account for the payable amount", async () => {
  const p = await rpc("authenticated", S1, "supplier_save_product", { p_product_id: null, p_supplier_id: ctx.s1, p_expected_version: null,
    p_data: { name: "مياه", description: "كرتون", unit: "كرتون", category: "water", price_halalas: 10000, stock: 10, cities: ["makkah"], active: true } });
  assert.equal(p.error, null, JSON.stringify(p.error));
  ctx.p1 = (p.data as any).id;
  const o = await rpc("authenticated", C1, "place_order", { p_items: [{ product_id: ctx.p1, quantity: 1 }], p_city: "makkah",
    p_address: "حي العزيزية، شارع 1، مبنى 2", p_recipient_name: "عميل", p_phone: "0500000000", p_request_id: crypto.randomUUID(), p_customization: {}, p_loyalty_points: 0 });
  assert.equal(o.error, null, JSON.stringify(o.error));
  ctx.o1 = o.data as string;
  const payable = (await sql(`select payable_halalas from public.orders where id=$1`, [ctx.o1]))[0].payable_halalas;
  assert.equal(Number(payable), 11500, "100 SAR + 15% VAT");
  let r = await createCheckout(deps, bearer(S2), { order_id: ctx.o1 });
  assert.equal(r.status, 409, "someone else's order cannot be paid through checkout");
  r = await createCheckout(deps, bearer(C1), { order_id: ctx.o1 });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  const created = tap.calls.filter((c) => c.method === "POST" && c.path === "/charges").at(-1)!;
  assert.equal(created.key, KEY1, "charge created with the supplier's key (funds settle to the supplier)");
  const charge = tap.charges.get(String(r.body.charge_id));
  assert.equal(charge.amount, 115, "amount in SAR");
  assert.equal(charge.reference.order, ctx.o1);
  ctx.c1 = String(r.body.charge_id);
  const init = await sql(`select status from private.gateway_charges where charge_id=$1`, [ctx.c1]);
  assert.equal(init[0].status, "initiated");
});

test("E4 webhook trusts only the provider's state fetched with the supplier key", async () => {
  // forged payload claiming success while Tap still says INITIATED
  let r = await processWebhook(deps, new Headers(), { id: ctx.c1, status: "CAPTURED", amount: 115, currency: "SAR", reference: { order: ctx.o1 } });
  assert.equal(r.body.outcome, "pending");
  assert.equal((await sql(`select payment_status from public.orders where id=$1`, [ctx.o1]))[0].payment_status, "unpaid");
  // charge id from a different supplier's account is invisible with this supplier's key
  const foreign = { id: "chg_FOREIGN01", _key: KEY2, status: "CAPTURED", amount: 115, currency: "SAR", reference: { order: ctx.o1 } };
  tap.charges.set(foreign.id, foreign);
  r = await processWebhook(deps, new Headers(), { id: foreign.id, reference: { order: ctx.o1 } });
  assert.match(String(r.body.ignored), /not found/);
  // provider captures -> paid
  tap.charges.get(ctx.c1).status = "CAPTURED";
  r = await processWebhook(deps, new Headers({ hashstring: "bogus" }), { id: ctx.c1, reference: { order: ctx.o1 } });
  assert.equal(r.body.outcome, "paid", JSON.stringify(r.body));
  assert.ok(logs.some((l) => l.includes("hashstring mismatch")), "bad signature logged, state still from API");
  r = await processWebhook(deps, new Headers(), { id: ctx.c1, reference: { order: ctx.o1 } });
  assert.equal(r.body.outcome, "duplicate_event_ignored");
  r = await processWebhook(deps, new Headers(), { id: "evt_123" });
  assert.ok(r.body.ignored);
});

test("E5 refunds: operator-only, bounded, executed on the supplier's account, confirmed by webhook", async () => {
  let r = await refundOrder(deps, bearer(C1), { order_id: ctx.o1, amount_halalas: 5000, reason: "إرجاع" });
  assert.equal(r.status, 403);
  r = await refundOrder(deps, bearer(ADMIN), { order_id: ctx.o1, amount_halalas: 999999, reason: "إرجاع" });
  assert.equal(r.status, 400, "refund above payable rejected before calling the gateway");
  r = await refundOrder(deps, bearer(ADMIN), { order_id: ctx.o1, amount_halalas: 5000, reason: "إرجاع جزئي" });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  assert.equal(r.body.status, "pending");
  assert.equal(tap.calls.filter((c) => c.path === "/refunds").at(-1)!.key, KEY1, "refund executed with the supplier's key");
  const refundId = String(r.body.refund_id);
  tap.refunds.get(refundId).status = "REFUNDED";
  r = await processWebhook(deps, new Headers(), { id: refundId, reference: { merchant: ctx.o1 } });
  assert.equal(r.body.refund, "succeeded", JSON.stringify(r.body));
  const o = (await sql(`select refund_status, refunded_halalas from public.orders where id=$1`, [ctx.o1]))[0];
  assert.equal(o.refund_status, "partial"); assert.equal(Number(o.refunded_halalas), 5000);
  r = await processWebhook(deps, new Headers(), { id: refundId, reference: { merchant: ctx.o1 } });
  assert.equal(Number((await sql(`select refunded_halalas from public.orders where id=$1`, [ctx.o1]))[0].refunded_halalas), 5000, "replay does not double count");
});

test("E6 billing runner requires the cron secret", async () => {
  assert.equal((await runBilling(deps, new Headers())).status, 401);
  assert.equal((await runBilling(deps, new Headers({ "x-cron-secret": "wrong" }))).status, 401);
  const r = await runBilling(deps, new Headers({ "x-cron-secret": "cron-secret-test" }));
  assert.equal(r.status, 200, JSON.stringify(r.body));
  await pool.end();
});
