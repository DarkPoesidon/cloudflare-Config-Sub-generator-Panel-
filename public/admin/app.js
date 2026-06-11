const state = {
  password: "",
  configured: true,
  configs: [],
  settings: { token: "" }
};

const loginPanel = document.getElementById("loginPanel");
const loginTitle = document.getElementById("loginTitle");
const loginHelp = document.getElementById("loginHelp");
const adminPanel = document.getElementById("adminPanel");
const loginForm = document.getElementById("loginForm");
const passwordLabel = document.getElementById("passwordLabel");
const passwordInput = document.getElementById("passwordInput");
const logoutBtn = document.getElementById("logoutBtn");
const settingsForm = document.getElementById("settingsForm");
const tokenInput = document.getElementById("tokenInput");
const subUrl = document.getElementById("subUrl");
const copySubUrlBtn = document.getElementById("copySubUrlBtn");
const configForm = document.getElementById("configForm");
const configId = document.getElementById("configId");
const nameInput = document.getElementById("nameInput");
const linkInput = document.getElementById("linkInput");
const enabledInput = document.getElementById("enabledInput");
const formTitle = document.getElementById("formTitle");
const cancelEditBtn = document.getElementById("cancelEditBtn");
const refreshBtn = document.getElementById("refreshBtn");
const configList = document.getElementById("configList");
const countText = document.getElementById("countText");
const toast = document.getElementById("toast");

function showToast(message, isError = false) {
  toast.textContent = message;
  toast.classList.toggle("error", isError);
  toast.classList.remove("hidden");
  window.setTimeout(() => toast.classList.add("hidden"), 2600);
}

function setLoggedIn(loggedIn) {
  loginPanel.classList.toggle("hidden", loggedIn);
  adminPanel.classList.toggle("hidden", !loggedIn);
  logoutBtn.classList.toggle("hidden", !loggedIn);
}

function renderLoginMode() {
  if (state.configured) {
    loginTitle.textContent = "Admin Login";
    loginHelp.textContent = "Enter your admin password.";
    passwordLabel.textContent = "Admin password";
    loginForm.querySelector("button").textContent = "Log in";
    passwordInput.autocomplete = "current-password";
  } else {
    loginTitle.textContent = "Create Admin Password";
    loginHelp.textContent = "First setup: choose the password you will use for future logins.";
    passwordLabel.textContent = "New admin password";
    loginForm.querySelector("button").textContent = "Save password";
    passwordInput.autocomplete = "new-password";
  }
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    ...options,
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {})
    }
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    if (res.status === 401) {
      state.password = "";
      setLoggedIn(false);
      passwordInput.value = "";
      passwordInput.focus();
    }
    throw new Error(data.error || `Request failed with ${res.status}`);
  }
  return data;
}

async function loadAll() {
  const [configsData, settingsData] = await Promise.all([
    api("/api/admin/configs"),
    api("/api/admin/settings")
  ]);
  state.configs = configsData.configs;
  state.settings = settingsData.settings;
  renderSettings();
  renderConfigs();
}

function renderSettings() {
  tokenInput.value = state.settings.token || "";
  if (!state.settings.token) {
    subUrl.textContent = "Set a token first";
    return;
  }
  const url = `${window.location.origin}/sub/${encodeURIComponent(state.settings.token)}`;
  subUrl.textContent = url;
}

function renderConfigs() {
  const enabledCount = state.configs.filter((item) => item.enabled).length;
  countText.textContent = `${state.configs.length} total, ${enabledCount} enabled`;
  configList.innerHTML = "";

  if (state.configs.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty";
    empty.textContent = "No configs yet.";
    configList.appendChild(empty);
    return;
  }

  for (const item of state.configs) {
    const row = document.createElement("article");
    row.className = "configItem";

    const meta = document.createElement("div");
    meta.className = "configMeta";
    meta.innerHTML = `
      <strong></strong>
      <span>${item.enabled ? "Enabled" : "Disabled"} - Created ${new Date(item.created_at).toLocaleString()}</span>
      <code></code>
    `;
    meta.querySelector("strong").textContent = item.name;
    meta.querySelector("code").textContent = item.link;

    const actions = document.createElement("div");
    actions.className = "actions";

    const edit = document.createElement("button");
    edit.type = "button";
    edit.className = "ghost";
    edit.textContent = "Edit";
    edit.addEventListener("click", () => startEdit(item));

    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "danger";
    remove.textContent = "Delete";
    remove.addEventListener("click", () => deleteConfig(item.id));

    actions.append(edit, remove);
    row.append(meta, actions);
    configList.appendChild(row);
  }
}

function startEdit(item) {
  configId.value = item.id;
  nameInput.value = item.name;
  linkInput.value = item.link;
  enabledInput.checked = item.enabled;
  formTitle.textContent = "Edit Config";
  cancelEditBtn.classList.remove("hidden");
  nameInput.focus();
}

function resetConfigForm() {
  configId.value = "";
  nameInput.value = "";
  linkInput.value = "";
  enabledInput.checked = true;
  formTitle.textContent = "Add Config";
  cancelEditBtn.classList.add("hidden");
}

async function deleteConfig(id) {
  if (!confirm("Delete this config?")) return;
  await api(`/api/admin/configs/${encodeURIComponent(id)}`, { method: "DELETE" });
  showToast("Config deleted");
  await loadAll();
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const password = passwordInput.value.trim();
  if (!password) {
    showToast("Password is required", true);
    passwordInput.focus();
    return;
  }
  try {
    if (state.configured) {
      await api("/api/admin/login", {
        method: "POST",
        body: JSON.stringify({ password })
      });
    } else {
      await api("/api/admin/login", {
        method: "PUT",
        body: JSON.stringify({ password })
      });
      state.configured = true;
      renderLoginMode();
    }
    passwordInput.value = "";
    setLoggedIn(true);
    await loadAll();
  } catch (error) {
    state.password = "";
    showToast(error.message, true);
  }
});

logoutBtn.addEventListener("click", async () => {
  await fetch("/api/admin/login", { method: "DELETE", credentials: "same-origin" }).catch(() => {});
  state.password = "";
  setLoggedIn(false);
});

settingsForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const token = tokenInput.value.trim();
  const data = await api("/api/admin/settings", {
    method: "PUT",
    body: JSON.stringify({ token })
  });
  state.settings = data.settings;
  renderSettings();
  showToast("Token saved");
});

copySubUrlBtn.addEventListener("click", async () => {
  if (!state.settings.token) return;
  await navigator.clipboard.writeText(subUrl.textContent);
  showToast("Subscription URL copied");
});

configForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const id = configId.value;
  const payload = {
    name: nameInput.value.trim(),
    link: linkInput.value.trim(),
    enabled: enabledInput.checked
  };
  const path = id ? `/api/admin/configs/${encodeURIComponent(id)}` : "/api/admin/configs";
  const method = id ? "PUT" : "POST";
  await api(path, { method, body: JSON.stringify(payload) });
  showToast(id ? "Config updated" : "Config added");
  resetConfigForm();
  await loadAll();
});

cancelEditBtn.addEventListener("click", resetConfigForm);
refreshBtn.addEventListener("click", () => loadAll().catch((error) => showToast(error.message, true)));

setLoggedIn(true);
api("/api/admin/login")
  .then((data) => {
    state.configured = data.configured;
    renderLoginMode();
    if (!state.configured) {
      setLoggedIn(false);
      return null;
    }
    return loadAll();
  })
  .catch(() => {
    renderLoginMode();
    setLoggedIn(false);
  });
