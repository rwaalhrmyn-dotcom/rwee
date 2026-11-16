// Daily billing runner (month close, overdue, reminders) for projects without pg_cron.
// Call with header x-cron-secret: <CRON_SECRET>; deploy with verify_jwt=false.
import { handle } from "../_shared/finance/deno.ts";
import { runBilling } from "../_shared/finance/handlers.ts";
Deno.serve((req) => handle(req, async (d, r) => runBilling(d, r.headers)));
