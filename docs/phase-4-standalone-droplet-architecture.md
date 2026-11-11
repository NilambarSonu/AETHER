# Phase 4 — Standalone Full-Feature AETHER Droplet Architecture & Implementation Plan

**Status:** Architecture & Execution Blueprint
**Target SDK:** Official `DroppyKit v1.23.0` (`11e4869898bf13991120e26af347b9007521623b`, ABI `1`, `minMacOS: 15.0`)
**Target Host:** Droppy (`16.2.x` nightly+, shipping `DroppyKit v1.23.0`)
**Scope:** Replace the passive IPC-only HUD client with a **single, self-contained, production-grade `AETHER.droplet`** inside `Droplet/` implementing complete `CodeCatch` parity — all engines (Messages, Apple Mail, Gmail OAuth API, Outlook/Graph OAuth API, IMAP IDLE, Bitwarden CLI TOTP, Agent/MCP guardrails, Privacy/Keychain/Touch ID) and all Settings hosted inside **Droppy Settings → Droplets → AETHER**, with live delivery & quick access in Droppy's **Notch Shelf / Command Center / Notification Banner Stack / HUD**.

---

## 1. Executive Diagnosis: Why the Previous `AETHER.droplet` Appeared Empty

In Phase 3F, `Droplet/Sources/AETHER/AetherDroplet.swift` was intentionally a thin UNIX Domain Socket listener waiting on an external `CodeCatch` macOS host app:

1. **`droplet.json` declared only `["hud"]` surface and `["hud", "clipboard-write"]` capabilities (`minAPI: 1.12.0`).**
   - It did **not** conform to `SettingsPaneProviding` or `SettingsPagesProviding`, so **Droppy → Settings → Droplets → AETHER** rendered only the host-provided enable toggle, capability badges, and About card.
   - It did **not** conform to `ShelfWidgetProviding` / `ShelfWidgetCompositionProviding` or `MenuBarExtraProviding`, so **no icon tile appeared** in Droppy's Notch Shelf Favorites Grid or Command Center.
2. **All actual monitoring (Messages, Apple Mail, Gmail, Outlook, IMAP, Bitwarden), preferences, Keychain storage, and Settings UI lived outside `Droplet/` inside `Sources/CodeCatch/`.**

Phase 4 eliminates the split-app requirement and consolidates the entire `CodeCatch` capability set directly into **`Droplet/`** as a self-contained `.droplet` bundle.

---

## 2. Core Architectural Principles & Non-Negotiable Constraints

1. **Zero Separate App Required:** `AETHER.droplet` owns account configuration, mail/message ingestion, OTP extraction, link phishing/DMARC verification, Bitwarden TOTP generation, Touch ID / password unlock policy, clipboard hygiene, notifications/HUDs, shelf quick-access, and agent/MCP access directly inside Droppy's process.
2. **All Settings Live Inside Droppy Settings (NEVER in the Notch):**
   - **Settings (`SettingsPagesProviding` → Droppy Settings → Droplets → AETHER):** Multi-page grouped `Form` hierarchy covering **General**, **Sources & Accounts** (including Gmail OAuth, Microsoft OAuth, iCloud/Yahoo/IMAP, Messages, Apple Mail, Bitwarden, Ignored Senders, Not a Code), **Privacy**, **Agents & MCP** (Rules, History, Agent Skills), and **Recent Emails** (30-minute unmatched recovery inbox).
   - **Notch & Command Center (`ShelfWidgetCompositionProviding`, `MenuBarExtraProviding`, `HUDPresenting`, `DropletNotificationService`, `LiveActivityProviding`):** Strictly for live code/link presentation, Touch ID unlock, copy/open actions, quick search, Bitwarden pins/search, and attention banners — never crowded with configuration toggles.
3. **DroppyKit v1.23.0 Good Citizen Compliance:**
   - **Preferences:** Uses `host.preferences.userDefaults` + `.defaultAppStorage(defaults)` on every SwiftUI root handed to Droppy. **Zero `UserDefaults.standard` calls.**
   - **Keychain Separation:** Uses dedicated service namespace `app.getdroppy.droplet.aether` (never colliding with standalone `com.uros.codecatch` ACLs). Secrets never enter `UserDefaults`.
   - **Windows & Status Items:** **Zero `NSWindow` / `NSPanel` / `NSStatusItem`** creation. Uses Droppy's native `DropletNotificationService` (banner stack), `DropletHUDService` (strip/card), `ShelfWidgetCompositionProviding` (notch widget), and `MenuBarExtraProviding` (Command Center tile).
   - **No Admin Privilege Escalation (`NSAppleScript`):** Never shells out via `with administrator privileges` to write `/usr/local/bin/codecatch`. Agent automation integrates natively via `DroppyKit.MCPToolProviding` + user-writable agent skill markdown (`~/.claude/skills/`, `~/.codex/skills/`, `~/.cursor/skills/`).
   - **Lifecycle Determinism:** Every timer, `DispatchSource`, `NotificationCenter` / `DistributedNotificationCenter` observer, `FSEventWatcher`, `NWPathMonitor`, `Task`, `MailWatcher` / `APIWatcher`, and `BitwardenCLI` subprocess is tracked and torn down cleanly inside `Droplet.deactivate()`. Double `activate` → `deactivate` → `activate` cycles are safe and idempotent.

---

