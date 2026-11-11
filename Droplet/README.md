# AETHER Droplet

**AETHER** is a standalone 2FA verification code, sign-in link, and Bitwarden TOTP authenticator droplet built directly for [Droppy](https://getdroppy.app) using [DroppyKit](https://getdroppy.app/docs/droppykit) `v1.23.0+` — requiring no separate companion app or helper binary.

## What it does

- **All settings inside Droppy Settings (`SettingsPagesProviding`).** Configure Messages, Apple Mail, Google Gmail (OAuth PKCE or App Password), Microsoft Outlook / 365 (OAuth PKCE or IMAP), iCloud, Yahoo, IMAP servers, Bitwarden CLI TOTP import, Ignored Senders, "Not a Code" filters, Privacy & Touch ID lock, and AI agent MCP guardrails directly inside **Droppy → Settings → Droplets → AETHER** (never inside the notch).
- **Notch & Command Center presentation (`ShelfWidgetCompositionProviding`, `MenuBarExtraProviding`, `HUDPresenting`, `LiveActivityProviding`).** Displays AETHER in Droppy's Notch Shelf Grid and Command Center to inspect, search, copy, and open recent verification codes, sign-in links, and pinned Bitwarden TOTP secrets, while presenting arrival HUD strips and Droppy notification banners.
- **Native Droppy MCP tools (`MCPToolProviding`).** Exposes `get_code`, `get_status`, and `list_recent_services` through Droppy's built-in MCP server with Touch ID confirmation, DMARC alignment checks, 20/hr rule rate limiting, and 3-denial shutoff.
- **Privacy by design.** Codes remain in memory (never written to disk), pasteboard copies include local-only/concealed hints and optional 90-second auto-clear, Keychain secrets live under `app.getdroppy.droplet.aether`, and screen-capture hiding uses scoped `NSWindow.sharingType = .none` protection while unlocked code panels are visible.

## Setup & permissions

1. Install **`AETHER.droplet`** into `~/Library/Application Support/Droppy/Droplets/aether/AETHER.droplet` (or **Droppy Playground**).
2. Open **Droppy → Settings → Droplets → AETHER**, review its declared capabilities, and approve enabling AETHER.
3. Configure accounts and sources inside **Droppy → Settings → Droplets → AETHER → Sources & accounts**.
4. For **Messages** and **Apple Mail**, grant **Full Disk Access** to **Droppy** in macOS System Settings. For **Automatically Type Codes**, grant **Accessibility** permission to **Droppy**.

## Security & process boundary

`AETHER.droplet` is loaded dynamically (`dlopen`) inside `Droppy.app` (`iordv.Droppy`) and shares Droppy's process address space, entitlements, and security context (not an independent macOS App Sandbox). Sensitive actions inside AETHER (Touch ID / password unlock, agent code release approval, OAuth browser sign-in, and Bitwarden CLI import) remain explicitly user-gated.

## Credits

- Built on **AETHER**, which evolved from [CodeCatch](https://github.com/ugzv/CodeCatch) by Uros (GNU GPLv3).

## License

GPL-3.0. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
