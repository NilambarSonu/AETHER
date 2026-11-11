# Architecture and Privacy Boundaries

**AETHER v2.0** provides a **standalone `AETHER.droplet`** built with **DroppyKit v1.23.0+**, unifying full verification-code detection, mail/messaging/TOTP adapters, privacy controls, Settings UI, Notch Shelf, Command Center, HUD/banners, and MCP tools inside one `.droplet` bundle. (Legacy host app target `CodeCatch`, `CodeCatchCLI`, `AetherCore`, and synchronized `AetherIPC` remain intact for compatibility and hardening tests.)

| Target / Bundle | Type | What it holds |
|---|---|---|
| `CodeCatchCore` (`Droplet/Sources/CodeCatchCore`) | Swift Package Target | Deterministic OTP extraction regex/fixture engine (704 test vectors), MIME parsing, `TOTP` implementation, service identity rules, Public Suffix List, and `VaultCode` parser. Zero UI, zero network, zero disk state. |
| `AetherEngine` (`Droplet/Sources/AetherEngine`) | Swift Package Target | Headless engine inside the droplet: `MessagesStore`, `AppleMailStore`, `GmailAPI`, `OutlookAPI`, `MailOAuth` (PKCE), `IMAPConnection`, `MailWatcher`, `APIWatcher`, `BitwardenCLI`, `AutoTyper`, `AetherAgentAccess`, `AgentSkillsManager`, `AetherClipboard`, `VaultSession`, `RecoveryInbox`, `AetherSecretStore` (`app.getdroppy.droplet.aether`). |
| `AETHER.droplet` (`Droplet/Sources/AETHER`) | Loadable Bundle (`.droplet`) | `AETHERPrincipal` & `AetherDroplet` dynamically loaded (`dlopen`) inside `Droppy.app` (`iordv.Droppy`, Team ID `NARHG44L48`). Shares Droppy's process address space and entitlements (not an independent OS sandbox). Implements `HUDPresenting`, `SettingsPagesProviding`, `ShelfWidgetCompositionProviding`, `MenuBarExtraProviding`, `LiveActivityProviding`, and `MCPToolProviding`. |
| `AetherIPC` / `AetherCore` | Synchronized IPC Targets | Length-prefixed binary framing, kernel audit token peer validator (`LOCAL_PEERTOKEN`), and UDS transport preserved in byte-for-byte parity. |

## Surface Separation

- **Droppy Settings (`SettingsPagesProviding`):** Root quick-actions pane, General notifications & auto-type, Sources & Accounts (Messages, Apple Mail, Google/Microsoft OAuth PKCE, IMAP editor + test connection), Bitwarden TOTP CLI import wizard, Ignored Senders, Not a Code rules, Privacy & History, Agents & MCP, Rules, Audit Log, and Unmatched Recent Emails recovery.
- **Notch & Command Center (`ShelfWidgetCompositionProviding`, `MenuBarExtraProviding`, `HUDPresenting`, `LiveActivityProviding`):** Strictly dedicated to code/link inspection, live expiry countdowns, hover-to-unblur, clipboard copy, sign-in link confirmation/opening, and transient approval banners — with one-tap deep links into Droppy Settings when configuration is needed.

## Received Messages & In-Memory Bounds

- `MessagesStore` reads `~/Library/Messages/chat.db` via SQLite read-only FSEvents/debounce (`LocalWatcher`); `AppleMailStore` reads `~/Library/Mail` read-only using Droppy's Full Disk Access permission.
- `MailWatcher` uses TLS IMAP with read-only `EXAMINE` / `BODY.PEEK` so inbox read flags remain untouched.
- `APIWatcher` polls Gmail REST and Microsoft Graph `Mail.Read` read-only endpoints with PKCE OAuth tokens stored in the login Keychain (`app.getdroppy.droplet.aether`).
- Received codes and `RecoveryInbox` (capped at 20 emails for 30 minutes) stay in memory only and are purged on expiration, dismissal, Clear History, or macOS lock when Clear on Lock is enabled.
- Droplet preferences use `host.preferences.userDefaults` (never `UserDefaults.standard`), with `unlockWithMac` stored strictly in Keychain (`UnlockPolicy`).

## Authentication, Clipboard & Capture Privacy

- `VaultSession` starts locked unless Unlock with Mac is explicitly opted into via authentication; sleep and screen lock cancel pending requests and lock imported Bitwarden TOTP entries.
- `AetherClipboard` writes with `NSPasteboard.ContentsOptions.currentHostOnly`, `org.nspasteboard.ConcealedType`, and `org.nspasteboard.TransientType`, clearing owned entries after 90 seconds if unchanged.
- `AetherScopedCaptureGuard` sets `window.sharingType = .none` only while a visible unlocked code or recovery view is mounted, restoring the hosting window's original sharing type immediately on unmount.

## AI Agent Guardrails (`MCPToolProviding`)

- Exposes `get_code`, `get_status`, and `list_recent_services` to AI coding apps connected to Droppy's native MCP server (`droplet_aether_*`).
- Enabling agent access, sign-in link release, and Allow All requires Touch ID / macOS authentication.
- `AetherAgentAccess` caps MCP waits at 55 seconds, requires DMARC alignment for email domain matching, never releases password-reset links or flagged lookalike URLs, caps auto-releases at 20 per hour, and shuts off automatically after 3 consecutive denials.
- `AgentSkillsManager` writes marked `SKILL.md` files into `~/.claude`, `~/.codex`, or `~/.cursor` using `O_NOFOLLOW` / `renamex_np` ownership verification so foreign files are never overwritten or deleted.
