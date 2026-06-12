# V2Ray Subscription Manager

Cloudflare Pages + Functions project for managing raw V2Ray subscription links in Cloudflare KV.

## Features

- Static admin UI at `/admin`
- Password-protected admin API
- Cloudflare KV storage using binding `SUB_KV`
- Add, edit, delete, enable, and disable raw `vless://`, `vmess://`, `trojan://`, `ss://`, `hysteria2://`, and `hy2://` links
- Public subscription endpoint at `/sub/:token`
- Plain newline subscription output by default
- Optional Base64 output with `/sub/:token?base64=1`
- Stores config name, enabled status, raw link, and `created_at`
- No telemetry and no external database

## Local Development

1. Install dependencies:

   ```powershell
   npm install
   ```

2. Create local environment file:

   ```powershell
   Copy-Item .dev.vars.example .dev.vars
   ```

3. Edit `.dev.vars` and set a strong `ADMIN_PASSWORD`.

4. Start local Pages dev server:

   ```powershell
   npm run dev
   ```

5. Open:

   ```text
   http://localhost:8788/admin
   ```

## Cloudflare Deployment

## Setup Apps

Use the release assets for one-click or guided setup:

- `CloudflareV2RaySetup-Windows-GUI.zip` - Windows graphical setup app.
- `cloudflare-sub-setup-windows-x64-cli.zip` - Windows terminal setup app.
- `cloudflare-sub-setup-macos-arm64.zip` - macOS Apple Silicon terminal setup app.
- `cloudflare-sub-setup-macos-x64.zip` - macOS Intel terminal setup app.
- `cloudflare-sub-setup-linux-x64.zip` - Linux x64 terminal setup app.
- `cloudflare-sub-setup-linux-arm64.zip` - Linux ARM64 terminal setup app.

The terminal setup app supports:

```bash
./cloudflare-sub-setup --password "your-admin-password"
./cloudflare-sub-setup --reset-password
./cloudflare-sub-setup --list-pages
./cloudflare-sub-setup --delete-page old-project-name
```

If no password is provided, the setup app deploys the project and clears any stored admin password. The first `/admin` visit then asks you to create the password in the browser.

1. Log in to Cloudflare:

   ```powershell
   npx wrangler login
   ```

2. Create a KV namespace:

   ```powershell
   npx wrangler kv namespace create SUB_KV
   npx wrangler kv namespace create SUB_KV --preview
   ```

3. Copy the returned production `id` and preview `preview_id` into `wrangler.toml`.

4. Create the Pages project:

   ```powershell
   npx wrangler pages project create v2ray-subscription-manager --production-branch main
   ```

5. Set the admin password secret:

   ```powershell
   npx wrangler pages secret put ADMIN_PASSWORD --project-name v2ray-subscription-manager
   ```

6. Deploy:

   ```powershell
   npm run deploy
   ```

7. Visit:

   ```text
   https://your-pages-domain.pages.dev/admin
   ```

8. In the admin UI, set a subscription token. Your public subscription URL is:

   ```text
   https://your-pages-domain.pages.dev/sub/YOUR_TOKEN
   ```

   Base64 encoded output:

   ```text
   https://your-pages-domain.pages.dev/sub/YOUR_TOKEN?base64=1
   ```

## Security Notes

- Use a long random admin password.
- Use a long random subscription token.
- The admin password is never stored in KV. It is read from the Cloudflare Pages secret `ADMIN_PASSWORD`.
- Admin requests use the `X-Admin-Password` header. Always use HTTPS in production.
