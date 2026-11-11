# AETHER — Portfolio Web Pages Blueprint (`/aether`, `/aether-policy`, `/aether-terms`)

> **Target Domain:** `https://www.nilambarsonu.me`
> **App Name (Must match Google Cloud & Microsoft Entra Branding verbatim):** `AETHER`
> **App Version Referenced:** `2.2.0` (`DroppyKit v1.23.0`, `macOS 15.0+`, `Droppy 16.2.0+`, `GPL-3.0`)
> **Purpose:** Complete engineering, design, color, icon, SVG, and verbatim content specification for Claude to implement all three production OAuth-verification pages in the `www.nilambarsonu.me` portfolio repository and push cleanly to `main`.

---

## 0. Mandatory Google Cloud & Microsoft Entra Verification Rules

Before writing code, make sure every requirement below holds on the deployed live routes of `https://www.nilambarsonu.me`:

1. **Exact Routes & HTTP Status (No Auth Walls, No Redirect-to-GitHub Only):**
   - **Application Homepage:** `https://www.nilambarsonu.me/aether` (HTTP `200 OK`, SSR / pre-rendered HTML — do **not** redirect blindly to GitHub or render only an empty client-side spinner; Google OAuth reviewers & automated crawlers inspect the rendered DOM on your verified domain).
   - **Privacy Policy:** `https://www.nilambarsonu.me/aether-policy` (HTTP `200 OK`, publicly accessible without login, linked clearly in the header/footer of `/aether` and ideally also discoverable in the portfolio footer).
   - **Terms of Service:** `https://www.nilambarsonu.me/aether-terms` (HTTP `200 OK`, publicly accessible without login, linked clearly from `/aether` and `/aether-policy`).
2. **Domain Ownership & Branding Consistency:**
   - All three URLs live on the same verified root domain (`nilambarsonu.me`) added under **Authorized domains** in Google Cloud Console (`nilambarsonu.me`) and verified in **Google Search Console** under the **same Google account** that owns the Google Cloud OAuth project.
   - The page title, app icon/logo, and product name shown on `/aether`, `/aether-policy`, and `/aether-terms` must visibly say **`AETHER`** (matching your Google OAuth Consent Screen **App name** and uploaded **App logo**).
3. **Contact Email Placeholder (`[YOUR_SUPPORT_EMAIL]`):**
   - Replace every `[YOUR_SUPPORT_EMAIL]` placeholder below with the **exact Developer Contact Email / User Support Email** entered in Google Cloud Console Branding (for example `nilambarsonubehera@gmail.com` or `support@nilambarsonu.me`). Do not leave placeholders in production!
4. **Google API Services User Data Policy ("Limited Use"):**
   - Because `AETHER` requests `https://www.googleapis.com/auth/gmail.readonly`, Google Trust & Safety **strictly requires** the Privacy Policy (`/aether-policy`) to state explicitly how Gmail data is accessed, used on-device, stored, never sold/shared, never used for advertising/AI training, and how users revoke access. Exact compliant wording is provided in Section 5 below.
5. **Crawlers & `robots.txt`:**
   - Ensure `/aether`, `/aether-policy`, and `/aether-terms` are **not** blocked in `robots.txt` and carry normal `<title>` and `<meta name="description">` tags.

---

## 1. Visual Design System & Color Combination

All three pages should feel **unified with `nilambarsonu.me`** while adopting **AETHER's crisp Apple-native macOS dark/glass aesthetic** and exact droplet brand colors extracted from `Droplet/.droppykit/AETHER.icon/icon.json` and `Droplet/Sources/AETHER/UI/Shared/AetherServiceVisuals.swift`.

### 1.1 Dual-Mode Palette (Dark Default / Light Compatible)

> If your portfolio supports Dark + Light themes, bind CSS variables below; if dark-first, use the Dark Mode tokens as primary.

| Role | Dark Theme Token | Light Theme Token | Usage |
| :--- | :--- | :--- | :--- |
| **Page Background** | `#090B10` | `#F6F8FC` | Main canvas (`min-h-screen`) |
| **Ambient Hero Glow** | `radial-gradient(ellipse at top, rgba(37,128,255,0.16), transparent 60%)` | `radial-gradient(ellipse at top, rgba(37,128,255,0.10), transparent 60%)` | Subtle sky glow behind hero / header |
| **Primary Card Surface** | `#111622` (`rgba(17, 22, 34, 0.86)`) | `#FFFFFF` (`rgba(255, 255, 255, 0.92)`) | Grouped Apple-style rounded cards (`16px`–`20px` radius) |
| **Elevated / Sub-Card Surface** | `#171D2B` | `#F0F4FA` | Callouts, Limited Use box, Notch preview shell |
| **Squircle Icon Dark Plate** | `linear-gradient(135deg, #353535, #161616)` | `#1E2430` | Matches AETHER dark icon backing |
| **Card Border (Hairline)** | `rgba(255, 255, 255, 0.08)` | `rgba(15, 23, 42, 0.08)` | Crisp Apple hairline stroke (`1px`) |
| **Hover Border / Active Ring** | `rgba(145, 196, 255, 0.28)` | `rgba(37, 128, 255, 0.28)` | Interactive cards, pills, focus outlines |
| **Text Primary** | `#F4F7FB` | `#0F172A` | Headings, key labels |
| **Text Secondary** | `#A3B1C6` | `#475569` | Descriptions, body prose |
| **Text Muted / Captions** | `#6E7D96` | `#64748B` | Dates, timestamps, metadata rows |
| **Brand Accent Gradient (AETHER Blue)** | `linear-gradient(135deg, #91C4FF 0%, #2580FF 100%)` | `linear-gradient(135deg, #5BA8FF 0%, #1D6FF2 100%)` | App icon squircle, primary CTAs, active highlights |
| **Brand Accent Solid** | `#2580FF` / `#60A5FA` | `#1D6FF2` | Inline links, focus accents |
| **OTP Code Pill Surface** | `rgba(37, 128, 255, 0.14)` | `rgba(37, 128, 255, 0.10)` | Preview OTP chip (`482 913`) |
| **OTP Code Text** | `#91C4FF` (`font-mono font-semibold tracking-wider`) | `#1D4ED8` | Tabular monospace verification codes |

