import { error, text } from "../_lib/responses.js";
import { getConfigs, getSettings } from "../_lib/store.js";

function toBase64(value) {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

export async function onRequestGet(context) {
  let settings;
  let configs;
  try {
    settings = await getSettings(context.env);
    configs = await getConfigs(context.env);
  } catch (err) {
    return error(err.message || "Subscription storage is not configured", 500);
  }

  const token = context.params.token;
  if (!settings.token || token !== settings.token) {
    return error("Not found", 404);
  }

  const body = configs
    .filter((item) => item.enabled)
    .map((item) => item.link)
    .join("\n");

  const output = new URL(context.request.url).searchParams.get("base64") === "1"
    ? toBase64(body)
    : body;

  return text(output);
}

export function onRequest() {
  return text("Method not allowed", { status: 405 });
}
