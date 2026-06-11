import { error, json } from "../../../_lib/responses.js";
import { requireAdmin } from "../../../_lib/auth.js";
import { getConfigs, saveConfigs, validateConfigInput } from "../../../_lib/store.js";

export async function onRequestPut(context) {
  const authError = await requireAdmin(context);
  if (authError) return authError;

  const id = context.params.id;
  const input = await context.request.json().catch(() => null);
  if (!input) return error("Invalid JSON");

  try {
    const configs = await getConfigs(context.env);
    const index = configs.findIndex((item) => item.id === id);
    if (index === -1) return error("Config not found", 404);

    const result = validateConfigInput(input, configs[index]);
    if (result.error) return error(result.error);

    configs[index] = result.config;
    await saveConfigs(context.env, configs);
    return json({ config: result.config });
  } catch (err) {
    return error(err.message || "Could not update config", 500);
  }
}

export async function onRequestDelete(context) {
  const authError = await requireAdmin(context);
  if (authError) return authError;

  const id = context.params.id;
  try {
    const configs = await getConfigs(context.env);
    const next = configs.filter((item) => item.id !== id);
    if (next.length === configs.length) return error("Config not found", 404);

    await saveConfigs(context.env, next);
    return json({ ok: true });
  } catch (err) {
    return error(err.message || "Could not delete config", 500);
  }
}

export function onRequest() {
  return json({ error: "Method not allowed" }, { status: 405 });
}
