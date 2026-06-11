import { error, json } from "../../../_lib/responses.js";
import { requireAdmin } from "../../../_lib/auth.js";
import { getConfigs, saveConfigs, validateConfigInput } from "../../../_lib/store.js";

export async function onRequestGet(context) {
  const authError = await requireAdmin(context);
  if (authError) return authError;

  try {
    const configs = await getConfigs(context.env);
    configs.sort((a, b) => b.created_at.localeCompare(a.created_at));
    return json({ configs });
  } catch (err) {
    return error(err.message || "Could not load configs", 500);
  }
}

export async function onRequestPost(context) {
  const authError = await requireAdmin(context);
  if (authError) return authError;

  const input = await context.request.json().catch(() => null);
  if (!input) return error("Invalid JSON");

  const result = validateConfigInput(input);
  if (result.error) return error(result.error);

  try {
    const configs = await getConfigs(context.env);
    configs.unshift(result.config);
    await saveConfigs(context.env, configs);
    return json({ config: result.config }, { status: 201 });
  } catch (err) {
    return error(err.message || "Could not save config", 500);
  }
}

export function onRequest() {
  return json({ error: "Method not allowed" }, { status: 405 });
}
