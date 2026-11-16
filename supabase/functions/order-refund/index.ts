// Operator-initiated refund executed on the supplier's Tap account.
import { handle } from "../_shared/finance/deno.ts";
import { refundOrder } from "../_shared/finance/handlers.ts";
Deno.serve((req) => handle(req, async (d, r) => refundOrder(d, r.headers.get("Authorization") ?? "", await r.json().catch(() => ({})))));
