# AETHER Standalone Droplet — Deep Architecture, Security, Latency & UI/UX Engineering Audit

**Version Target:** `2.1.0` (`DroppyKit v1.23.0`, ABI `1`)  
**Scope:** [`Droplet/Sources/`](../Droplet/Sources) (`CodeCatchCore`, `AetherEngine`, `AETHER`)  
**Purpose:** Exhaustive technical analysis of inherited upstream CodeCatch weaknesses, OAuth branding & Google verification red-warning root cause, zero-database cryptographic defense-in-depth, zero-delay / zero-miss OTP ingestion algorithms, sender brand visuals in Notch HUD/notifications, and Apple-native `DroppyKit` UI/UX architecture.

---

## 1. Executive Summary: Why "Clean Forking" CodeCatch Was Only Step Zero

Importing CodeCatch's open-source parsing and watcher foundations gave AETHER standalone parity inside Droppy, **but inheriting CodeCatch's defaults blindly left five critical gaps** compared to a hardened, production-grade Droplet architecture:

1. **Upstream CodeCatch OAuth Identity Leakage & Google Red Warning:**
   [`MailOAuth.swift`](../Droplet/Sources/AetherEngine/Mail/MailOAuth.swift) still shipped CodeCatch's Google Cloud Client ID (`374242175460-...`) and Microsoft Entra App ID (`946bd1c2-...`, `msauth.com.uros.codecatch://auth`). Users signing in saw CodeCatch's name/logo, developer contact (`uros.gazvoda@futuristica.com`), and Google's `"Google hasn't verified this app (unsafe)"` screen.
2. **Mailbox Polling Latency & Missed-OTP Blind Spots ("Arrives in Gmail app, missing until manual refresh"):**
   Fixed 10s polling in [`APIWatcher.swift`](../Droplet/Sources/AetherEngine/Mail/APIWatcher.swift), serial one-by-one message downloads, Gmail `history.list` filtering strictly to `historyTypes=messageAdded` + `labelId=INBOX`, Outlook second-granularity timestamp cursors with full `seen.removeAll()` wipes, 120s retry sleeps across sleep/wake, and Apple Mail 30s follow-up lag when `.emlx` body writes trail `Envelope Index` SQLite inserts.
3. **Keychain Secrets Stored as Unwrapped Plaintext Blobs + Tamperable Policy State:**
   [`AetherSecretStore`](../Droplet/Sources/AetherEngine/Core/AetherSecrets.swift) stored `[VaultCode]` JSON, `AgentConfig` JSON, and `"unlock-with-mac"` (`"true"`/`"false"`) in generic Keychain without `ThisDeviceOnly` locality attributes or AEAD cryptographic authentication/integrity binding. `AgentAuditLog`, `mailAccounts`, and cache filenames on disk leaked metadata in plain form.
4. **Generic Monochrome Icons & Missing Sender Branding in the Notch:**
   `AetherDroplet` (`makeCompactLeading`) and [`AetherHUDBridge`](../Droplet/Sources/AETHER/DroppyBridges/AetherHUDBridge.swift) showed a generic `key.viewfinder` symbol even for recognizable senders (Facebook, Google, GitHub, etc.), and didn't show sender identity cleanly inside the Notch HUD card.
5. **Visual Mismatch & Row Crowding in Droppy Settings:**
   Subpages mixed bare monochrome glyphs inside `DropletToggleRow` next to large colored tiles (`AetherSymbolTile`), duplicated "+ Add Account" controls, jammed multiple buttons/status controls onto single rows, and included boilerplate rows redundant inside Droppy Settings.

---

## 2. OAuth Identity & Google Red-Warning Root Cause Analysis

### 2.1 Exact Technical Cause of Screenshots 1 & 2

When `MailOAuth.signIn` launches `ASWebAuthenticationSession`:
- **Google Screen ("to continue to CodeCatch" + orange asterisk logo):**  
  Google renders the **OAuth Consent Screen metadata (App Name, App Logo, Support Email, Privacy Policy, Terms URL)** stored inside the Google Cloud Project that owns the `client_id` parameter (`374242175460-...`). No client-side Swift string can override what Google displays for a third-party `client_id`.
