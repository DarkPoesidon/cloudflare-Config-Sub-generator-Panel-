import { json } from "../../_lib/responses.js";
import { clearSessionCookie, createSalt, createSessionCookie, hashPassword, isAdminConfigured, normalizePassword, verifyAdminPassword } from "../../_lib/auth.js";
import { saveAdminAuth } from "../../_lib/store.js";

export async function onRequestGet(context) {
  return json({ configured: await isAdminConfigured(context) });
}

export async function onRequestPost(context) {
  const input = await context.request.json().catch(() => ({}));
  const supplied = normalizePassword(input.password || context.request.headers.get("X-Admin-Password") || "");
  const result = await verifyAdminPassword(context, supplied);
  if (!result.ok) return result.response;

  return json(
    { ok: true },
    { headers: { "Set-Cookie": await createSessionCookie(context) } }
  );
}

export async function onRequestPut(context) {
  const input = await context.request.json().catch(() => ({}));
  const password = normalizePassword(input.password || "");
  const configured = await isAdminConfigured(context);

  if (configured) {
    const current = String(input.current_password || "");
    const result = await verifyAdminPassword(context, current);
    if (!result.ok) return result.response;
  }

  if (password.length < 8 || password.length > 200) {
    return json({ error: "Password must be 8-200 characters" }, { status: 400 });
  }

  const salt = createSalt();
  const passwordHash = await hashPassword(password, salt);
  await saveAdminAuth(context.env, {
    salt,
    password_hash: passwordHash,
    created_at: new Date().toISOString()
  });

  return json(
    { ok: true, configured: true },
    { headers: { "Set-Cookie": await createSessionCookie(context, passwordHash) } }
  );
}

export async function onRequestDelete(context) {
  return json({ ok: true }, { headers: { "Set-Cookie": clearSessionCookie(context) } });
}

export function onRequest() {
  return json({ error: "Method not allowed" }, { status: 405 });
}