### 1.2 Semantic Squircle Badge Gradients (Matching AETHER Droppy Settings)

Every feature/section icon should use a crisp **Apple System Settings squircle tile** (`rounded-[24%]`, subtle top inner highlight `border-white/25`, crisp `white` icon centered at ~52% scale):

| Domain / Category | Gradient (`top-left` → `bottom-right`) | Meaning |
| :--- | :--- | :--- |
| **AETHER Brand / General** | `#91C4FF` → `#2580FF` | Core app identity, OTP capture, Notch HUD |
| **Vault & Cryptography** | `#FFB340` → `#EA580C` | Keychain AES-256-GCM, Touch ID lock, protection |
| **Gmail & Mail Sources** | `#FB7185` → `#E11D48` / `#F97316` → `#EA580C` | Gmail / Outlook / IMAP read-only watchers |
| **Messages & Local macOS** | `#4ADE80` → `#16A34A` | Messages SQLite & Apple Mail read-only access |
| **Privacy & Limited Use** | `#2DD4BF` → `#0D9488` | Zero-database architecture, Google Limited Use, deletion |
| **AI Agents & MCP Guardrails** | `#818CF8` → `#4F46E5` | Droppy MCP gating, DMARC alignment, Touch ID consent |
| **Terms & Legal / License** | `#94A3B8` → `#475569` | GPL-3.0 license, third-party notices, terms |

### 1.3 Typography & Spacing Tokens
- **Display / Headings / Body:** Clean sans-serif matching macOS SF Pro feel (`-apple-system, BlinkMacSystemFont, "SF Pro Display", "Inter", system-ui, sans-serif`) — reuse your portfolio's sans stack if it already loads Inter/Plus Jakarta/Geist.
- **Monospace (Codes, Scopes, Redirect URIs, Crypto specs):** `ui-monospace, "SF Mono", "JetBrains Mono", monospace` with `font-variant-numeric: tabular-nums`.
- **Reading Width:**
  - `/aether` (Product Showcase): Max width `1120px` (`max-w-5xl` / `max-w-6xl`), generous section spacing (`py-16` / `gap-6`).
  - `/aether-policy` & `/aether-terms` (Legal Documents): Max width `820px` (`max-w-3xl`) for main prose column + optional sticky left table-of-contents sidebar on `lg:` (`max-w-5xl` container), `leading-relaxed` (`1.7` line height), `15px`–`16px` body font size for effortless reading by Google Trust & Safety reviewers.

---

## 2. AETHER App Icon & Page Icon Map

### 2.1 Official AETHER App Icon (`Droplet/Assets/aether.png` / `site/assets/icon-512.png`)

**Primary Asset (Use Everywhere):** Copy `Droplet/Assets/aether.png` (`512×512` crisp PNG, 3D glass peach-pink-violet wallet folder with `[O] [T] [P]` tabs and cyan indicator light) into your portfolio's `public/images/aether-icon.png` (and reuse `site/assets/icon-180.png`, `icon-256.png`, `icon-512.png`). Render it inside hero headers, the AETHER sub-navigation bar (`28×28` rounded-lg), and OpenGraph tags so your live `/aether` page icon matches the **exact logo uploaded in Google Cloud & Microsoft Entra Branding**.

> **Accent Color Harmony with New Icon:** Pair primary brand CTAs with soft warm/cool accents complementing `aether.png` (`#FFA888` Peach -> `#C084FC` Violet alongside `#38BDF8` / `#2580FF` Azure indicator highlight).

**Lightweight SVG Fallback (optional for small `16×16` UI accents):**

```svg
<svg width="64" height="64" viewBox="0 0 64 64" fill="none" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="AETHER app icon">
  <defs>
    <linearGradient id="aetherOtpGrad" x1="8" y1="8" x2="56" y2="56" gradientUnits="userSpaceOnUse">
      <stop offset="0%" stop-color="#FFA987"/>
      <stop offset="52%" stop-color="#F48FB1"/>
      <stop offset="100%" stop-color="#B39DFF"/>
    </linearGradient>
  </defs>
  <rect x="2" y="2" width="60" height="60" rx="14" fill="url(#aetherOtpGrad)"/>
  <circle cx="15" cy="23" r="3" fill="#67E8F9"/>
  <text x="32" y="42" text-anchor="middle" fill="white" font-family="ui-rounded, system-ui" font-size="16" font-weight="700">OTP</text>
</svg>
```

