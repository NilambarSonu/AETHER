# AETHER Phase 2B — Service Icon & Favicon Privacy Hardening

## 1. Executive Summary

In Phase 2B, AETHER changes the default setting for `Prefs.serviceIcons` from `true` (opt-out) to `false` (opt-in).

This architectural modification guarantees that by default:
- **Zero outbound network queries** are generated when messages, emails, or verification codes are processed.
- No third-party network proxy or CDN can observe which services, domains, or senders the user is receiving authentication codes from.
- All local visual badges fall back cleanly to native, local SF Symbols or system mail badges.
- Users who desire remote high-resolution service brand favicons can explicitly opt in through Settings.

---

## 2. Threat Model & Privacy Justification

### 2.1 The Privacy Exposure in Default Favicon Lookups
In legacy versions, when an incoming OTP or notification arrived from `sender@paypal.com` or `service@github.com`, `IconStore.load(domain)` was invoked automatically:
1. `serviceIcons` was registered as `true` in `UserDefaults`.
2. The application dispatched an HTTPS `GET` request to:
   `https://www.google.com/s2/favicons?domain=example.com&sz=128`
   (or fallback to DuckDuckGo: `https://icons.duckduckgo.com/ip3/example.com.ico`).
3. **The Information Leak:** Although the message body and OTP code were never sent over the network, the **domain name** of every OTP sender was transmitted in real time to external proxy endpoints (Google / DuckDuckGo).
4. An external observer, CDN, or network logger could infer:
   - What services the user holds accounts with.
   - The exact timestamp when a user requested a login code or password reset.
   - User behavioral patterns and login frequency.

### 2.2 Hardened Privacy Policy in Phase 2B
Under AETHER's local-first, privacy-first charter:
- **Zero Telemetry & Zero Unprompted Network Egress:** A verification utility must not disclose authentication activity or metadata to external parties without explicit, informed user consent.
- **Default Secure & Private:** Out-of-the-box installation must generate zero network traffic during code extraction and menu bar display.

---

## 3. Implementation Details

### 3.1 Preference Registration Change
In `Sources/CodeCatch/Model/Prefs.swift`, the default dictionary registration was updated:

```swift
static func register(in defaults: UserDefaults = .standard) {
    defaults.register(defaults: [
        receivedCodes: true, signInLinks: true, resetLinks: true, bitwarden: true,
        showBanner: true, autoCopy: true, autoType: false, clearClipboard: true, codeInMenuBar: true,
        sound: false, messages: true, appleMail: false, launchAtLogin: true, historyDays: 7, 
        serviceIcons: false, // Changed from true -> false in Phase 2B
        hideFromCapture: true, blurCodes: false, showPreviews: true, clearOnLock: false, hotkeys: true,
    ])
}
```

### 3.2 In-Flight Protection & Short-Circuit Evaluation
In `Sources/CodeCatch/Model/IconStore.swift`, when `load(domain)` is called:
```swift
guard defaults.bool(forKey: Prefs.serviceIcons) else { return }
```
Because this check occurs before:
- Disk cache directory lookup / creation
- In-flight task creation
- Network URLSession data task instantiation

Setting `serviceIcons` to `false` completely disables all file system touch operations and network calls.

---

## 4. Network Behavior Matrix

| Scenario | Service Icons Default (`false`) | Service Icons Opt-in (`true`) |
|---|---|---|
| **New Message Arrives** | 0 outbound network requests | 1 HTTPS request to Google/DuckDuckGo |
| **Local Cache Directory** | Never created or written to | Created at `~/Library/Caches/.../icons` |
| **Sender Domain Privacy** | 100% strictly local | Domain leaked to favicon proxy |
| **UI Presentation** | Local generic SF Symbol / App badge | Service brand logo (if fetched) |
| **Performance Overhead** | 0 ms (immediate local return) | ~150–500 ms async network fetch |

---

## 5. User Opt-In Flow & Settings Experience

For users who prefer visual brand icons:
1. The user navigates to **AETHER Settings → Appearance / Display**.
2. A toggle labeled *"Show service brand icons"* is presented, accompanied by a clear privacy disclosure:
   > *"When enabled, AETHER fetches public website icons using Google's favicon proxy. The sender's domain name is sent to retrieve the icon, but your emails, messages, and codes are never transmitted."*
3. When toggled on, `UserDefaults.standard.set(true, forKey: Prefs.serviceIcons)` is persisted, and subsequent domain lookups seamlessly fetch and cache brand icons.
4. When toggled off, all in-flight and future fetches are immediately suppressed.

---

## 6. Verification & Test Evidence

The hardened privacy behavior is verified in `Tests/CodeCatchTests/IconPrivacyTests.swift`:
1. `defaultRegistrationDisablesServiceIconsAndPreventsNetworkRequests`:
   - Verifies that `UserDefaults` default registration sets `serviceIcons == false`.
   - Verifies `store.load("example.com")` results in zero network requests (`requests.isEmpty`).
   - Verifies cache directory is not created on disk.
2. `explicitOptInLookupUsesOneGoogleProxyRequestAndCachesTheIcon`:
   - Verifies that when explicitly enabled (`defaults.set(true)`), icon fetching and caching operates reliably.
3. `iconURLsCannotEscapeTheAllowedProxyHostsAndPaths`:
   - Validates strict URL whitelist preventing SSRF or proxy bypass.