- **Red Warning ("Google hasn't verified this app / Go to CodeCatch (unsafe)"):**  
  `https://www.googleapis.com/auth/gmail.readonly` is a **Google Restricted Scope**. Google mandates:
  - **Testing Mode (`External` user type, up to 100 explicit Test Users):** Still displays an unverified notice for `gmail.readonly` and **expires OAuth refresh tokens every 7 days**.
  - **Internal Mode (Google Workspace org users only):** Zero unverified warning within that Workspace organization.
  - **Production Public Verification (`External`):** Requires completing **Google OAuth Brand Verification** (verified homepage domain, privacy policy, YouTube scope demo video) **plus CASA (Cloud Application Security Assessment — Tier 2)** because `gmail.readonly` reads mailbox data.

### 2.2 Architectural Solution in AETHER

1. **Immediate Removal of Upstream CodeCatch OAuth IDs:**  
   Scrub `374242175460-...` and `946bd1c2-...` / `msauth.com.uros.codecatch://auth` completely from [`MailOAuth.swift`](../Droplet/Sources/AetherEngine/Mail/MailOAuth.swift) so third-party CodeCatch branding never appears.
2. **Custom & Bundled AETHER OAuth Configuration (`AetherOAuthConfig`):**  
   Support BOTH:
   - Compiled-in AETHER GCP / Microsoft Entra Client IDs (ready to populate once created under your own Google Cloud & Azure accounts), AND
   - Keychain-stored **Per-User Custom OAuth Client IDs** configurable directly inside **Droppy → Settings → Droplets → AETHER → Sources & accounts → Add / Edit Mail Account** (deriving Google's `com.googleusercontent.apps.<PREFIX>:/oauth2redirect` iOS client redirect URI and Microsoft's `app.getdroppy.droplet.aether://auth` automatically).
3. **Zero-Warning Gmail / Outlook App Password Fallback (First-Class Citizen):**  
   For users who want zero OAuth consent screens, zero 7-day token expirations, and instant sub-second `IMAP IDLE` push before CASA verification is completed, **App Password (TLS IMAP port 993)** remains available alongside OAuth with clear inline guidance.

---

## 3. Codebase Security & Zero-Database Architecture Audit

### 3.1 What Was Already Strong vs. Remaining Weaknesses

