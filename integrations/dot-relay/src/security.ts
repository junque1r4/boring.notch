// Modified for Boring Notch Agents, 2026-10-11. GPL-3.0-only.
export const USER_LIMIT = 8192;
export const REPLY_LIMIT = 65536;
export const RETENTION_MS = 7 * 86400000;
export const SUBSCRIPTION_TTL_MS = 24 * 3600000;
export const OWNER_ID = "39351332";
export const NATIVE_REDIRECT = "boringnotch-agents://oauth/callback";
export const EVENT_NAME = "notch.message.created";
export const SCOPES = ["notch:send", "notch:read", "notch:context", "notch:reply", "notch:subscribe", "offline_access"];
export class RelayError extends Error {
  constructor(public code: string, public status = 400) { super(code); }
}
export function uuid(value: unknown): string {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) throw new RelayError("invalid_message_id");
  return value.toLowerCase();
}
export function boundedText(value: unknown, limit: number): string {
  if (typeof value !== "string" || !value.trim() || new TextEncoder().encode(value).length > limit) throw new RelayError("invalid_text");
  return value;
}
export function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new RelayError("invalid_object");
  return value as Record<string, unknown>;
}
export async function readJSON(request: Request, limit = 131072): Promise<Record<string, unknown>> {
  if (!request.headers.get("content-type")?.startsWith("application/json")) throw new RelayError("json_required", 415);
  const declared = Number(request.headers.get("content-length"));
  if (declared > limit) throw new RelayError("payload_too_large", 413);
  const reader = request.body?.getReader();
  if (!reader) throw new RelayError("body_required");
  const parts: Uint8Array[] = []; let length = 0;
  try {
    while (true) {
      const item = await reader.read(); if (item.done) break;
      length += item.value.length;
      if (length > limit) { await reader.cancel(); throw new RelayError("payload_too_large", 413); }
      parts.push(item.value);
    }
    const bytes = new Uint8Array(length); let offset = 0;
    for (const part of parts) { bytes.set(part, offset); offset += part.length; }
    return object(JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes)));
  } catch (error) {
    if (error instanceof RelayError) throw error;
    throw new RelayError("invalid_json");
  }
}
export function b64(bytes: Uint8Array): string { return btoa(String.fromCharCode(...bytes)); }
export function unb64(value: string): Uint8Array {
  try { return Uint8Array.from(atob(value), char => char.charCodeAt(0)); } catch { throw new RelayError("invalid_secret"); }
}
export function signingKey(secret: unknown): Uint8Array {
  if (typeof secret !== "string" || !secret.startsWith("whsec_")) throw new RelayError("invalid_secret");
  const key = unb64(secret.slice(6));
  if (key.length < 24 || key.length > 64) throw new RelayError("invalid_secret");
  return key;
}
export async function digest(value: string): Promise<string> {
  return Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)))).map(byte => byte.toString(16).padStart(2, "0")).join("");
}
export async function equal(a: string, b: string): Promise<boolean> {
  const key = await crypto.subtle.importKey("raw", new Uint8Array(32), {name:"HMAC",hash:"SHA-256"}, false, ["sign","verify"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(a));
  return crypto.subtle.verify("HMAC", key, signature, new TextEncoder().encode(b));
}
export async function signedHeaders(secret: string, eventId: string, body: string, subscriptionId: string, now = Date.now()): Promise<Headers> {
  const timestamp = String(Math.floor(now / 1000));
  const key = await crypto.subtle.importKey("raw", signingKey(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signed = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${eventId}.${timestamp}.${body}`)));
  return new Headers({"Content-Type":"application/json","webhook-id":eventId,"webhook-timestamp":timestamp,"webhook-signature":`v1,${b64(signed)}`,"X-MCP-Subscription-Id":subscriptionId});
}
export function callbackURL(value: unknown, allowedOrigins: string): URL {
  if (typeof value !== "string" || value.length > 2048) throw new RelayError("invalid_callback");
  let url: URL; try { url = new URL(value); } catch { throw new RelayError("invalid_callback"); }
  if (url.protocol !== "https:" || url.username || url.password || url.hash || (url.port && url.port !== "443")) throw new RelayError("invalid_callback");
  const allow = allowedOrigins.split(",").map(origin => origin.trim()).filter(Boolean);
  if (!allow.includes(url.origin)) throw new RelayError("callback_origin_not_allowed");
  // Exact operator-approved public ChatGPT origins only. The Worker also enables
  // global_fetch_strictly_public; redirects are rejected on every request.
  if (/^(localhost|.*\.localhost|.*\.local)$/.test(url.hostname) || /^\[|^[\d.]+$/.test(url.hostname)) throw new RelayError("invalid_callback");
  return url;
}
export async function encrypt(value: unknown, secret: string, context: string): Promise<string> {
  const raw = unb64(secret); if (raw.length !== 32) throw new RelayError("relay_not_configured",503);
  const key = await crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt"]);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = await crypto.subtle.encrypt({name:"AES-GCM",iv,additionalData:new TextEncoder().encode(context)}, key, new TextEncoder().encode(JSON.stringify(value)));
  return `${b64(iv)}.${b64(new Uint8Array(data))}`;
}
export async function decrypt<T>(value: string, secret: string, context: string): Promise<T> {
  const [iv, data] = value.split(".");
  const key = await crypto.subtle.importKey("raw", unb64(secret), "AES-GCM", false, ["decrypt"]);
  const plain = await crypto.subtle.decrypt({name:"AES-GCM",iv:unb64(iv),additionalData:new TextEncoder().encode(context)}, key, unb64(data));
  return JSON.parse(new TextDecoder().decode(plain)) as T;
}
export function retryDelay(attempt: number): number { return Math.min(1000 * 2 ** attempt, 60000); }

export async function readForm(request:Request,limit=4096):Promise<URLSearchParams> {
  if(!request.headers.get("content-type")?.startsWith("application/x-www-form-urlencoded"))throw new RelayError("form_required",415);
  if(Number(request.headers.get("content-length"))>limit)throw new RelayError("payload_too_large",413);
  const reader=request.body?.getReader();if(!reader)throw new RelayError("body_required");
  const parts:Uint8Array[]=[];let length=0;
  while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>limit){await reader.cancel();throw new RelayError("payload_too_large",413);}parts.push(value);}
  const bytes=new Uint8Array(length);let offset=0;for(const part of parts){bytes.set(part,offset);offset+=part.length;}
  try{return new URLSearchParams(new TextDecoder("utf-8",{fatal:true,ignoreBOM:false}).decode(bytes));}catch{throw new RelayError("invalid_form");}
}

export async function textFingerprint(value:string,secret:string):Promise<string> {
 const key=await crypto.subtle.importKey("raw",unb64(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
 return b64(new Uint8Array(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(value))));
}
