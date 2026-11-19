// Finance job handlers. Pure functions over injected dependencies so the same code runs in
// Supabase Edge Functions (Deno) and in unit tests (Node). Payments are made by customers
// directly to suppliers (supplier payment link or cash on delivery); there is no gateway here.

export interface Deps {
  env: { CRON_SECRET?: string };
  serviceRpc(fn: string, args: Record<string, unknown>): Promise<{ data: any; error: any }>;
  log(msg: string, extra?: unknown): void;
}
export interface Result { status: number; body: Record<string, unknown> }

const ok = (body: Record<string, unknown>, status = 200): Result => ({ status, body });
const fail = (status: number, error: string): Result => ({ status, body: { error } });

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

// Daily billing runner: closes the previous month, marks overdue invoices, sends reminders.
export async function runBilling(d: Deps, headers: Headers): Promise<Result> {
  const given = headers.get("x-cron-secret") ?? "";
  if (!d.env.CRON_SECRET || !timingSafeEqual(given, d.env.CRON_SECRET)) return fail(401, "unauthorized");
  const r = await d.serviceRpc("run_billing_jobs", {});
  if (r.error) return fail(500, String(r.error?.message ?? r.error).slice(0, 300));
  return ok({ result: r.data });
}