### 2.2 Lucide Icon Mapping (For React / Tailwind / Next.js / Astro)

Use **`lucide-react`** (or raw Lucide SVGs) inside colored `32×32` (`rounded-lg`) or `24×24` (`rounded-md`) squircle tiles so the web pages feel visually identical to AETHER inside Droppy:

| Section / Concept | Recommended Icon (`lucide-react`) | Squircle Color |
| :--- | :--- | :--- |
| AETHER App Identity | Custom AETHER SVG above | `#91C4FF → #2580FF` |
| Instant Notch HUD & OTP Capture | `Sparkles` or `KeyRound` | `#91C4FF → #2580FF` |
| Gmail OAuth (`gmail.readonly`) | `Mail` | `#FB7185 → #E11D48` |
| Microsoft Outlook / M365 (`Mail.Read`) | `Inbox` | `#60A5FA → #2563EB` |
| Apple Mail & Messages (Local Read-Only) | `MessageSquare` / `Laptop` | `#4ADE80 → #16A34A` |
| Zero-Database / Volatile RAM Retention | `DatabaseZap` or `MemoryStick` | `#2DD4BF → #0D9488` |
| AES-256-GCM Keychain & Touch ID | `ShieldCheck` / `Fingerprint` | `#FFB340 → #EA580C` |
| Google API Limited Use Compliance | `BadgeCheck` / `Lock` | `#2DD4BF → #0D9488` |
| Optional Service Brand Logos | `Image` / `GlobeLock` | `#38BDF8 → #0284C7` |
| Revocation & User Controls | `Trash2` / `UserX` | `#F87171 → #DC2626` |
| AI Agent / MCP Approval Gate | `Terminal` / `Bot` | `#818CF8 → #4F46E5` |
| Open Source GPL-3.0 & Legal Terms | `Scale` / `FileText` | `#94A3B8 → #475569` |
| Download / GitHub Release | `Download` / `Github` | Brand button |

---

## 3. Shared Page Chrome (All 3 Routes)

Include a subtle top **AETHER Sub-Header Bar** right below or integrated with the portfolio navigation so reviewers can effortlessly click between all three verified URLs:
- **Left:** AETHER SVG Logo (`28×28`) + **`AETHER`** badge (`by Nilambar Behera` · `for Droppy macOS`)
- **Center/Right Sub-Nav Pills:**
  - `Overview` → `/aether`
  - `Privacy Policy` → `/aether-policy`
  - `Terms of Service` → `/aether-terms`
  - `GitHub` → `https://github.com/NilambarSonu/AETHER` (external icon)
- **Bottom Page Footer (visible on all 3 routes):**
  - App Name & License: `AETHER for Droppy — Released under GNU GPL v3.0. Copyright © 2026 Nilambar Behera.`
  - Attribution note: `Evolved from open-source CodeCatch (GPL-3.0). Built with DroppyKit SDK.`
  - Quick links: `Home (/aether)` · `Privacy Policy (/aether-policy)` · `Terms of Service (/aether-terms)` · `Contact ([YOUR_SUPPORT_EMAIL])`

---

## 4. Page 1 Specification — Application Home Page (`/aether`)

> **URL to paste into Google Cloud Console ("Application home page link"):**
> `https://www.nilambarsonu.me/aether`

### 4.1 Layout Structure
1. **Hero Section (2-Column Desktop / Stacked Mobile)**
   - **Left Column:**
     - Pill badge (`bg-sky-500/10 border border-sky-400/20 text-sky-300`): `[KeyRound icon] Standalone Droppy Droplet · macOS 15+`
     - **H1:** `AETHER`
     - **Tagline (Lead Paragraph):** `Instant verification codes, sign-in links, and 2FA right in the Droppy notch.`
     - **Supporting Copy:** `AETHER runs inside Droppy on your Mac to surface one-time verification codes (OTPs), magic sign-in links, password reset links, and Bitwarden TOTP secrets the moment they arrive — with zero companion app, zero cloud servers, and strict on-device encryption.`
     - **CTA Row:**
       - Primary Gradient Button (`#91C4FF → #2580FF`, dark shadow): `[Download icon] Download Latest Release` → `https://github.com/NilambarSonu/AETHER/releases/latest`
       - Secondary Glass Button: `[Github icon] View Source (GPL-3.0)` → `https://github.com/NilambarSonu/AETHER`
     - **Quick Trust Links Row (Small muted links right under CTAs):**
       - `Privacy Policy` (`/aether-policy`) · `Terms of Service` (`/aether-terms`) · `Security Architecture` (`#security`)
   - **Right Column — Visual Showcase Card (Simulated MacBook Notch HUD Mockup):**
     - Sleek dark matte bezel container (`#0B0D12`, subtle top border, `rounded-2xl`) simulating the top of a Mac screen with a centered MacBook notch cutout!
     - Inside the expanded Notch HUD card:
       - Left squircle (`38×38`, `#1877F2` Facebook blue badge with white `f` + tiny blue envelope badge):
       - Title: **`Facebook`**
       - Subtitle (`text-xs text-slate-400`): `security@facebookmail.com · Mail · Expires in 4m 18s`
       - Right OTP chip: **`482 913`** (`font-mono text-lg font-bold text-sky-300 bg-sky-500/15 px-3 py-1 rounded-lg`)
       - Action pills below: `[Copy Code (blue filled)]` · `[View in Droppy (subtle dark pill)]`
     - Caption below visual: `Live Notch HUD & Shelf preview — processed 100% locally in memory on your Mac.`

