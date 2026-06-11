const CONFIGS_KEY = "configs";
const SETTINGS_KEY = "settings";
const ADMIN_AUTH_KEY = "admin_auth";
const ALLOWED_PROTOCOLS = ["vless://", "vmess://", "trojan://", "ss://"];

function kv(env) {
  if (!env.SUB_KV) {
    throw new Error("SUB_KV binding is not configured");
  }
  return env.SUB_KV;
}

export async function getConfigs(env) {
  const configs = (await kv(env).get(CONFIGS_KEY, "json")) || [];
  if (!Array.isArray(configs)) {
    throw new Error("Stored configs data is invalid");
  }
  return configs;
}

export async function saveConfigs(env, configs) {
  await kv(env).put(CONFIGS_KEY, JSON.stringify(configs));
}

export async function getSettings(env) {
  const settings = (await kv(env).get(SETTINGS_KEY, "json")) || { token: "" };
  if (!settings || typeof settings !== "object" || Array.isArray(settings)) {
    throw new Error("Stored settings data is invalid");
  }
  return { token: String(settings.token || "") };
}

export async function saveSettings(env, settings) {
  await kv(env).put(SETTINGS_KEY, JSON.stringify(settings));
}

export async function getAdminAuth(env) {
  return (await kv(env).get(ADMIN_AUTH_KEY, "json")) || null;
}

export async function saveAdminAuth(env, auth) {
  await kv(env).put(ADMIN_AUTH_KEY, JSON.stringify(auth));
}

export function validateConfigInput(input, existing = {}) {
  const name = String(input.name || "").trim();
  const link = String(input.link || "").trim();
  const enabled = Boolean(input.enabled);

  if (!name) {
    return { error: "Config name is required" };
  }

  if (name.length > 120) {
    return { error: "Config name must be 120 characters or less" };
  }

  if (!ALLOWED_PROTOCOLS.some((protocol) => link.startsWith(protocol))) {
    return { error: "Config link must start with vless://, vmess://, trojan://, or ss://" };
  }

  return {
    config: {
      id: existing.id || crypto.randomUUID(),
      name,
      link,
      enabled,
      created_at: existing.created_at || new Date().toISOString()
    }
  };
}

export function validateToken(input) {
  const token = String(input.token || "").trim();
  if (!/^[A-Za-z0-9._~-]{8,160}$/.test(token)) {
    return { error: "Token must be 8-160 characters and use only letters, numbers, dot, underscore, tilde, or hyphen" };
  }
  return { token };
}
