# Setup Apps

This project includes setup apps for different operating systems.

## Windows

Use the GUI app:

```text
windows-setup-app\CloudflareV2RaySetup.exe
```

## macOS and Linux

Use the terminal setup app from the release archive:

```bash
./cloudflare-sub-setup
```

Useful options:

```bash
./cloudflare-sub-setup --password "your-admin-password"
./cloudflare-sub-setup --reset-password
./cloudflare-sub-setup --list-pages
./cloudflare-sub-setup --delete-page old-project-name
```

If `--password` is omitted, the app deploys everything and clears the stored panel password. The first visit to `/admin` asks you to create the password in the browser.

All versions require Node.js and use Wrangler OAuth for Cloudflare authorization.