## 3. Feature Parity Matrix (`CodeCatch 2.0` → Standalone `AETHER.droplet`)

| Domain | Original `CodeCatch` Behavior | Standalone `AETHER.droplet` Implementation | DroppyKit Capability / API |
| --- | --- | --- | --- |
| **Settings Navigation** | 4-tab window (`General`, `Sources`, `Privacy`, `Agents`) + modal sheets | Native multi-page drill-down inside **Droppy → Settings → Droplets → AETHER** | `SettingsPagesProviding` (`DropletSettingsPane`, `DropletSettingsPageLink`, `DropletSettingsPage`, `makeSettingsPageToolbar`, `DropletConfirmationDialog`) |
| **Menu Bar / Quick Access** | `MenuBarExtra` popover with latest card, search, day sections, recovery footer | Command Center tile (`MenuBarExtraProviding`) + Notch Shelf Widget (`ShelfWidgetCompositionProviding` with `ShelfWidgetScaffold`) | `menu-bar`, `shelf-read`, `shelf-write` |
| **Arriving Banner** | Custom top-right `NSPanel` (`Banner`) | Native `DropletNotification` banner with actions (`Copy Code` / `Open Link` / `Unlock` / `Ignore`) + optional `DropletHUDRequest` strip/card in notch | `notch-banner`, `hud`, `DropletNotificationService` (`1.23.0`) |
| **Live Activity** | Menu bar code readout for 3m (`codeInMenuBar`) | Optional ephemeral `LiveActivityProviding` compact pill during active agent wait or brief freshly-arrived countdown; yields cleanly (`nil`) at rest | `live-activity` (`DropletLiveActivityPriority`) |
| **Auto-Copy & Clipboard** | Local-only `NSPasteboard` (`org.nspasteboard.ConcealedType` & `TransientType`), optional 90s auto-clear | Exact `Clipboard` parity inside `AetherEngine` wired to `Clear Clipboard After 90 Seconds` + screen-lock clear | `clipboard-write` |
| **Auto-Type Codes** | Opt-in key-by-key `CGEvent` typing for split OTP fields when frontmost app is external | Exact `KeyTyper` parity using `host.permissions.status(for: .accessibility)` & scoped `synthetic-input` lint waiver | `accessibility` (`// droppykit-lint: allow synthetic-input: ...`) |
| **Sound Cues** | Play `Tink` sound on arrival (`sound`) | `DropletFeedbackService` / system sound playback gated on `sound` preference | `sound-playback` |
| **Keyboard Shortcuts** | Global Carbon hotkeys (`⌃⌥⌘C` Copy Latest, `⌃⌥⌘F` Search) | Registered via `host.shortcuts` + `ShortcutsProviding`, user-rebindable in **Droppy → Settings → Shortcuts** | `global-shortcuts` (`DropletShortcutsService`) |
| **Startup & Updates** | `SMAppService.mainApp` Login Item + Sparkle updater | Managed transparently by Droppy host (`Launch at Login` & Droplet updates); Settings shows accurate host-managed status without mutating Droppy's own login item | Host-managed |
| **Catch Filters** | `Verification Codes`, `Sign-In Links`, `Password Reset Links`, `Ignored Senders`, `Not a Code` | 100% identical filtering, SHA-256 `NotCodeRule` hashing, and domain/sender/phone ignore rules | Stored in `host.preferences.userDefaults` |
| **Messages (`chat.db`)** | `SQLiteReader` + `FSEventWatcher` + `TypedStream` fallback decoding | Identical `MessagesStore` + `FSEventWatcher` using Droppy's Full Disk Access (`full-disk-access-probe` status & System Settings deep-link) | `full-disk-access-probe`, `SQLite3` (SDK autolinked) |
| **Apple Mail (`~/Library/Mail`)** | `SQLiteReader` (`Envelope Index`) + `.emlx` / `.partial.emlx` MIME body wait + `FSEventWatcher` | Identical `AppleMailStore` using Droppy's FDA + `MIME.parse` | `full-disk-access-probe`, `SQLite3` |
| **Gmail & Outlook OAuth** | `ASWebAuthenticationSession` PKCE (`OAuth.google`, `OAuth.microsoft`) + `GmailAPI` / `OutlookAPI` polling (`10s`) | Identical `OAuth`, `GmailAPI`, `OutlookAPI`, `APIWatcher`, with sheet anchored to Droppy's active Settings `NSWindow` via SwiftUI window probe | `network-client`, Keychain refresh tokens |
| **iCloud, Yahoo & Custom IMAP** | `IMAPConnection` TLS `EXAMINE INBOX` + `IDLE` (`540s` renew) / `NOOP` fallback (`20s`) + `NWPathMonitor` | Identical `IMAPConnection` + `MailWatcher` + `NWPathMonitor` + provider auto-guess (`MailAccount.guess`) | `network-client`, `NWConnection` |
| **Bitwarden TOTP Vault** | `bw` CLI setup wizard (`US`/`EU`), unlock/sync/`list items`, review diff, local TOTP generation (`TOTP`) | Upgraded `BitwardenCLI` with process-group isolation (`setpgid`, `kill(-pid, SIGTERM)`), concurrent pipe drain, deadline & `deactivate()` cancellation | `// droppykit-lint: allow process: ...` |
| **Touch ID / Unlock Policy** | `LAContext` Touch ID / Mac password, Lock on sleep/screen-lock, `Unlock with Mac` toggle in Keychain | Identical `VaultSession` + `UnlockPolicy` + `DeviceAuthentication`, decoupled from `NSApp.windows` / standalone popover | `LocalAuthentication` + Keychain |
| **Hide from Screen Capture & Privacy** | `Blur until Hover`, `Show Message Previews`, `Keep Codes 1/7/30d`, `Clear History When Mac Locks`, `Show Service Logos` (off by default), `Hide from Capture` | Full parity. `Show Service Logos` defaults to `false` (renders clean SF Symbol / monogram tiles; fetches favicons only if opted in). Scoped capture protection on hosted views (`NSView.window?.sharingType`), never sweeping `NSApp.windows`. | Scoped window `sharingType` + code redaction |
| **Recent Emails Recovery** | 30-min bounded in-memory buffer of non-matched mail with selection `⌘C` concealed copy | Accessible in **Settings → Recent Emails** page and quick-linked from Shelf Widget / Command Center footer | `SettingsPagesProviding` + `ShelfWidget` |
| **Agents & AI Integration** | `CLIServer` (UDS) + `codecatch` CLI symlink + Approval card + Rules + Last 50 logs | Primary: Native `MCPToolProviding` (`get_code`, `search_vault_codes`, `list_sources`, `copy_latest_code`) with full `AgentAccess` security gates (Touch ID approval via Droppy confirmation/notification, DMARC `senderVerified` guard, `55s` bounded wait under Droppy's `60s` MCP ceiling, `Allow All` 20/hr cap, 3-denial kill switch, 50-entry log) + Skills writer for Claude/Codex/Cursor | `MCPToolProviding` (`1.21.0+`) |

---

## 4. Target Workspace & Package Layout

Everything needed to compile and validate `AETHER.droplet` lives **exclusively inside `Droplet/`** (zero `../` dependencies so `cd Droplet && droppykit build` / `droppykit validate` / `droppykit lint` remain completely portable). Simultaneously, root `Package.swift` references `Droplet/Sources/CodeCatchCore` and `Droplet/Sources/AetherEngine` downward so `swift test` at the repository root compiles and tests both modules locally and on CI without Xcode:

```text
Droplet/
├── droplet.json                     # minAPI: "1.23.0", minAppVersion: "16.2.0", full capabilities & surfaces
├── Package.swift                    # CodeCatchCore + AetherEngine + AetherIPC + AETHER (.dynamic) + AETHERHarness
├── Package.resolved                 # Pinned DroppyKit v1.23.0 (11e4869898bf13991120e26af347b9007521623b)
├── LICENSE                          # GPL-3.0
├── README.md / CHANGELOG.md / NOTICE.md
├── Assets/Creator.png
└── Sources/
    ├── CodeCatchCore/               # SINGLE SOURCE OF TRUTH (moved/unified from root Sources/CodeCatchCore)
    │   ├── CodeExtractor.swift      # 704-case OTP detector + validity parser
    │   ├── MIME.swift               # Raw MIME & Authentication-Results DMARC parser
    │   ├── TOTP.swift               # RFC 6238 TOTP generator
    │   ├── VaultCode.swift          # Bitwarden JSON item importer
    │   ├── ServiceIdentity.swift    # Sender/domain resolver & ignore matcher
    │   ├── SignInLink.swift         # Sign-in vs password-reset URL classifier
    │   ├── LinkWrapper.swift        # Tracking-link destination unwrapper
    │   ├── SiteQuery.swift          # Agent query domain matcher
    │   ├── PublicSuffix*.swift      # Offline PSL
    │   ├── TypedStream.swift        # Messages attributedBody decoder
    │   └── AgentWire / CodeSignature / LocalSocket / IPCPeerValidator
    │
    ├── AetherEngine/                # Headless Core Engines (NO DroppyKit import — 100% XCTest/SwiftTesting ready)
    │   ├── Core/
    │   │   ├── AetherPrefs.swift            # Preference keys, defaults registration, typed accessors over injected UserDefaults
    │   │   ├── AetherSecrets.swift          # Keychain wrapper (`app.getdroppy.droplet.aether`) + injectable test backend
    │   │   ├── AetherRuntimeHooks.swift     # Protocol/callbacks bridging banners, HUDs, sound, URL open, agent UI, & typing
    │   │   ├── AetherClipboard.swift        # Local-only concealed/transient pasteboard + auto-clear timer
    │   │   ├── AetherIconStore.swift        # Opt-in service logo cache (Google/DDG proxies only when enabled)
    │   │   └── AetherLogger.swift           # Redacted OSLog logger (never logs secret codes or tokens)
    │   ├── Models/
    │   │   ├── IncomingMessage.swift        # Unified incoming mail/message representation + MIME initializer
    │   │   ├── SourceHealth.swift           # Per-source status, retry time, last checked/message/code
    │   │   ├── CodeItem.swift               # Code/link/vault item model + phishing linkNotice
    │   │   ├── CodeSearch.swift             # Ranking, pinned/recent vault shortcuts
    │   │   ├── NotCodeRule.swift            # SHA-256 context rule for false positives
    │   │   └── RecoveryInbox.swift          # Bounded 30m unmatched email buffer
    │   ├── Messages/
    │   │   ├── SQLiteReader.swift           # Read-only URI sqlite3 wrapper
    │   │   ├── FSEventWatcher.swift         # DispatchQueue-bound FSEventStreamRef watcher
    │   │   ├── LocalWatcher.swift           # FSEvents + 1s fallback poll + retry loop
    │   │   └── MessagesStore.swift          # ~/Library/Messages/chat.db reader
    │   ├── Mail/
    │   │   ├── MailAccount.swift            # Account model + Gmail/Outlook/IMAP host guessing + UserDefaults store
    │   │   ├── MailOAuth.swift              # PKCE ASWebAuthenticationSession (Google + Microsoft) w/ custom window anchor
    │   │   ├── MailSignIn.swift             # Async sign-in coordinator
    │   │   ├── GmailAPI.swift               # Gmail REST readonly watcher client
    │   │   ├── OutlookAPI.swift             # Microsoft Graph Mail.Read watcher client
    │   │   ├── IMAPConnection.swift         # Minimal TLS IMAP4rev1 + IDLE actor
    │   │   ├── MailWatcher.swift            # Backfill + IDLE/NOOP + exponential backoff
    │   │   ├── APIWatcher.swift             # Gmail/Outlook incremental cursor poller
    │   │   └── AppleMailStore.swift         # ~/Library/Mail V10 Envelope Index + .emlx reader
    │   ├── Vault/
    │   │   ├── DeviceAuthentication.swift   # LAContext Touch ID / password authenticator + cancel support
    │   │   ├── UnlockPolicy.swift           # Keychain-backed "Unlock with Mac" state
    │   │   ├── VaultSession.swift           # Sleep/lock auto-locking in-memory secret holder
    │   │   ├── VaultChanges.swift           # Import diff summary
    │   │   ├── VaultStorage.swift           # Encrypted-via-LAContext Keychain persistence
    │   │   └── BitwardenCLI.swift           # Hardened `bw` CLI runner (process group + SIGTERM on cancel/timeout)
    │   ├── System/
    │   │   ├── AccessibilityTrust.swift     # AXIsProcessTrusted probe
    │   │   ├── AutoTyper.swift              # Opt-in CGEvent digit typer (`allow synthetic-input`)
    │   │   └── SourceMonitor.swift          # Orchestrates Messages, Apple Mail, Mail accounts, NWPathMonitor & lifecycle stop
    │   ├── Agents/
    │   │   ├── AgentConfig.swift            # Keychain-backed config & allow rules
    │   │   ├── AgentAccess.swift            # Site/DMARC matcher, 20/hr rate limit, 3-denial auto-off, approval flow
    │   │   └── AgentSkillsManager.swift     # Claude Code / Codex / Cursor skill installer (`SKILL.md` for Droppy MCP)
    │   └── Model/
    │       └── AetherAppModel.swift         # Central ObservableObject coordinating ingest, lock, history, copy, open, stop()
    │
    ├── AetherIPC/                   # Preserved modular IPC wire types (backward-compat verification)
    │
    └── AETHER/                      # DroppyKit Presentation & Integration Layer
        ├── AetherDroplet.swift              # @objc(AETHERPrincipal) + Droplet + activate/deactivate + LiveActivity
        ├── DroppyBridges/
        │   ├── AetherNotificationBridge.swift   # DropletNotificationService banner stack + action handlers
        │   ├── AetherHUDBridge.swift            # DropletHUDStrip / DropletHUDCard notifications & copy confirmation
        │   ├── AetherShortcutsBridge.swift      # global-shortcuts registration (Copy Latest, Open Shelf) + ShortcutsProviding
        │   ├── AetherMCPBridge.swift            # MCPToolProviding (`get_code`, `search_vault_codes`, `list_sources`, `copy_latest_code`)
        │   └── AetherCaptureAndWindowHelpers.swift # WindowAnchorReader (for OAuth sheets) & scoped CaptureGuard + Permissions helpers
        └── UI/
            ├── Shared/
            │   ├── AetherServiceVisuals.swift   # Safe SF Symbol + gradient Monogram avatars + ExpiryRing + CodeText (blurred/masked)
            │   ├── AetherCodeActions.swift      # Shared copy/open/ignore/not-a-code/source actions & confirmations
            │   └── AetherWindowAnchors.swift    # SwiftUI -> NSWindow bridge for OAuth without NSApp.windows
            ├── Settings/
            │   ├── AetherSettingsRootPane.swift # Landing DropletSettingsPane (Status, Quick Test, Drill-down PageLinks)
            │   ├── GeneralSettingsPage.swift    # Delivery toggles, Accessibility status, Shortcuts summary, Host startup note
            │   ├── SourcesSettingsPage.swift    # What to Catch filters, Messages/FDA, Apple Mail/FDA, Accounts list, Bitwarden card
            │   ├── AddAccountSettingsPage.swift # Provider picker (Google, Microsoft, iCloud, Yahoo, Custom IMAP)
            │   ├── AccountEditorSettingsPage.swift # OAuth beta sign-in flow, IMAP host/port/app password, remove confirmation
            │   ├── BitwardenSettingsPage.swift  # Checklist wizard (`bw` CLI, US/EU server, `bw login`, password/session import, diff preview)
            │   ├── IgnoredSendersSettingsPage.swift # Add/remove addresses, domains, SMS senders
            │   ├── NotCodesSettingsPage.swift   # View/forget masked-digit Not a Code rules
            │   ├── PrivacySettingsPage.swift    # Touch ID lock, Capture guard, Blur codes, Previews, Clipboard clear, Logos, History retention
            │   ├── AgentsSettingsPage.swift     # MCP Enable toggle, Auto-Copy/Type safety warning, Connected Skills, Prompt copy box, Share & Permissions
            │   ├── AgentRulesAndLogPages.swift  # `Always Allowed` rules manager + `Request History` (last 50)
            │   └── RecoveryEmailsSettingsPage.swift # Split-view 30m unmatched email inspector with selectable ⌘C copy
            └── Notch/
                ├── AetherShelfWidgetView.swift  # ShelfWidgetCompositionProviding (`ShelfWidgetScaffold` single & split modes)
                └── AetherMenuBarExtraView.swift # Command Center tile & popover panel (`MenuBarExtraProviding`)
```

---

## 5. Manifest (`Droplet/droplet.json`) & Capability Specification

- **`kit.minAPI`**: `"1.23.0"` (matches `Droplet/Package.swift` `.package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.23.0")`)
- **`minAppVersion`**: `"16.2.0"` (Droppy `16.2.x` ships DroppyKit `1.23.0`)
- **`minMacOS`**: `"15.0"`
- **`category`**: `"System"`
- **`surfaces`**:
  - `"settings-pane"` (`SettingsPagesProviding` — root pane + 12 drill-down settings pages + search entries)
  - `"menu-bar-extra"` (`MenuBarExtraProviding` — Command Center tile & quick-access view)
  - `"shelf-widget"` (`ShelfWidgetCompositionProviding` — Notch Shelf icon tile + interactive code/search card)
  - `"live-activity"` (`LiveActivityProviding` — yields `nil` at rest; shows compact chip only during active short-lived window or agent approval wait)
  - `"hud"` (`HUDPresenting` — transient notch strip & card feedback)
- **`capabilities`**:
  - `"hud"` — transient notch strip / card announcements
  - `"notch-banner"` — Droppy native banner stack notifications (`host.notifications`)
  - `"menu-bar"` — Command Center tile (`MenuBarExtraProviding`)
  - `"shelf-read"` — inspect widget visibility & shelf state
  - `"shelf-write"` — present shelf widget from shortcut / notification (`host.shelf.open(revealing:)`)
  - `"global-shortcuts"` — system-wide Copy Latest Code & Open Codes hotkeys (`host.shortcuts`)
  - `"network-client"` — HTTPS/TLS access for Gmail API, Microsoft Graph API, IMAP IDLE, OAuth tokens, opt-in favicon cache
  - `"clipboard-write"` — local concealed/transient pasteboard copy & timed auto-clear
  - `"full-disk-access-probe"` — check Droppy's Full Disk Access status & open Privacy System Settings when Messages/Apple Mail is enabled without FDA
  - `"accessibility"` — check Accessibility status for opt-in Auto-Type & open System Settings
  - `"sound-playback"` — play completion/arrival audio cue when enabled

---

## 6. UI Hierarchy & Screen Flows

### 6.1 Droppy Settings → Droplets → AETHER (`SettingsPagesProviding`)

All configuration stays strictly inside **Droppy Settings**:

1. **Root Pane (`makeSettingsPane`)**:
   - **Vault & Monitoring Card**:
     - Lock status (`Locked` / `Unlocked`) + `Unlock` / `Lock` button (triggers `LAContext`).
     - Active monitoring summary (`Messages · N accounts · M codes in memory`) + **`Send Test Code`** button (tests banner, notch HUD, and clipboard end-to-end).
     - `Keyboard Shortcuts` link button calling `host.workspace.openShortcuts()`.
   - **Settings Pages Card** (`DropletSettingsPageLink` rows):
     - **`General`** (`page: "general"`) — Banner/HUD delivery, auto-copy, auto-type, sound, shortcuts, host lifecycle notes.
     - **`Sources & Accounts`** (`page: "sources"`) — What to catch, Messages, Apple Mail, Google Gmail / Microsoft Outlook / iCloud / Yahoo / IMAP accounts, Bitwarden.
     - **`Privacy & Security`** (`page: "privacy"`) — Touch ID unlock, capture hiding, blur until hover, previews, clipboard timer, service logos, history retention.
     - **`Agents & MCP`** (`page: "agents"`) — Droppy MCP sharing toggle, auto-copy/type safety banner, Claude/Codex/Cursor skill connections, permission rules, request history.
     - **`Recent Emails`** (`page: "recovery"`) — Unmatched recovery inbox from the last 30 minutes.
   - **`settingsSearchEntries`**: Indexes every setting title & keyword (`Gmail`, `Outlook`, `IMAP`, `Bitwarden`, `Touch ID`, `Messages`, `Apple Mail`, `Ignored Senders`, `Not a Code`, `MCP`, `Auto-Type`, `Clipboard`) into Droppy Settings' global search bar.

2. **Sub-Pages (`makeSettingsPage(id:context:)` & `makeSettingsPageToolbar(id:context:)`)**:
   - **`general`**:
     - *When a Code or Link Arrives*: `Show Notification Banner` (`notch-banner`), `Show Notch HUD Strip`, `Automatically Copy Codes`, `Automatically Type Codes` (shows Accessibility permission status badge + `Allow…` System Settings button when enabled), `Play Sound`.
     - *Keyboard*: Registered Droppy Shortcuts (`DroppyShortcutRecorder` / `Edit in Shortcuts…` button).
     - *Startup & Updates*: Informative read-only status rows explaining Droppy handles launch-at-login and droplet bundle lifecycle (`Droppy` version/bundle version), preventing erroneous mutation of Droppy's own `SMAppService`.
   - **`sources`** (Toolbar: `+ Add Account` pill, `Refresh` pill):
     - *What to Catch*: `Verification Codes`, `Sign-In Links`, `Password Reset Links`, `Ignored Senders` link (`sources.ignored`), `Not a Code` link (`sources.notcodes`), paused banner when all three are off.
     - *Messages*: Enable toggle + colored health status dot (`Live`, `Needs Full Disk Access`, `Error`) + `Allow Full Disk Access…` row calling `host.permissions.openSystemSettings(for: .fullDiskAccessProbe)` when needed + health details (`Last checked`, `Last message`, `Last code`, `Check Now`).
     - *Mail*: `Apple Mail` toggle + FDA status row + health details; List of configured `MailAccount` rows (watch toggle, email & status subtitle, `Configure >` push to `sources.account:<uuid>`, `Check Now`). Plus `+ Add Mail Account` link (`sources.add-account`).
     - *Bitwarden*: Setup / status summary + Enable toggle + Refresh / Lock / Unlock / Remove (`DropletConfirmationDialog`) + link to `sources.bitwarden`.
   - **`sources.add-account`**: Clean native list picking **Google (Gmail)**, **Microsoft (Outlook / Hotmail / Microsoft 365)**, **iCloud Mail**, **Yahoo Mail**, or **Other IMAP Account**, routing directly into `sources.account:new:<preset>`.
   - **`sources.account:<id>`** (Toolbar: `Save` pill):
     - Provider banner & required read-only disclosure before consent.
     - For Google / Microsoft: `Sign in with Google / Microsoft…` (`ASWebAuthenticationSession` anchored to the Settings window via `WindowAnchorReader`), signed-in status, `Sign Out`.
     - For IMAP (including Gmail app-password option): `Label`, `Email` (auto-guesses IMAP host on submit), `IMAP server`, `Port`, `App password` (`SecureField`), `Enabled` toggle, validation/auth error banner, and `Remove Account…` (`DropletConfirmationDialog`) calling `goBackInSettings()` on completion.
   - **`sources.ignored` / `sources.notcodes`**: Add/remove ignored senders (address, domain `@domain`, SMS phone/sender ID) with validation help, and forget false-positive `Not a Code` pattern hashes.
   - **`sources.bitwarden`**: Full step-by-step interactive wizard (CLI version check, `US`/`EU` region picker + `bw config server`, signed-in status, master password OR session paste, diff review showing Added / Changed / Removed + unreadable warnings, Commit Save with Touch ID).
   - **`privacy`**:
     - *Unlock*: `Ask for Touch ID / Mac Password to Show Codes` (backed by Keychain `UnlockPolicy`).
     - *On Screen*: `Hide Sensitive Views from Screen Capture`, `Hide Codes Until Hover`, `Show Live Activity Chip Briefly` (only for new codes / agent wait), `Show Message Previews`.
     - *Clipboard & Network*: `Clear Clipboard After 90 Seconds`, `Show Service Logos` (default OFF; discloses Google/DDG favicon proxy trade-off).
     - *History*: `Keep Codes For` (`1 Day` / `7 Days` / `30 Days`), `Clear History When Mac Locks`, `Clear History` (`Clear Now` with `DropletConfirmationDialog`).
   - **`agents`**:
     - *AI & MCP Access*: `Let Agents Ask for Codes` toggle (Touch ID protected, stored in Keychain) + live warning banner if `Automatically Copy` or `Automatically Type` is active while agent access is on (`Turn Off` one-click button).
     - *Connected Coding Agents*: Status + `Connect` / `Disconnect` buttons for **Claude Code** (`~/.claude/skills/codecatch/SKILL.md`), **Codex** (`~/.codex/skills/codecatch/SKILL.md`), **Cursor** (detects inheritance cleanly), updating instructions to invoke Droppy's MCP tools (`droplet_aether_get_code`, `droplet_aether_status`), plus copyable `AGENTS.md` / `CLAUDE.md` prompt block.
     - *What to Share*: `Verification Codes` (Included), `Sign-In Links` toggle (Touch ID protected; verified senders only), `Password Reset Links` (Never).
     - *Permissions*: `Allow All Without Asking` toggle (Touch ID protected), `Always Allowed` rules (`agents.rules`), `Request History` (`agents.history`).
   - **`recovery`**:
     - Master-detail list of emails from the past 30 minutes containing OTP context where automated extraction found no match, with `Check Again`, `Unlock`, and selectable body / `Copy Message` using local concealed clipboard.

### 6.2 Notch Shelf Widget, Command Center Tile & Arriving Code Alerts

1. **Command Center Tile (`MenuBarExtraProviding`):**
   - Renders `AETHER` tile (`systemImage: "key.viewfinder"`, `title: "AETHER"`) inside Droppy's Command Center panel.
   - Clicking opens a crisp, fast code-management popover (`MenuContent` parity): Lock/Unlock button, Source-attention alert banner (e.g., `Needs Full Disk Access` → Opens System Settings, `Sign In Expired` → Opens Account page in Settings), Search field, Hero Latest Code Card (service badge, big spaced digits, expiry ring, Copy / Open Link / View in Messages/Mail), Today / Older grouped code rows with hover blur-reveal & context menu (`Copy`, `Open Link`, `Pin Vault Login`, `Clear`, `Not a Code`, `Ignore Sender`), `Show Older` expander, and `Recent Emails` footer button (`host.workspace.openSettingsPage("recovery", title: "Recent Emails")`) + `Settings…` gear action (`host.workspace.openSettings()`). **Zero configuration toggles live here.**
2. **Notch Shelf Widget (`ShelfWidgetCompositionProviding`):**
   - Puts the `AETHER` icon in Droppy's Notch Shelf Favorites / Widget Grid (fixing Image 1!).
   - Built on `ShelfWidgetScaffold` (inherits `context.contentInsets`, host font scale, `.droppyWidgetText`, `DroppyWashCircleButtonStyle` / `DroppyWashPillButtonStyle`, no custom card chrome, no entrance animation).
   - **Compact / Split Mode:** Latest live code hero, countdown ring / `"Expired"` state, 1-click Copy / Open Link wash button, Lock/Unlock pill, and quick search/open-Settings icon.
   - **Solo Mode:** Hero code card + quick scroll list of recent live codes & pinned Bitwarden logins + source status pill + `Unlock` / `Copy` / `Settings` actions.
3. **Notification Banners & HUD (`DropletNotificationService` + `DropletHUDService`):**
   - **Arriving Code/Link (`showBanner` ON):** Posts `DropletNotification` (`threadID: "aether-codes"`) with privacy-aware body (`••••••` when locked or `showPreviews == false`, plaintext code + sender preview when unlocked) and action buttons (`Copy Code` / `Open Link` / `Unlock`, `Dismiss` / `Ignore Sender`).
   - **Notch HUD (`showNotchHUD` toggle & feedback):** Presents `DropletHUDStrip` + `DropletHUDCard` via `.normal` priority when arriving (or `.high` only on explicit user click/shortcut like `Copy Latest Code`!).
4. **Live Activity (`LiveActivityProviding`):**
   - Returns `nil` by default so the notch stays completely clean at rest (`GoodCitizen`).
   - Optionally activates briefly (`DropletLiveActivityPriority.attention` / `.status`) ONLY while waiting for user Touch ID approval on an incoming MCP agent request OR briefly (`180s` if `Show Code in Notch Live Activity` is enabled by the user and code is unlocked & uncopied).

---

## 7. Security, Privacy, Lint Rules & Legal/Store Tradeoffs

### 7.1 `droppykit lint --strict` & Waiver Architecture
| Rule | Usage in `AETHER` | Handling Strategy |
| --- | --- | --- |
| `host-defaults` | AppStorage / UserDefaults | **Strict Elimination:** Every class accepts `defaults: UserDefaults` from `host.preferences.userDefaults`; all SwiftUI views apply `.defaultAppStorage(...)`. Zero `UserDefaults.standard`. |
| `own-window` / `own-status-item` | Notifications, Popover | **Strict Elimination:** Zero `NSWindow`, `NSPanel`, or `NSStatusItem`. Uses `host.notifications`, `host.hud`, `ShelfWidget`, `MenuBarExtraProviding`. |
| `host-windows` | OAuth anchor & capture hiding | **Zero `NSApp.windows` access.** OAuth anchor reads `NSView.window` from SwiftUI view representable (`WindowAnchorReader`) or `NSApp.keyWindow`. Capture hiding sets `window.sharingType` only on AETHER's active hosted window and restores original value on `onDisappear` / `deactivate()`. |
| `admin-privileges` | Old `CommandLineTool.swift` | **Removed completely.** No `NSAppleScript` or `/usr/local/bin` installer. Replaced with native `MCPToolProviding`. |
| `synthetic-input` | Auto-Type OTP (`AutoTyper.swift`) | User-opt-in feature (off by default), gated on `DropletPermission.accessibility`. Uses scoped line waiver: `// droppykit-lint: allow synthetic-input: User opt-in OTP auto-type into focused fields with Accessibility trust`. Note: Requires maintainer exception if ever submitted to the public Droppy Store (`Rules.md`). |
| `process` | Bitwarden `bw` CLI (`BitwardenCLI.swift`) | Spawns `bw` only on explicit user click in Bitwarden wizard with `setpgid` process group isolation, concurrent stdout/stderr pipe drain, `terminationHandler`, timeout + `kill(-pid, SIGTERM)` and cancellation in `deactivate()`. Uses scoped waiver: `// droppykit-lint: allow process: User-initiated Bitwarden bw CLI TOTP import with process-group deadline and deactivate kill`. |
| Third-Party Logos (`GoodCitizen.md`) | `Show Service Logos` | Defaults `OFF`. Zero third-party logo files bundled in `Assets/`. Renders native SF Symbols + system-gradient `Monogram` squares unless the user explicitly enables network favicon lookup in Privacy Settings. |
| **License (`GPL-3.0`)** | Existing `AETHER` + `CodeCatch` license | `droplet.json` & `LICENSE` declare `GPL-3.0`. Passes `droppykit lint --strict` and `droppykit validate` cleanly for local & GitHub release builds. Explicitly noted: public Droppy Store (`gitlab.com/droppyformac1/droplets`) policy (`GoodCitizen.md`) restricts GPL code unless granted explicit maintainer exception or cleanly re-licensed. |

### 7.2 OAuth Redirect Handling Inside `Droppy.app`
- `OAuth.google` (`com.googleusercontent.apps.374242175460-...:/oauth2redirect`) and `OAuth.microsoft` (`msauth.com.uros.codecatch://auth`) run via `ASWebAuthenticationSession(url:callback:.customScheme(scheme))` with PKCE (`S256`).
- `ASWebAuthenticationSession` intercepts the custom redirect scheme inside macOS's system authentication sheet directly without requiring those schemes in `Droppy.app`'s `Info.plist`.
- Both Google and Microsoft public client IDs are inherited verbatim from `CodeCatch`; documentation & settings editor display the required pre-consent read-only privacy notice (`gmail.readonly` / `Mail.Read`).

### 7.3 SQLite & File Monitoring Inside `Droppy.app`
- `MessagesStore` (`~/Library/Messages/chat.db`) and `AppleMailStore` (`~/Library/Mail/V*/MailData/Envelope Index`) open read-only (`SQLITE_OPEN_READONLY | SQLITE_OPEN_URI`) using system `libsqlite3` (verified autolinked under `swiftc -emit-library` + `-enable-library-evolution`).
- If read fails with permission error, reports `.attention(SourceStatus.needsDiskAccess)` without spamming retries (>5s backoff); UI shows **"Full Disk Access Needed for Droppy"** + button calling `host.permissions.openSystemSettings(for: .fullDiskAccessProbe)`.

---

## 8. Phased Implementation Plan & Verification Gates

1. **Milestone 1 — Workspace Unification (`CodeCatchCore` Single Source of Truth):**
   - Move `Sources/CodeCatchCore/` → `Droplet/Sources/CodeCatchCore/`.
   - Update root `Package.swift`, `scripts/update-psl.sh`, `scripts/install.sh`.
   - Verify root `swift test --filter CodeCatchCoreTests` passes all tests & 704 OTP fixture rows.

2. **Milestone 2 — Headless `AetherEngine` Extraction & Unit Test Suite:**
   - Implement `Droplet/Sources/AetherEngine/` cleanly parameterized (zero `UserDefaults.standard`, zero `NSApp.windows`, zero `Droplet` UI imports, hardened `BitwardenCLI`, decoupled `OAuth`/`DeviceAuthentication`/`AppModel`).
   - Wire `AetherEngine` into root `Package.swift` + create `Tests/AetherEngineTests/` testing preferences isolation, Keychain persistence abstraction, mail account CRUD, OAuth callback parsing, ingestion & filters, `NotCodeRule`, `RecoveryInbox`, `CodeSearch`, `VaultSession` lock/unlock policy, `BitwardenCLI` cancellation, and `AgentAccess` 20/hr rate limits & Touch ID/DMARC guards.
   - Verify `swift test` runs all tests locally with 0 failures.

3. **Milestone 3 — `Droplet/` Manifest, Package & Bridges (`DroppyKit v1.23.0`):**
   - Update `Droplet/droplet.json` (`minAPI: "1.23.0"`, `minAppVersion: "16.2.0"`, full capabilities & surfaces) and `Droplet/Package.swift` (`from: "1.23.0"`, linking `CodeCatchCore`, `AetherEngine`).
   - Implement `AetherDroplet` principal + `Droplet` lifecycle (`activate`/`deactivate`), `AetherNotificationBridge`, `AetherHUDBridge`, `AetherShortcutsBridge`, `AetherMCPBridge`, and `AetherWindowAnchors`/`CaptureGuard`.

4. **Milestone 4 — Complete Settings Pages (`SettingsPagesProviding`):**
   - Implement `AetherSettingsRootPane` and all sub-pages (`General`, `Sources`, `AddAccount`, `AccountEditor`, `BitwardenSetup`, `IgnoredSenders`, `NotCodes`, `Privacy`, `Agents`, `AgentRules`, `AgentHistory`, `RecoveryEmails`) + `makeSettingsPageToolbar` + `settingsSearchEntries`.

5. **Milestone 5 — Notch Shelf Widget, Command Center Tile & Live Activity:**
   - Implement `AetherShelfWidgetView` (`ShelfWidgetCompositionProviding` + `ShelfWidgetScaffold`), `AetherMenuBarExtraView` (`MenuBarExtraProviding`), and ephemeral `LiveActivityProviding`.
   - Ensure Settings never appear in the notch, while Command Center & Shelf show the AETHER icon and live code experience cleanly.

6. **Milestone 6 — Strict Verification, Documentation & Hardening:**
   - Update `README.md`, `ARCHITECTURE.md`, `SECURITY.md`, `Droplet/README.md`, `Droplet/CHANGELOG.md`, `Tests/AetherCoreTests/AetherReleaseHardeningTests.swift`.
   - Run full root `swift test`, run `python3 /Users/nilambarbehera/Documents/Projects/droppykit/Scripts/lint-droplet.py --package Droplet --no-binary --strict`, inspect compiled targets, and prepare CI workflow verification (Xcode 26 + `droppykit build` + `droppykit validate` + `droppykit run --shots --report`)!