| Security Area | Inherited Baseline | Vulnerability / Weakness Found | Upgraded AETHER Architecture |
| :--- | :--- | :--- | :--- |
| **Live OTP Storage** | RAM-only `[CodeItem]` array | Cleared properly on lock/expiry, **but** OAuth `access_token` cache (`MailOAuth.cache`) remained in static RAM across lock/sleep | Clear `MailOAuth` bearer cache synchronously inside `VaultSession.lock()`, `willSleep`, and `deactivate()`. Enforce **Zero-Database-on-Disk Invariant** permanently. |
| **Bitwarden Vault & Agent Secrets** | Stored as raw UTF-8 JSON inside Keychain (`bitwarden.codes`, `agent-access`) | Anyone or any helper inspecting the Login Keychain item sees raw `otpauth://` secrets & JSON unencrypted; `kSecAttrAccessible` defaulted without `ThisDeviceOnly` (sync hazard) | Enforce `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Wrap payloads via **`AetherVaultCrypto`**: **AES-256-GCM + HKDF-SHA256** domain subkeys (`aether.v2`) with **AAD** binding ciphertext to `bundleID + domain + keyName`. |
| **Unlock Policy (`unlockWithMac`) & Agent `allowAll`** | Raw `"true"`/`"false"` string in Keychain (`unlock-with-mac`); plain JSON in `agent-access` | If a Keychain value or defaults entry is swapped/forged externally, unlock prompt or agent auto-approval could be subverted cleanly | Stored inside **AES-256-GCM AEAD + AAD-bound envelopes**. Any bit flip, replay from another key, or non-envelope tampering fails GCM tag verification and **fails closed** (`isUnlocked = false`, Touch ID required, `agent.enabled = false`). |
| **Metadata in `UserDefaults`** | `agentLog` written to unencrypted `UserDefaults` plist | Reveals caller apps, requested sites, and timestamps in `~/Library/Preferences/` | Move `AgentAuditLog` out of `UserDefaults` into AEAD-sealed Keychain (`agent.audit.v2`), auto-pruned and removable via Clear Log. |
| **Disk Favicon Cache** | `~/Library/Caches/AETHER/Icons/<domain>.png` & `<domain>.miss` | Plaintext domain filenames reveal every bank, exchange, and service user uses (`ls .../Icons`) | Derive filenames via **Keychain-backed HMAC-SHA256** keyed digest (`<hmac32>.png` / `<hmac32>.miss`) so disk cache leaks zero domain names. |
| **PKCE Randomness** | `Int.random(in:)` Swift RNG for PKCE `code_verifier` and `state` | Non-cryptographic PRNG rather than OS CSPRNG | Replace with **`SecRandomCopyBytes`** unbiased CSPRNG sampling. |
| **Bitwarden CLI Input Hygiene** | `masterPassword` kept in Swift `String` until reset | Lacks explicit `Data`/byte cleanup where controllable | Clear sensitive transient fields immediately on exit/cancel/import completion and enforce process-group termination in `deactivate()`. |
| **Runtime Binary & Anti-Tamper** | Runs unsigned/ad-hoc in local testing, signed by Droppy in Store | Malicious process could inspect or tamper with preferences/IPC without verification | Host code runs inside **Hardened Runtime Droppy.app** (Developer ID signed, library validation / codesign enforcement in production). Add AAD key binding, fail-closed policy validation, strict `IPCPeerValidator` audit verification (if local IPC is bridged), and **SPKI TLS pinning roadmap** for `gmail.googleapis.com`, `oauth2.googleapis.com`, `graph.microsoft.com`, `login.microsoftonline.com`. |

### 3.2 Zero-Database Storage Guarantee

AETHER **never creates any SQLite database, Core Data store, Realm file, or JSON history log of received OTPs**:
- **Messages & Apple Mail:** Opened **strictly read-only** (`SQLITE_OPEN_READONLY` via `SQLiteReader` / `O_RDONLY` on `.emlx`) exclusively to inspect arriving items within user-configured retention (`historyDays`).
- **Live Codes & Recovery Inbox:** Exist **solely in volatile process memory** inside `@MainActor AetherAppModel`. Closing/deactivating the droplet, locking macOS (when `Clear history when Mac locks` is on), or expiry removes them immediately with zero swap-friendly disk files written.
- **Persistent Secrets Only (`AetherSecretStore`):** OAuth refresh tokens, IMAP app passwords, Bitwarden TOTP seeds, `AgentConfig`, `UnlockPolicy`, `AgentAuditLog`, custom OAuth Client IDs, and the 256-bit `MasterKey` live exclusively inside macOS **Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)** wrapped with **AES-256-GCM + HKDF-SHA256**.

---

## 4. Zero-Delay & Zero-Miss Ingestion Pipeline Analysis

### 4.1 Diagnosed Latency & Missed-OTP Root Causes

1. **`GmailAPI` Missed Emails (Explains "Visible in Gmail app, missing in AETHER until manual refresh"):**
   - **Previous bug:** `added(since:)` called `/history?startHistoryId=...&historyTypes=messageAdded&labelId=INBOX`.
   - **Why emails disappeared or stalled:**
     - Verification emails often receive Gmail category labels (`CATEGORY_UPDATES`, `CATEGORY_PROMOTIONS`, `CATEGORY_SOCIAL`) or user filter labels (`Skip Inbox` / auto-categorize) where `labelId=INBOX` + `historyTypes=messageAdded` misses `labelAdded` transitions or filtered deliveries.
     - Initial `inbox(since:)` used `q: "in:inbox after:..."` which ignored filtered/archived verification emails and suffered Unix second truncation skew.
     - `for id in ids` fetched raw MIME payloads **serially** one HTTP round-trip at a time.
2. **`APIWatcher` Fixed 10s Idle Poll + Exponential Sleep Trap:**
   - 10-second sleep meant up to 10s delay after email delivery at Google/Microsoft servers.
   - `seen.removeAll()` discarded the entire deduplication history whenever `seen.count > 1000`.
   - Transient network errors on wake triggered 5s → 10s → 20s → … → 120s sleep backoff without immediate wakeup when the user opened the shelf or settings.
3. **`OutlookAPI` Timestamp Boundary Edge Cases:**
   - `receivedDateTime ge \(cursor)` relied on the last fetched message timestamp; same-second arrivals or minor Graph clock drift could duplicate or skip edge items.
4. **`AppleMailStore` & `LocalWatcher` `.emlx` Flush Race:**
   - Mail.app frequently inserts the metadata row into `Envelope Index` **before** finishing writing `<rowid>.emlx` to `V*/.../Messages/`. Previously `LocalWatcher` then slept up to **30 seconds** (`interval = fseventsActive ? 30.0 : 1.0`) if directory FSEvents didn't re-fire cleanly, plus `AppleMailStore.open` always reset `position = 0`.

### 4.2 Upgraded Pipeline Architecture (Implemented in `v2.1.0`)

1. **Gmail Zero-Miss Strategy:**
   - Poll `history.list` with **both `historyTypes=messageAdded` AND `historyTypes=labelAdded`**, without locking out non-`INBOX` tabs. Check returned labels and skip only `TRASH`, `SPAM`, and `DRAFT` cleanly.
   - Perform **rolling recent-message reconciliation** every 4 polls (~18–20s) + on bootstrap/wake/manual check (`q: "newer_than:1h -in:trash -in:spam -in:drafts"`) against the bounded deduplication cache so **even if Gmail's `historyId` stream lags or skips a filter delivery, AETHER catches it automatically with zero user refresh!**
2. **Adaptive Burst Polling + Concurrent Batch Fetch (`APIWatcher`):**
   - **Burst Window (`2.5s` poll):** Automatically engages for 45s on startup, Mac wake, network reconnect, shelf widget open, or manual check — cutting average detection lag from ~5–10s down to **~1.2–2.5s**.
   - **Active Steady State (`5.0s` poll):** Halves steady-state waiting latency compared to 10s while avoiding Gmail/Graph quota exhaustion.
   - **Wakeable Poll Loop (`AsyncStream` signal):** `SourceMonitor.check(_:)` / `triggerBurst()` wakes sleeping watchers instantly instead of killing & recreating tasks cleanly.
   - **Concurrent Fetches (`TaskGroup`, max 4 in-flight):** Fetches multiple arriving messages simultaneously in parallel.
   - **Bounded FIFO `SeenIDBuffer(capacity: 2000)`:** Prevents sudden cache amnesia.
3. **Outlook Overlap Window:**
   - Rewinds cursor query safely by **5 seconds** (`receivedDateTime ge (last - 5s)`) backed by `SeenIDBuffer`, guaranteeing zero skipped same-second or skew-ordered Graph messages.
4. **Apple Mail Fast Pending-Body Follow-up (`0.6s`):**
   - `LocalStore.hasPendingBodies` notifies `LocalWatcher` when an `.emlx` file wasn't yet written on disk, triggering a **600ms rapid retry** until Mail.app flushes the message body (instead of stalling up to 30 seconds).

---

## 5. Sender Branding & Notch Presence Architecture

### 5.1 Notch Surfaces & Real Brand Icons

- **Notch HUD Strip & Expanded Card (`AetherHUDBridge`):**
  Upgraded from the generic data-only `DropletHUDCard` (limited to single monochrome SF symbols) to a bespoke **Droppy-native two-shape `DropletHUDRequest`** matching `DroppyShellMetrics` & `AdaptiveColors`:
  - **Compact Strip:** Leading wing shows **`AetherServiceAvatar`** (real cached icon or crisp offline Brand Badge like Facebook `#1877F2` `'f'`, Google `'G'`, GitHub charcoal, etc.) + short service title; trailing wing renders grouped monospaced code (`482 913`).
  - **Expanded Notch Card:** Displays:
    - **38pt Service Brand Icon** with tiny origin badge (`Mail` / `Messages` / `Key`)
    - **Service Name** (`Facebook`) + **Sender Identity** (`security@facebookmail.com` when available and `Show message previews` is enabled)
    - **Large Monospaced Copyable Code** + expiry badge
    - Tactile **Copy Code** / **Open Link** primary pill + **View** secondary pill.
