# Cloudflare Setup Guide

This guide deploys this project to Cloudflare Pages and connects it to Cloudflare KV.

You need:

- A Cloudflare account
- Node.js installed on your PC
- This project folder: `D:\clouflare subscription generator panel`
- One strong admin password
- One long random subscription token for your public `/sub/...` URL

## Easiest Option: Windows Setup App

If you do not want to run every command manually, open this app:

```text
D:\clouflare subscription generator panel\windows-setup-app\CloudflareV2RaySetup.exe
```

Then:

1. Enter your admin password if you want the setup app to set it, or leave it empty if you want `/admin` to ask you to create it.
2. Click **Run All**.
3. Log in to Cloudflare when the browser opens.
4. Wait for deployment to finish.
5. Copy the admin panel URL shown by the app.
6. If you left the password empty, open `/admin` and create the password there.

If one step fails, you can use the individual buttons in the app to continue from that step.

Cloudflare still requires browser authorization. The app starts that authorization with Wrangler, and after you approve it, the app creates KV, creates the Pages project, sets the password secret, deploys the project, and gives you the admin link.

If `SUB_KV` or `SUB_KV_preview` already exists, the app reuses it. It also loads existing KV IDs from `wrangler.toml` when it opens.

If the admin panel opens but the password says **Unauthorized**:

1. Open the setup app again.
2. Click **Reset Panel Password**.
3. Open `/admin`.
4. Create a new password in the browser.

Always use the stable admin URL:

```text
https://v2ray-subscription-manager.pages.dev/admin
```

Do not use older deployment URLs such as:

```text
https://e8cbb4bd.v2ray-subscription-manager.pages.dev/admin
```

Old deployment URLs can keep older environment values.

To remove old Cloudflare Pages projects, use the **Cloudflare Pages Projects** panel in the app:

1. Click **List Pages**.
2. Check one or more projects.
3. Click **Delete Selected**.

Fallback launcher if the EXE does not open:

```text
D:\clouflare subscription generator panel\windows-setup-app\Run Cloudflare Setup App.cmd
```

## 1. Open PowerShell In The Project Folder

Open PowerShell and run:

```powershell
cd "D:\clouflare subscription generator panel"
```

## 2. Install Project Tools

Run:

```powershell
npm install
```

## 3. Login To Cloudflare

Run:

```powershell
npx wrangler login
```

Your browser will open. Log in to Cloudflare and approve Wrangler.

## 4. Create Cloudflare KV Storage

Run these two commands:

```powershell
npx wrangler kv namespace create SUB_KV
npx wrangler kv namespace create SUB_KV --preview
```

Cloudflare will print output similar to this:

```toml
[[kv_namespaces]]
binding = "SUB_KV"
id = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

The preview command prints a different ID.

Open `wrangler.toml` and replace:

```toml
id = "replace_with_production_kv_namespace_id"
preview_id = "replace_with_preview_kv_namespace_id"
```

with the real IDs Cloudflare gave you.

Example:

```toml
[[kv_namespaces]]
binding = "SUB_KV"
id = "abc123productionid"
preview_id = "abc123previewid"
```

Do not change the binding name. It must stay:

```toml
binding = "SUB_KV"
```

## 5. Create The Cloudflare Pages Project

Run:

```powershell
npx wrangler pages project create v2ray-subscription-manager --production-branch main
```

If Cloudflare says the project already exists, that is fine. Continue to the next step.

## 6. Add Your Admin Password Secret

Run:

```powershell
npx wrangler pages secret put ADMIN_PASSWORD --project-name v2ray-subscription-manager
```

Wrangler will ask for the secret value. Paste your admin password and press Enter.

Use a strong password, for example a long random phrase. Do not put this password in `wrangler.toml`.

## 7. Deploy The Project

Run:

```powershell
npm run deploy
```

At the end, Wrangler will show your Pages URL. It will look like:

```text
https://v2ray-subscription-manager.pages.dev
```

## 8. Bind KV In The Cloudflare Dashboard If Needed

If the admin page opens but saving configs fails, manually check the KV binding:

1. Go to the Cloudflare dashboard.
2. Open **Workers & Pages**.
3. Select **v2ray-subscription-manager**.
4. Go to **Settings**.
5. Open **Bindings**.
6. Add a **KV namespace binding**.
7. Set variable name to:

   ```text
   SUB_KV
   ```

8. Select the KV namespace you created.
9. Save.
10. Redeploy:

   ```powershell
   npm run deploy
   ```

## 9. Open The Admin Panel

Open:

```text
https://v2ray-subscription-manager.pages.dev/admin
```

Log in with the admin password you saved in step 6.

## 10. Create Your Subscription Token

Inside the admin panel:

1. Find **Subscription Token**.
2. Enter a long random token.
3. Click **Save Token**.

Example token:

```text
my-private-token-9f42d891b8a14f3c
```

Your subscription URL will be:

```text
https://v2ray-subscription-manager.pages.dev/sub/my-private-token-9f42d891b8a14f3c
```

Base64 version:

```text
https://v2ray-subscription-manager.pages.dev/sub/my-private-token-9f42d891b8a14f3c?base64=1
```

## 11. Add Config Links

In the admin panel, add links like:

```text
vless://...
vmess://...
trojan://...
ss://...
hysteria2://...
hy2://...
```

Only enabled configs appear in the public subscription output.

## 12. Update Later

After changing files, redeploy with:

```powershell
npm run deploy
```

## Common Problems

### Admin says unauthorized

Your password is wrong or the `ADMIN_PASSWORD` secret was not set.

Run again:

```powershell
npx wrangler pages secret put ADMIN_PASSWORD --project-name v2ray-subscription-manager
```

Then redeploy:

```powershell
npm run deploy
```

### Saving configs fails

The `SUB_KV` binding is missing or connected to the wrong namespace. Check step 8.

### Subscription URL says not found

The token in the URL does not match the token saved in the admin panel.

### Base64 output looks like random text

That is expected. Clients that need Base64 subscriptions can use the `?base64=1` URL.

## Quick Command Summary

```powershell
cd "D:\clouflare subscription generator panel"
npm install
npx wrangler login
npx wrangler kv namespace create SUB_KV
npx wrangler kv namespace create SUB_KV --preview
# Edit wrangler.toml with the KV IDs.
npx wrangler pages project create v2ray-subscription-manager --production-branch main
npx wrangler pages secret put ADMIN_PASSWORD --project-name v2ray-subscription-manager
npm run deploy
```
