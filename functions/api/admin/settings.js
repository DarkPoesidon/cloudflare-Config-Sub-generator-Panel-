import { error, json } from "../../_lib/responses.js";
import { requireAdmin } from "../../_lib/auth.js";
import { getSettings, saveSettings, validateToken } from "../../_lib/store.js";

export async function onRequestGet(context) {
  const authError = await requireAdmin(context);
  if (authError) return authError;
  try {
    const settings = await getSettings(context.env);
    return json({ settings });
  } catch (err) {
    return error(err.message || "Could not load settings", 500);
  }
}

export async function onRequestPut(context) {
  const authError = await requireAdmin(context);
  if (authError) return authError;

  const input = await context.request.json().catch(() => null);
  if (!input) return error("Invalid JSON");

  const result = validateToken(input);
  if (result.error) return error(result.error);

  try {
    const settings = { token: result.token };
    await saveSettings(context.env, settings);
    return json({ settings });
  } catch (err) {
    return error(err.message || "Could not save settings", 500);
  }
}

export function onRequest() {
  return json({ error: "Method not allowed" }, { status: 405 });
}
