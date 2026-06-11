# Windows Setup App

Run the EXE:

```text
windows-setup-app\CloudflareV2RaySetup.exe
```

Keep the EXE inside this project folder. It deploys the local `public`, `functions`, `package.json`, and `wrangler.toml` files.

The app will:

1. Check Node.js and npm.
2. Install project dependencies.
3. Reuse your existing Wrangler login, or open Cloudflare login if needed.
4. Create production and preview KV namespaces.
5. Save the KV IDs into `wrangler.toml`.
6. Create the Cloudflare Pages project.
7. Save `ADMIN_PASSWORD` as a Pages secret.
8. Deploy the project.
9. Show the admin panel URL.
10. Test whether the deployed admin password works.

Cloudflare login still requires your browser because Cloudflare controls that authentication step.
If you leave the setup app password field empty, the web panel will ask you to create a password on first visit.
The EXE embeds a fallback copy of the PowerShell setup script, but it uses the `CloudflareSetupApp.ps1` beside it when present so fixes can be applied without rebuilding the launcher.
If you leave the setup app password field empty and click **Set Password**, the app clears the stored panel password. The next visit to `/admin` will ask you to create a password in the browser.

If `/admin` says **Unauthorized** or you forgot the password, open the app and click:

1. **Reset Panel Password**
2. Open `/admin`
3. Create a new password in the browser

Use **Set Password** only when you want the setup app to set the panel password for you.
Use the stable admin URL: `https://v2ray-subscription-manager.pages.dev/admin`. Old deployment URLs like `https://abc12345.v2ray-subscription-manager.pages.dev/admin` can keep old secrets.

The app can also list and delete Cloudflare Pages projects from the **Cloudflare Pages Projects** panel.

If `SUB_KV` or `SUB_KV_preview` already exists, the app now reuses the existing namespaces automatically. It also loads saved KV IDs from `wrangler.toml` when it opens.

If the EXE does not open on your PC, use the fallback launcher:

```text
windows-setup-app\Run Cloudflare Setup App.cmd
```