2. **Section: What AETHER Does (6 Feature Cards — 3×2 Grid)**
   - **Card 1 (`Sparkles` · Blue squircle):** **Notch HUD, Banners & Auto-Copy** — *Appears subtly around your MacBook notch, presents native Droppy banners, copies verification codes automatically with local-only/concealed pasteboard flags, and optionally clears the clipboard after 90 seconds.*
   - **Card 2 (`Mail` · Rose/Orange squircle):** **Gmail & Outlook OAuth PKCE + IMAP** — *Connects directly from your Mac to Google Gmail (`gmail.readonly`), Microsoft Outlook / 365 (`Mail.Read`), iCloud, Yahoo, or any custom TLS IMAP mailbox — using adaptive polling & IMAP IDLE with zero intermediate relay servers.*
   - **Card 3 (`MessageSquare` · Green squircle):** **Messages & Apple Mail Watchers** — *Reads local macOS Messages and Apple Mail stores strictly in read-only mode (requires macOS Full Disk Access granted to Droppy) for sub-second SMS and inbox OTP capture.*
   - **Card 4 (`ShieldCheck` · Amber squircle):** **Vault Protection & Touch ID** — *Lock the Shelf Widget and Menu Bar popover behind macOS Touch ID / user password. Hide unlocked code windows from screen sharing and recordings (`NSWindow.sharingType = .none`).*
   - **Card 5 (`KeyRound` · Cyan squircle):** **Bitwarden TOTP Authenticator** — *Optionally imports TOTP authenticator seeds using the local Bitwarden CLI (`bw`), stores them inside your Keychain wrapped with AES-256-GCM, and lets you pin frequently used logins.*
   - **Card 6 (`Terminal` · Indigo squircle):** **AI Agent / MCP Guardrails** — *Lets local coding agents request an active verification code through Droppy's built-in MCP tools (`get_code`, `get_status`, `list_recent_services`) gated behind explicit Touch ID approval, DMARC alignment verification, and strict rate limits.*

3. **Section: Why AETHER Requests Read-Only Email Permissions (Important for Google & Microsoft Reviewers)**
   - Clean bordered callout box (`bg-[#111622] border-sky-500/20`):
   - **Heading:** `Transparent Read-Only Access (`gmail.readonly` & `Mail.Read`)`
   - **Body:**
     > AETHER connects directly from your macOS device to your email provider using OAuth 2.0 with PKCE. It requests **strictly read-only access** (`https://www.googleapis.com/auth/gmail.readonly` for Google; `User.Read` and `Mail.Read` with `offline_access` for Microsoft) for **one purpose only**: detecting recently received one-time verification codes, sign-in links, and password reset links locally inside Droppy so you can copy or open them without switching apps.
     >
     > - **No External Servers:** Nilambar Behera operates zero backend servers for AETHER. Your emails, OAuth tokens, and verification codes never pass through or touch any developer-controlled server.
     > - **No Modification or Sending:** AETHER cannot compose, send, forward, edit, archive, or delete any message in your mailbox.
     > - **Full Google Limited Use Compliance:** AETHER adheres strictly to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. See full details in our [Privacy Policy](/aether-policy).

4. **Section: Security Architecture at a Glance (`#security` — 4 Compact Cards)**
   - **Zero-Database OTP Design:** *Arriving verification codes and recovery emails live only in volatile RAM and expire automatically according to your retention preference — never written to SQLite, JSON, or disk logs.*
   - **AES-256-GCM + HKDF-SHA256 Keychain Sealing:** *OAuth refresh tokens, IMAP app passwords, Bitwarden TOTP seeds, security policies, and agent audit logs are sealed in macOS Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) using device-only keys and domain-bound AAD.*
   - **Fail-Closed Policy Verification:** *If Keychain policy material is modified or corrupted outside AETHER, unlock rules and agent permissions fail closed to locked/disabled and require user re-authentication.*
   - **Privacy-Preserving Icon Cache:** *Third-party brand logo downloads are disabled by default (using bundled vector/monogram brand marks offline). When explicitly enabled, only the service hostname is queried and cached locally under keyed HMAC-SHA256 hashes.*