- **Compact Live Activity Wing (`AetherDroplet.makeCompactLeading`):**
  Shows the live **`AetherServiceAvatar` (`18pt`)** for the active code alongside spaced monospaced digits in the trailing wing.
- **On-Device Brand Recognition (`AetherBrandCatalog`) + Privacy-Preserving Logo Cache (`AetherIconStore`):**
  Ships rich offline brand styling & recognizable marks for major 2FA providers (Facebook, Google, Apple, Microsoft, GitHub, Instagram, X/Twitter, Discord, PayPal, Stripe, OpenAI, Amazon, Slack, LinkedIn, Netflix, Spotify, Zoom, Notion, Uber, Airbnb, Cloudflare, Binance, Coinbase, Revolut, Wise, Steam) with **zero network calls** when `Show service logos` is disabled — and seamlessly upgrades to real downloaded favicons (stored under HMAC-hashed filenames) when enabled.

---

## 6. Apple-Native `DroppyKit` UI/UX Redesign Blueprint

1. **Consistent Colorful Static App-Style Row Icons (`AetherSettingsIconBadge`):**  
   Every toggle, picker, action row, and page link inside AETHER Settings uses uniform `22×22` (row) or `28×28` (page link) continuous squircle badges (`DroppyRadius.appIcon(forSide:)`) with rich macOS gradients and crisp white glyphs — eliminating the jarring mismatch between colorful page-link tiles and plain monochrome toggle symbols.
