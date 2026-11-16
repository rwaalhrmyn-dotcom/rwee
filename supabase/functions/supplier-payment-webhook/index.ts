// Tap webhook for supplier-direct charges and refunds. Deployed with verify_jwt=false;
// every event is re-fetched from Tap with the supplier's key before anything is recorded.
import { handle } from "../_shared/finance/deno.ts";
import { processWebhook } from "../_shared/finance/handlers.ts";
Deno.serve((req) => handle(req, async (d, r) => processWebhook(d, r.headers, await r.json().catch(() => ({})))));