5. **Section: System Requirements & Open Source Credits**
   - Two-column clean metadata card:
     - **Requirements:** `macOS 15.0 (Sequoia) or later` · `Droppy 16.2.0 or later` · `Universal binary (Apple Silicon & Intel)`
     - **License & Attribution:** `Open source under GNU GPL v3.0.` Evolved from upstream open-source [CodeCatch](https://github.com/ugzv/CodeCatch) by Uros and built for [Droppy](https://getdroppy.app) with `DroppyKit`.
     - **Legal & Support:** Links to `/aether-policy` (**Privacy Policy**), `/aether-terms` (**Terms of Service**), GitHub Issues, and `[YOUR_SUPPORT_EMAIL]`.

---

## 5. Page 2 Specification — Privacy Policy (`/aether-policy`)

> **URL to paste into Google Cloud Console ("Application privacy policy link"):**
> `https://www.nilambarsonu.me/aether-policy`

### 5.1 Visual Structure
- **Top Breadcrumb & Title Header:** `AETHER / Privacy Policy` · **H1:** `Privacy Policy for AETHER` · **Effective Date:** `November 11, 2026` · **Last Updated:** `November 11, 2026`
- **4-Chip "At a Glance" Summary Grid (Teal / Blue glass cards above legal prose):**
  1. `[ServerOff]` **Zero Developer Servers** — *Direct device-to-provider connections only.*
  2. `[DatabaseZap]` **Zero OTP Database** — *Detected codes exist in RAM only and are cleared cleanly.*
  3. `[Lock]` **Keychain + AES-256-GCM** — *Credentials stay sealed locally (`ThisDeviceOnly`).*
  4. `[BadgeCheck]` **Google Limited Use Compliant** — *Never sold, shared, used for ads, or trained on AI.*
- **Main Policy Body (Sticky TOC on desktop `lg:` + clean numbered prose sections below).**

### 5.2 Complete Privacy Policy Copy (Use Verbatim, Only Fill `[YOUR_SUPPORT_EMAIL]`)

```markdown
# Privacy Policy for AETHER

**Effective Date:** November 11, 2026
**Last Updated:** November 11, 2026
**Application:** AETHER (Standalone Droplet for Droppy on macOS)
**Developer:** Nilambar Behera ([https://www.nilambarsonu.me](https://www.nilambarsonu.me))
**Contact Email:** [YOUR_SUPPORT_EMAIL]

## 1. Overview and Core Privacy Commitment

AETHER is a free, open-source macOS verification code and 2FA utility (distributed under the GNU General Public License v3.0) designed to run locally inside the Droppy host application on your Mac.

**AETHER does not operate any remote servers, cloud databases, analytics pipelines, or telemetry endpoints.** All message inspection, verification code parsing, link validation, TOTP generation, and storage encryption occur exclusively on your local Mac device.

## 2. Information AETHER Accesses (Strictly User-Configured & Local)

AETHER accesses only the data sources you explicitly enable inside **Droppy → Settings → Droplets → AETHER**:

### 2.1 Google Gmail (OAuth 2.0 with PKCE)
- **Requested Scope:** `https://www.googleapis.com/auth/gmail.readonly` (read-only access).
- **What is Accessed:** Message metadata and MIME message text/HTML from recent emails in your connected Gmail account via direct HTTPS requests from your Mac to Google's Gmail API (`gmail.googleapis.com`) and OAuth endpoints (`accounts.google.com`, `oauth2.googleapis.com`).
- **How it is Used:** Parsed immediately in memory on your Mac to detect one-time verification codes (OTPs), sign-in links, password reset links, sender name/domain, and expiration hints.
- **No Write Access:** AETHER never sends, modifies, forwards, labels, archives, or deletes your Gmail messages.

### 2.2 Microsoft Outlook / Microsoft 365 (OAuth 2.0 with PKCE)
- **Requested Scopes:** `offline_access`, `User.Read`, and `Mail.Read`.
- **What is Accessed:** Your signed-in email address/profile identifier (`User.Read`) and recent mailbox messages (`Mail.Read`) directly from your Mac via Microsoft Graph (`graph.microsoft.com`) and Microsoft identity endpoints (`login.microsoftonline.com`).
- **How it is Used:** Used solely to identify your connected mailbox and detect arriving verification codes and sign-in/reset links locally in memory.

### 2.3 Custom IMAP Mailboxes (iCloud Mail, Yahoo, Fastmail, Custom Servers)
- **What is Accessed:** Hostname, port, username/email, app-specific password (if configured), and recent inbox message headers/bodies over TLS IMAP.
- **How it is Used:** Monitored directly from your Mac to detect verification codes and sign-in links.

### 2.4 Local macOS Messages and Apple Mail (Optional, Full Disk Access Required)
- **What is Accessed:** If you enable **Messages** or **Apple Mail** monitoring and grant macOS **Full Disk Access** to Droppy, AETHER opens Apple's local Messages database (`chat.db`, strictly read-only) and Apple Mail's local `Envelope Index` / `.emlx` files (strictly read-only) on your Mac.
- **How it is Used:** Detects arriving SMS/iMessage and Apple Mail verification codes locally. Nothing from Messages or Apple Mail ever leaves your device.

### 2.5 Bitwarden TOTP Secrets (Optional)
- **What is Accessed:** If you trigger a Bitwarden import, AETHER invokes the official local `bw` CLI tool on your Mac using your credentials to import TOTP `otpauth://` authenticator items you choose to import. Your Bitwarden master password is used only transiently for that local CLI unlock/sync operation and is not persistently stored by AETHER.

### 2.6 Optional Service Brand Logos ("Show Service Logos" — Disabled by Default)
- **Default Behavior:** **Disabled (`false`) by default.** Out of the box, AETHER displays crisp bundled on-device icons and monogram badges with **zero network calls** for logos.
- **If You Explicitly Enable It:** AETHER sends only the bare service domain hostname (e.g., `github.com` — never your email address, OTP code, or message text) over an ephemeral, cookie-less HTTPS request to public icon proxies (`https://www.google.com/s2/favicons` and fallback `https://icons.duckduckgo.com/ip3/<domain>.ico`). Fetched icons are stored locally in `~/Library/Caches/AETHER/Icons/` under keyed HMAC-SHA256 hashed filenames so directory listings do not expose the services you use.

## 3. Google API Services User Data Policy (Limited Use Disclosure)

**AETHER's use and transfer to any other app of information received from Google APIs strictly adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements.**

Specifically, regarding data obtained through Google Gmail APIs (`gmail.readonly`):
1. **Purpose Limitation:** Access is strictly limited to reading incoming messages locally on your device to identify and present verification codes, sign-in links, password reset links, and optional recent-email diagnostics inside Droppy.
2. **No Transfer or Sale:** We **never** sell, rent, trade, or transfer Google user data to any third parties, advertisers, data brokers, or developer servers (we do not operate servers that receive your mail data).
3. **No Human Reading:** The developer and any third party have zero technical ability to read your emails or access your tokens. All processing happens locally inside your macOS user session unless you explicitly submit debugging logs or screenshots yourself when requesting support.
4. **No Advertising or AI/ML Training:** Google user data is **never** used for personalized advertising, profiling, creditworthiness assessment, or training generalized or external machine learning / AI models.
5. **Local AI Agent MCP Gating (Opt-In Only):** If you explicitly enable AETHER's local AI Agent / MCP integration inside Droppy settings, local tools (`get_code`, `get_status`, `list_recent_services`) operate strictly on your machine, check DMARC domain alignment where applicable, enforce rate limits, and require your explicit Touch ID / user approval per request before releasing a single verification code to a local coding agent. No raw mailbox contents or Google OAuth tokens are exposed to MCP tools.

## 4. How Data is Stored and Protected on Your Mac

AETHER follows a **Zero-Database Architecture** for detected codes:
- **No On-Disk OTP Database:** Arriving verification codes, message previews, and unmatched recent-email diagnostics reside **exclusively in volatile system memory (RAM)** and are automatically purged on expiry, when macOS locks (when configured), or when Droppy / AETHER closes.
- **Sealed Keychain Storage:** Persistent secrets (OAuth refresh tokens, IMAP app passwords, custom OAuth Client IDs, Bitwarden TOTP seeds, security unlock policies, agent access rules, and the local agent request log) are stored locally in the **macOS Keychain** (`app.getdroppy.droplet.aether`) with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (preventing iCloud Keychain synchronization across devices) and wrapped with **AES-256-GCM authenticated encryption** using **HKDF-SHA256** domain subkeys bound with key-specific Additional Authenticated Data (AAD).
- **Volatile Access Tokens:** Short-lived OAuth bearer access tokens exist only in memory and are cleared immediately when you lock the vault, when your Mac sleeps, or when AETHER stops.
- **Biometric / Password Lock & Anti-Capture:** Vault protection (Touch ID / macOS account password), fail-closed policy checks, clipboard concealment/local-only flags with optional 90-second auto-wipe, and `NSWindow.sharingType = .none` screen-capture protection help keep displayed codes private.

## 5. Third-Party Services and SDKs

Depending on the features you choose to connect, AETHER communicates directly from your Mac only with:
- **Google LLC** (`accounts.google.com`, `oauth2.googleapis.com`, `gmail.googleapis.com`) — governed by Google's Privacy Policy when you connect Gmail.
- **Microsoft Corporation** (`login.microsoftonline.com`, `graph.microsoft.com`) — governed by Microsoft's Privacy Statement when you connect Outlook / Microsoft 365.
- **Your Chosen IMAP Provider** (e.g., Apple iCloud, Yahoo, or your mail host) — when you configure IMAP.
- **Google / DuckDuckGo Favicon Endpoints** — only if you opt into `Show service logos`.
- **Droppy Host Runtime (`DroppyKit`)** — AETHER runs dynamically inside Droppy on macOS to display HUDs, notification banners, shelf widgets, settings UI, and optional local shortcuts/MCP bridges.

## 6. Data Retention, Deletion, and Revoking Access

Because all data remains locally under your control:
- **Instant Account Removal in AETHER:** Removing a connected Gmail, Microsoft, or IMAP account inside **Droppy → Settings → Droplets → AETHER → Sources & accounts** deletes its locally stored credentials/tokens from the macOS Keychain, attempts remote OAuth token revocation where supported (e.g., Google `oauth2.googleapis.com/revoke`), and purges its in-memory messages.
- **Revoke Access via Google:** You can revoke AETHER's access to your Gmail account at any time from your Google Account Security permissions page: [https://myaccount.google.com/permissions](https://myaccount.google.com/permissions).
- **Revoke Access via Microsoft:** You can revoke AETHER's access to your Microsoft account at any time from Microsoft's app consent portal: [https://account.live.com/consent/Manage](https://account.live.com/consent/Manage).
- **Complete Removal:** Clearing Bitwarden codes, resetting agent logs, or removing `AETHER.droplet` from Droppy removes stored items; you may also remove any residual cached icon directory at `~/Library/Caches/AETHER/` and Keychain items labeled `app.getdroppy.droplet.aether` via macOS Keychain Access.

## 7. Children's Privacy

AETHER is not directed to individuals under the age of 13 (or the minimum digital consent age in your jurisdiction), and the developer does not knowingly collect personal information from children.

## 8. Open Source Transparency

AETHER is open source under the GNU General Public License v3.0 (GPL-3.0). Anyone can audit the complete network, parsing, and cryptography implementation at:
[https://github.com/NilambarSonu/AETHER](https://github.com/NilambarSonu/AETHER)

## 9. Changes to This Privacy Policy

If AETHER introduces changes that affect data handling, scopes, or permissions, we will update this page with a revised "Last Updated" date before releasing the corresponding version.

## 10. Contact Us

If you have questions, security reports, or privacy requests regarding AETHER or this Privacy Policy, contact:

- **Developer:** Nilambar Behera
- **Email:** [YOUR_SUPPORT_EMAIL]
- **Website:** [https://www.nilambarsonu.me/aether](https://www.nilambarsonu.me/aether)
- **Source & Issue Tracker:** [https://github.com/NilambarSonu/AETHER](https://github.com/NilambarSonu/AETHER)
```

---

## 6. Page 3 Specification — Terms of Service (`/aether-terms`)

> **URL to paste into Google Cloud Console ("Application terms of service link"):**
> `https://www.nilambarsonu.me/aether-terms`

### 6.1 Visual Structure
- Matches `/aether-policy` typography and card chrome (`max-w-3xl` prose or sticky sidebar layout).
- Top summary strip with 3 small gray-slate squircle pills:
  - `[Scale]` **GNU GPL v3.0 Open Source**
  - `[Laptop]` **Requires macOS 15+ & Droppy 16.2+**
  - `[ShieldAlert]` **Provided "AS IS" without Warranty**

### 6.2 Complete Terms of Service Copy (Use Verbatim, Only Fill `[YOUR_SUPPORT_EMAIL]`)

```markdown
# Terms of Service for AETHER

**Effective Date:** November 11, 2026
**Last Updated:** November 11, 2026
**Application:** AETHER (Standalone Droplet for Droppy on macOS)
**Developer:** Nilambar Behera ([https://www.nilambarsonu.me](https://www.nilambarsonu.me))
**Contact Email:** [YOUR_SUPPORT_EMAIL]

## 1. Acceptance of Terms

By downloading, installing, or using **AETHER** (`AETHER.droplet`), or by connecting an email or local message source to AETHER inside Droppy, you agree to these Terms of Service ("Terms") and our [Privacy Policy](/aether-policy). If you do not agree, do not install or use AETHER and remove any connected accounts.

## 2. Description of Service

AETHER is a free, open-source macOS droplet plugin built for **Droppy** (`Droppy.app`). It runs locally on your computer to monitor user-selected sources (Messages, Apple Mail, Google Gmail via OAuth, Microsoft Outlook / Microsoft 365 via OAuth, IMAP accounts, and optionally imported Bitwarden TOTP items) and present verification codes, sign-in links, password reset links, and TOTP codes in Droppy's interface.

AETHER is provided strictly as a local client-side productivity and security utility and does not provide cloud hosting, email accounts, or remote synchronization services.

## 3. Open-Source License and Third-Party Attribution

- **GNU GPL v3.0:** AETHER's source code is licensed under the **GNU General Public License, Version 3.0 (GPLv3)**, available in full at [https://github.com/NilambarSonu/AETHER/blob/main/LICENSE](https://github.com/NilambarSonu/AETHER/blob/main/LICENSE). Where any conflict arises between open-source rights granted by GPLv3 and these Terms regarding source redistribution or modification, GPLv3 governs your rights in the software code.
- **Upstream Credits:** AETHER evolved from the open-source [CodeCatch](https://github.com/ugzv/CodeCatch) project (GNU GPLv3, Copyright © 2024–2026 Uros / CodeCatch contributors) with modifications and new components Copyright © 2026 Nilambar Behera.
- **DroppyKit Runtime:** AETHER targets **DroppyKit SDK** (Copyright © 2026 Jordy Spruit) and executes inside the Droppy macOS application; your use of Droppy itself remains governed by Droppy's own terms and licenses.

## 4. Eligibility and System Requirements

To run AETHER you must independently provide and maintain:
- A compatible Apple Mac running **macOS 15.0 (Sequoia)** or later.
- **Droppy version 16.2.0** or later installed on your Mac.
- Appropriate macOS permissions where desired by you (such as **Full Disk Access** granted to Droppy for local Messages/Apple Mail inspection, or **Accessibility** for opt-in auto-typing).

## 5. Acceptable Use and Account Authorization

You represent and agree that:
1. You will connect **only email accounts, mailboxes, vaults, and device data that you own or are explicitly authorized by the account owner/organization to access**.
2. You will not use AETHER to intercept, scrape, harvest, or redistribute communications belonging to other individuals without authorization, nor to violate applicable computer misuse, privacy, or telecommunications laws.
3. If you enable AETHER's optional **Auto-Type** or **AI Agent / MCP** features, you accept sole responsibility for reviewing active destination apps/fields and approving Touch ID / password prompts before releasing any code.
4. You will comply with the applicable terms of service of any connected third-party provider, including **Google LLC** (Gmail API Terms & Google Account Terms) and **Microsoft Corporation** (Microsoft Services Agreement / Entra Terms).

## 6. Security Responsibilities

AETHER incorporates on-device safeguards including Keychain encryption (`AES-256-GCM`), Touch ID vault lock options, volatile RAM code handling, and suspicious link/DMARC domain warnings. However:
- You remain solely responsible for keeping your Mac account, macOS login password, Touch ID enrollment, Droppy installation, and Bitwarden vault credentials secure.
- You should always verify the sender domain and destination URL before clicking sign-in or password reset links presented by any tool.
- You are responsible for downloading official releases only from verified sources (`https://github.com/NilambarSonu/AETHER/releases`) and checking SHA-256 checksums where appropriate.

## 7. Third-Party Services Availability

AETHER depends on APIs, authentication endpoints, local database schemas, and host interfaces operated by third parties (Google, Microsoft, Apple macOS, Bitwarden CLI, and Droppy). Those providers may change rate limits, OAuth policies, API fields, or OS restrictions at any time, which can temporarily or permanently affect AETHER compatibility without liability to the developer.

## 8. Disclaimer of Warranties

**TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW (AND CONSISTENT WITH SECTIONS 15–16 OF THE GNU GPLv3), AETHER IS PROVIDED "AS IS" AND "AS AVAILABLE", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED**, INCLUDING WITHOUT LIMITATION ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, UNINTERRUPTED DELIVERY, OR 100% CODE DETECTION ACCURACY. You should never rely solely on AETHER as an unrecoverable backup method for critical multi-factor authentication access.

## 9. Limitation of Liability

**TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW (AND CONSISTENT WITH SECTION 16 OF THE GNU GPLv3), IN NO EVENT SHALL THE DEVELOPER OR CONTRIBUTORS BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES**, OR ANY LOSS OF DATA, LOSS OF ACCOUNT ACCESS, LOCKOUTS, LOST PROFITS, OR SECURITY INCIDENTS ARISING OUT OF OR IN CONNECTION WITH YOUR USE OR INABILITY TO USE AETHER, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.

## 10. Suspension, Termination, and Revocation

You may stop using AETHER at any time by disabling or deleting the droplet in **Droppy → Settings → Droplets → AETHER**, removing connected accounts inside AETHER, and revoking OAuth access in your Google or Microsoft account security settings. Because the developer hosts no user accounts, no developer action is required to terminate service on your device; however, third-party API providers may revoke OAuth client access independently if required by their platform policies.

## 11. Changes to These Terms

We may update these Terms of Service periodically to reflect new releases, legal requirements, or API policy updates. Continued use of AETHER after updates are posted on this page constitutes acceptance of the revised Terms.

## 12. Contact

Questions regarding these Terms, licensing, or notices can be directed to:

- **Developer:** Nilambar Behera
- **Email:** [YOUR_SUPPORT_EMAIL]
- **Website:** [https://www.nilambarsonu.me/aether](https://www.nilambarsonu.me/aether)
- **Repository:** [https://github.com/NilambarSonu/AETHER](https://github.com/NilambarSonu/AETHER)
```

---

## 7. Copy-Paste Instructions for Claude in Your Portfolio Repo

When you open your portfolio codebase (`www.nilambarsonu.me`) with Claude, give it this file plus the prompt below:

> **Prompt for Claude:**
> *"Read this specification carefully. Build three production-ready, statically/server-rendered routes in my portfolio codebase using our existing framework styling plus the exact color tokens, Lucide/squircle icons, SVG AETHER mark, and verbatim copy defined here:*
> 1. `/aether` *(Application Home Page)*
> 2. `/aether-policy` *(Privacy Policy)*
> 3. `/aether-terms` *(Terms of Service)*
> *Use my real support email in place of `[YOUR_SUPPORT_EMAIL]`, ensure all three routes render full HTML on initial SSR load (`HTTP 200`, no auth wall, crawlable by Google), link cleanly between all three routes in a shared AETHER sub-header & footer, verify build/typecheck/lint cleanly, and push to `main`."*

### Post-Push Google Cloud OAuth Verification Checklist
Once Claude pushes to `main` and `https://www.nilambarsonu.me` deploys:
1. Run `curl -I https://www.nilambarsonu.me/aether`, `curl -I https://www.nilambarsonu.me/aether-policy`, and `curl -I https://www.nilambarsonu.me/aether-terms` and confirm all return `HTTP/2 200`.
2. In **Google Cloud Console → Google Auth platform → Branding**:
   - **App name:** `AETHER`
   - **App logo:** Upload AETHER icon (`120×120` PNG)
   - **Application home page link:** `https://www.nilambarsonu.me/aether`
   - **Application privacy policy link:** `https://www.nilambarsonu.me/aether-policy`
   - **Application terms of service link:** `https://www.nilambarsonu.me/aether-terms`
   - **Authorized domains:** `nilambarsonu.me`
3. Verify `nilambarsonu.me` in **Google Search Console** under the same Google account owning the GCP project.
4. Create your **iOS** OAuth Client ID (Bundle ID `app.getdroppy.droplet.aether`) for Google + **Mobile & desktop** App Registration (`app.getdroppy.droplet.aether://auth`) for Microsoft Entra, and either paste them straight into AETHER Settings or share the Client IDs so they can be bundled into the next AETHER release.