2. **Native Grouped Form Alignment (`DropletSettingsPane`, `DropletSettingsPage`, `Toggle`, `LabeledContent`):**  
   Retains `DropletSettingsPane` / `DropletSettingsPage` native Form plumbing so rows, switches, dividers, info-tip popovers, and columns stay 100% native across macOS 15+ and macOS 26.
3. **Decluttered Information Architecture (Zero Duplication, Zero Crowded Button Clusters):**
   - **Root Pane:** One clean action per row (`Vault protection` Lock/Unlock, `Notch shelf widget` Open Widget, `Test notification & HUD` Send Test Code), followed by 5 clear `Configuration` subpages.
   - **General:** Organized cleanly into `Arrival delivery`, `Automation`, and `Keyboard shortcuts` (redundant static host rows removed).
   - **Sources & accounts:** Separate cards so toggle rows (`What to catch`) never mix with navigation link tiles (`Filtering rules`); cleaner `Messages` & `Apple Mail` status switches with on-demand diagnostic expansion rather than 4-control trailing clusters; unified Mail account list + Add flow.
   - **Account Editor (OAuth):** Zero CodeCatch strings anywhere; clear **AETHER OAuth Client ID** setup disclosure + copyable Redirect URI + frictionless **App Password (IMAP)** tab.
   - **Micro-interactions:** Smooth `DroppyTransition` state swaps (`Copy` → `Copied` checkmark feedback), hover-to-reveal digits, clean grouped monospaced code formatting (`482 913`), warning amber countdown rings under 30s, and instant shelf-open burst refresh.

---

## 7. Next-Phase Roadmap (Beyond `v2.1.0`)

