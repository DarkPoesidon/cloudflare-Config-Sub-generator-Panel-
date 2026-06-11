import { error } from "./responses.js";
import { getAdminAuth } from "./store.js";

const SESSION_COOKIE = "admin_session";
const SESSION_TTL_SECONDS = 7 * 24 * 60 * 60;
const LEGACY_SESSION_SECRET = "legacy-admin-secret";

function constantTimeEqual(a, b) {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  const length = Math.max(left.length, right.length);
  let diff = left.length ^ right.length;

  for (let i = 0; i < length; i += 1) {
    diff |= (left[i] || 0) ^ (right[i] || 0);
  }

  return diff === 0;
}

function base64UrlEncode(value) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64UrlDecode(value) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

async function hmac(secret, value) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return base64UrlEncode(new Uint8Array(signature));
}

async function sha256(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return base64UrlEncode(new Uint8Array(digest));
}

async function getSessionSecret(context) {
  const auth = await getAdminAuth(context.env).catch(() => null);
  if (auth?.password_hash) {
    return auth.password_hash;
  }
  return context.env.ADMIN_PASSWORD || LEGACY_SESSION_SECRET;
}

function getCookie(request, name) {
  const cookie = request.headers.get("Cookie") || "";
  for (const part of cookie.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) {
      return rest.join("=");
    }
  }
  return "";
}

export async function verifyAdminPassword(context, supplied) {
  const auth = await getAdminAuth(context.env);
  const normalized = normalizePassword(supplied);
  if (auth?.password_hash) {
    const suppliedHash = await hashPassword(normalized, auth.salt || "");
    if (!constantTimeEqual(suppliedHash, auth.password_hash)) {
      return { ok: false, response: error("Unauthorized", 401) };
    }
    return { ok: true };
  }

  const legacyExpected = context.env.ADMIN_PASSWORD;
  if (!legacyExpected || !normalized || !constantTimeEqual(normalized, legacyExpected.trim())) {
    return { ok: false, response: error("Unauthorized", 401) };
  }

  return { ok: true };
}

export async function hashPassword(password, salt) {
  return sha256(`${salt}:${normalizePassword(password)}`);
}

export function normalizePassword(password) {
  return String(password || "").trim();
}

export function createSalt() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return base64UrlEncode(bytes);
}

export async function isAdminConfigured(context) {
  const auth = await getAdminAuth(context.env);
  return Boolean(auth?.password_hash);
}

export async function createSessionCookie(context, explicitSecret = "") {
  const payload = {
    exp: Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS
  };
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signature = await hmac(explicitSecret || await getSessionSecret(context), encodedPayload);
  const secure = new URL(context.request.url).protocol === "https:" ? "; Secure" : "";
  return `${SESSION_COOKIE}=${encodedPayload}.${signature}; Path=/; HttpOnly${secure}; SameSite=Strict; Max-Age=${SESSION_TTL_SECONDS}`;
}

export function clearSessionCookie(context) {
  const secure = new URL(context.request.url).protocol === "https:" ? "; Secure" : "";
  return `${SESSION_COOKIE}=; Path=/; HttpOnly${secure}; SameSite=Strict; Max-Age=0`;
}

async function verifySession(context) {
  const token = getCookie(context.request, SESSION_COOKIE);
  if (!token || !token.includes(".")) {
    return false;
  }

  const [payload, signature] = token.split(".");
  const expectedSignature = await hmac(await getSessionSecret(context), payload);
  if (!constantTimeEqual(signature || "", expectedSignature)) {
    return false;
  }

  try {
    const decoded = new TextDecoder().decode(base64UrlDecode(payload));
    const data = JSON.parse(decoded);
    return Number(data.exp || 0) > Math.floor(Date.now() / 1000);
  } catch {
    return false;
  }
}

export async function requireAdmin(context) {
  const supplied = context.request.headers.get("X-Admin-Password") || "";
  if (supplied && (await verifyAdminPassword(context, supplied)).ok) {
    return null;
  }

  if (await verifySession(context)) {
    return null;
  }

  return error("Unauthorized", 401);
}
