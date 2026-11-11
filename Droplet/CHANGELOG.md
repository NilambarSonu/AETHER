# Changelog

## [2.0.0] - 2026-11-11

- Upgraded **`AETHER.droplet`** into a self-contained, standalone Droppy droplet with full CodeCatch feature parity requiring no external Mac application or helper process (`DroppyKit v1.23.0`, `minAppVersion: 16.2.0`).
- Unified `CodeCatchCore` inside `Droplet/Sources/CodeCatchCore` and extracted the headless `AetherEngine` module (`MessagesStore`, `AppleMailStore`, `MailOAuth` PKCE for Google & Microsoft, `GmailAPI`, `OutlookAPI`, `IMAPConnection`, `BitwardenCLI`, `AutoTyper`, `AetherAgentAccess`, `AgentSkillsManager`, `AetherSecrets`, `AetherClipboard`, `VaultSession`, `RecoveryInbox`).
- Added complete configuration UI strictly inside **Droppy → Settings → Droplets → AETHER** via `SettingsPagesProviding` (Root Pane, General, Sources & Accounts, Add/Edit Mail Accounts with Google/Microsoft OAuth PKCE and IMAP Test, Bitwarden TOTP Wizard, Ignored Senders, Not a Code Rules, Privacy & History, Agents & MCP, Approval Rules, Request Log, and Recent Emails Recovery).
- Added Notch & Command Center surfaces (`ShelfWidgetCompositionProviding`, `MenuBarExtraProviding`, `HUDPresenting`, `DropletNotificationService`, `LiveActivityProviding`) plus global shortcut registration (`DropletShortcutsService`) and native Droppy MCP tools (`MCPToolProviding`).

## [1.0.0] - 2026-11-10

- Built against the official DroppyKit SwiftPM SDK (`1.12.0`+ compatible with Droppy 15.3+, Droppy Playground, and Droppy 16.x).
- Added the initial `HUDPresenting` notch presentation bridge for verification codes delivered over local Unix Domain Sockets.