1. **Secure Enclave (`SecAccessControl` + Hardware Wrapping Key):** Bind the `MasterKey` directly to Secure Enclave (`biometryCurrentSet`) on Apple Silicon Macs where available, ensuring even a root process cannot extract the wrapping key offline.
2. **SPKI TLS Public-Key Pinning:** Validate Subject Public Key Info (SPKI) pin hashes inside `URLSessionDelegate` against Google & Microsoft root/intermediate CAs with graceful dual-pin backup rotation.
3. **Microsoft Graph Delta Query Sync (`me/mailFolders/inbox/messages/delta`):** Replace `receivedDateTime ge` filter polling with stateful opaque Graph delta tokens for true O(changes) enterprise Outlook scale.
4. **Google CASA Tier 2 Production Verification:** Once your GCP Brand (`AETHER`) is ready for public distribution without any Testing-mode 7-day refresh limit or unverified prompt, complete Google Brand Verification + CASA Tier 2 audit for `gmail.readonly`.


---

## 8. Competitive & Weaknesses (`W-01`–`W-26`) Closure Matrix (`v2.2.0`)

| Weakness / Rivalry Gap | Inheritance Baseline (`v2.0`) | AETHER Status (`v2.2.0`) |
| :--- | :--- | :--- |
| **`W-01` / Brand & OAuth provenance** | Hardcoded CodeCatch OAuth IDs & warning screen | **Closed.** Purged CodeCatch IDs; built-in first-party Google iOS (`210406503188-...`) & Microsoft Entra (`3265c45a-...`) IDs + `aether.png` identity + `/aether`, `/aether-policy`, `/aether-terms` pages spec. |
| **`W-02` / Native Notification vs Notch** | Basic banner card | **Closed.** Interactive `DropletNotification` (`Copy`, `Open`, `Dismiss`) + two-shape custom Notch HUD + Compact Live Activity (beats *bytemail* without switching mail clients). |
| **`W-03` / `W-13` Fixed 90s Clipboard & Overwrite Loss** | Fixed 90s clear; overwrote prior clipboard forever | **Closed (Beats *MessAuto*).** Configurable TTL (`30s`–`5m`) + safe prior-clipboard capture/restoration (`restoreClipboard`), while always wiping concealed secrets & locking hard. |
| **`W-04` / `W-12` Latency, Long Blobs & Regex Stalls** | `@MainActor` regex on large blobs | **Closed.** Precomputes `CodeExtractor` + `SignInLink` off `@MainActor` (`PrecomputedExtraction`), bounds giant inputs (`131_072` chars), and compresses Public Suffix List via LZMA. |
| **`W-15` Spam / Junk Coverage** | Excluded Spam/Junk globally | **Closed (Beats *Copy 2FA*).** Opt-in `includeJunkMail` checks Gmail `SPAM` & Outlook `junkemail` while mandating DMARC manual tap safety. |
| **`W-16` Sleep / Network / IMAP Latency** | 540s IMAP `IDLE`, 10s poll, 200ms FSEvents | **Closed (Beats *AutoCodeBar*).** 50 ms `FSEventWatcher`, 2.5s burst / 5.0s API polling, 240s IMAP keepalive with instant `PollWakeSignal`, and live per-source latency (`ms`) metrics. |
| **`W-18` Sender Spoofing (`DMARC`)** | Parsed `senderVerified` but still blind auto-copied | **Closed.** Blocks blind auto-copy/auto-type on DMARC failures (`blockUnverifiedAutoCopy`) and surfaces verified/unverified badges across HUD, Banners, Shelf, and Menu Bar. |
| **`W-23` Third-Party Favicon Tracking** | Plaintext `<domain>.png` cache filenames | **Closed.** Defaults `OFF`; bundles local crisp brand marks (`AetherBrandCatalog`); hashes opt-in fetched cache files via keyed `HMAC-SHA256`. |
| **`W-24` Blind Auto-Type Accessibility** | Typed into whatever window was active | **Closed (Beats *MessAuto* & *OTPfill*).** Refuses failed DMARC mail, blocks Slack/Discord/Messages/Notes/Zoom/Teams, verifies editable `AXUIElement` focus, and checks browser URL host against expected sender domain. |
| **Bundle Footprint Optimization** | 12.2 MB unstripped universal bundle / 3.17 MB ZIP | **Optimized.** `512×512` `aether.png` (`79 KB`), LZMA Public Suffix List, detached unused `AetherIPC` link, and `strip -x` + `zip -9` packaging. |
