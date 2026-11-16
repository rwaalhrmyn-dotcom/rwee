// Supplier connects/updates its own Tap account. The key is verified with Tap, sealed
// (AES-GCM) and stored as ciphertext; it is never returned or logged.
import { handle } from "../_shared/finance/deno.ts";
import { connectGateway } from "../_shared/finance/handlers.ts";
Deno.serve((req) => handle(req, async (d, r) => connectGateway(d, r.headers.get("Authorization") ?? "", await r.json().catch(() => ({})))));
