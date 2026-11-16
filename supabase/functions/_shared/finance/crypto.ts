// AES-256-GCM sealing of supplier gateway secret keys. The 32-byte key lives only in
// the Edge Function environment (GATEWAY_SECRETS_KEY, base64); the database stores
// ciphertext + IV and never sees plaintext keys. Works in Deno and Node (Web Crypto).

const enc = new TextEncoder();
const dec = new TextDecoder();

export function b64encode(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

export function b64decode(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function importKey(keyB64: string): Promise<CryptoKey> {
  if (!keyB64) throw new Error("GATEWAY_SECRETS_KEY is not configured");
  const raw = b64decode(keyB64);
  if (raw.length !== 32) throw new Error("GATEWAY_SECRETS_KEY must be 32 bytes (base64)");
  return await crypto.subtle.importKey("raw", raw, { name: "AES-GCM" }, false, ["encrypt", "decrypt"]);
}

export async function sealSecret(plaintext: string, keyB64: string, aad: string): Promise<{ ciphertext: string; iv: string }> {
  const key = await importKey(keyB64);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: "AES-GCM", iv, additionalData: enc.encode(aad) }, key, enc.encode(plaintext));
  return { ciphertext: b64encode(new Uint8Array(ct)), iv: b64encode(iv) };
}

// aad binds the ciphertext to its supplier: a blob copied to another supplier will not decrypt.
export async function openSecret(ciphertext: string, iv: string, keyB64: string, aad: string): Promise<string> {
  const key = await importKey(keyB64);
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: b64decode(iv), additionalData: enc.encode(aad) }, key, b64decode(ciphertext));
  return dec.decode(pt);
}

export async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(message)));
  return Array.from(sig).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}
