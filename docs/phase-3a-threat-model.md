# AETHER Phase 3A — Comprehensive Security Threat Model

## 1. Executive Summary

This document presents a comprehensive threat model for the AETHER headless engine and its integration with DroppyKit, evaluated across 12 specific threat vectors.

Because AETHER processes sensitive authentication factors (email and SMS OTPs) and operates with macOS Full Disk Access, the security architecture strictly separates the **Trusted Core** (AETHER Host) from the **Presentation Layer** (DroppyKit Droplet).

---

## 2. Threat Analysis Matrix

| # | Threat Vector | Attack Scenario | Existing Protection | Required Mitigation | Residual Risk | Verification Method |
|---|---|---|---|---|---|---|
| **1** | **Malicious Local Process** | Local process running under same or different user attempts to connect to `droplet.sock` to snoop OTPs. | File permissions `0600` block other users. | Retrieve kernel `LOCAL_PEERTOKEN`; verify UID and client bundle identity. | Negligible (root attacker can bypass permissions). | Automated test attempting connection from unauthenticated process. |
| **2** | **Foreign Signing Team ID** | Attacker signs a rogue droplet with an unauthorized Apple Developer certificate. | `IPCPeerValidator` checks code signature. | Enforce exact Team ID policy (`certificate leaf[subject.OU] == ...`). | None. Cryptographically backed by Apple CA. | Unit test verifying rejection of mismatched Team ID. |
| **3** | **Unsigned / Ad-hoc Binary** | Attacker builds unsigned binary attempting to establish IPC connection. | `IPCPeerValidator` fails closed on missing signatures. | Missing or invalid signing identity fails closed; debug bypass gated strictly behind `#if DEBUG`. | None in production release. | Test in `IPCSecurityTests.swift`. |
| **4** | **IPC Endpoint Spoofing** | Attacker pre-creates `droplet.sock` before AETHER launches to act as a man-in-the-middle. | Standard `bind()` fails with `EADDRINUSE`. | Check `lstat`; verify socket ownership (`st_uid == getuid()`) and file mode (`0600`). Recreate cleanly. | None. | Unit test simulating pre-existing rogue socket file. |
| **5** | **Replay of Old OTP Event** | Attacker captures previously transmitted IPC frame and replays it over socket. | Codes expire quickly in real services. | Enforce `Date() <= expiresAt`; track sliding window of last 50 seen `deduplicationHash` values. | None. | Unit test passing expired timestamp and duplicate payload. |
| **6** | **Malformed / Oversized Payload** | Attacker floods socket with gigabytes of garbage or deeply nested JSON. | Swift memory safety prevents C buffer overruns. | Enforce strict 4 KB maximum frame limit before parsing; discard oversized frames immediately. | None. | Fuzz test transmitting 50 KB payloads and corrupt byte streams. |
| **7** | **Unauthorized Clipboard Access** | Rogue application on Mac reads clipboard after OTP is copied. | `Prefs.clearClipboard` clears clipboard after 60s. | Default to manual "Copy Code" button in Notch card; auto-clear pasteboard after expiration timeout. | Low (any unsandboxed process can read pasteboard while active). | Test clipboard timeout and preference switches. |
| **8** | **OTP Exposure in Logs** | Diagnostic logger writes plaintext verification codes to system log streams. | Phase 2B verified 0 OTP codes in logs. | Enforce string masking: `[REDACTED OTP (%ld chars)]`; audit all `os_log` statements. | Zero. | Automated regex scanner across all test and runtime logs. |
| **9** | **Crash Dumps & Memory Lifetime** | Application crashes and writes unencrypted heap to diagnostic crash log. | Heap allocations are ephemeral. | Deallocate payload immediately upon card dismissal or timeout; avoid persistent String caching. | Low (system crash logs protected by user permissions). | Memory lifecycle audit. |
| **10** | **Stale IPC Endpoints** | Socket file persists after sudden crash or power outage, blocking next launch. | POSIX socket cleanup. | Safely probe socket with connect test; call `unlink(path)` if stale, then re-bind. | None. | Crash-recovery socket restart test. |
| **11** | **Concurrent Receivers** | Multiple rogue clients connect simultaneously to race for OTP events. | Host socket manages connection list. | Restrict active subscriber to 1 primary verified peer; reject or disconnect auxiliary peers. | None. | Test verifying rejection of second concurrent connection. |
| **12** | **Compromised Presentation Layer** | `Droppy.app` is compromised by a malicious community droplet. | AETHER Host holds Full Disk Access and Keychain credentials; Droppy has zero access. | Transmit ONLY extracted OTP and sender label; never send email credentials, tokens, or body. | Low (attacker sees only the single current ephemeral OTP). | Architectural boundary verification. |

---

## 3. Defense-in-Depth Summary

1. **Compartmentalization:** If `Droppy.app` or any droplet inside it is compromised, the attacker gains **zero access** to the user's email accounts, IMAP passwords, OAuth refresh tokens, or historical message database.
2. **Minimal Data Principle:** The IPC contract transmits only the bare minimum required to show the Notch card: the 4–8 character code and the service name (e.g., "GitHub").
3. **No Darwin Notifications for Sensitive Data:** Darwin notifications (`notify_post`) are public to all processes on the Mac. AETHER completely avoids Darwin notifications for OTP data, using private Unix Domain Sockets with audit tokens.
