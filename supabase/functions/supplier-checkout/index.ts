// Creates the payment page on the SUPPLIER's own Tap account for a single-supplier order.
import { handle } from "../_shared/finance/deno.ts";
import { createCheckout } from "../_shared/finance/handlers.ts";
Deno.serve((req) => handle(req, async (d, r) => createCheckout(d, r.headers.get("Authorization") ?? "", await r.json().catch(() => ({})))));
