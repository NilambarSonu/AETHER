# Competitive Engineering Audit: MessAuto vs 2fhey vs AETHER
**Document Version:** 1.0.0 (Production Architecture Review)  
**Date:** November 2026  
**Author:** Nilambar Behera (AETHER Lead Architect)  
**Classification:** Confidential Technical Review & Roadmap  

---

## 1. Executive Summary

AETHER was conceived to deliver the fastest, most secure, and most seamless two-factor authentication (2FA) and one-time passcode (OTP) experience on macOS. Rather than requiring users to run heavy standalone applications or browser extensions, AETHER operates as a native **Droplet** inside **Droppy** using Swift 6.2 and Apple's official DroppyKit SDK v1.23.0.

To maintain market leadership and architectural dominance, this audit provides a line-by-line engineering comparison of the two primary open-source native competitors:
1. **MessAuto** (`https://github.com/LeeeSe/MessAuto`): A cross-platform Rust utility (with egui / cocoa bindings) targeting macOS Messages.
2. **2fhey** (`https://github.com/SoFriendly/2fhey`): A macOS menu-bar utility written in Swift targeting iMessage and Android via a Google Messages bridge.

| Architectural Dimension | MessAuto (Rust) | 2fhey (Swift) | AETHER (.droplet) |
| :--- | :--- | :--- | :--- |
| **Runtime Environment** | Standalone process (~25–40 MB RAM) | Standalone menubar app (~30–50 MB RAM) | **Native DroppyKit bundle (~4 MB incremental)** |
| **Message Sources** | Messages (`chat.db`) | Messages (`chat.db`), Google Messages (WS) | **Messages, Apple Mail, IMAP, Gmail (OAuth), Outlook (OAuth), Bitwarden CLI** |
| **Parsing Engine** | Regex + 100-char proximity scoring | JSON keywords + NumberGuard filter | **3-Tier Token Stream + 704 Regression Fixtures** |
| **Database Synchronization** | Shell subprocess (`sqlite3`) polling | `DispatchSource` on `chat.db-wal` | **CoreServices `FSEventStream` + WAL pragmas** |
| **Security & Privacy** | Plaintext in memory; no hardware enclave | Plaintext in memory; no biometric gate | **Hardware Secure Enclave / Touch ID vault, transient clipboard** |
| **User Interface** | egui floating window / tray | AppKit / SwiftUI menubar popover | **Dynamic Notch HUD, Shelf Widget, Liquid Glass** |
| **Agent / Automation API** | None | None | **Model Context Protocol (MCP) Bridge** |

---

## 2. In-Depth Codebase Audits

### 2.1 MessAuto (`LeeeSe/MessAuto`)

#### Code Analysis & Architecture
- **Language & Runtime:** Rust (2021 edition), compiled with `egui`, `eframe`, and `enigo`.
- **Database Access:** In `src/monitor/message.rs`, MessAuto spawns a child process executing `/usr/bin/sqlite3` with `SELECT MAX(ROWID) FROM message;`.
  ```rust
  let output = std::process::Command::new("sqlite3")
      .arg(db_path.to_str().unwrap())
      .arg("SELECT MAX(ROWID) FROM message;")
      .output()?;
  ```
- **Parsing Mechanics (`src/parser.rs`):**
  1. Finds trigger keywords: "code", "verification", "验证码", "código", etc.
  2. Extracts candidate codes matching regex patterns (`verification_regex`).
  3. Computes byte/character distance between candidates and keyword boundaries (`find_closest_candidate`).
  4. Filters out candidates where `distance > 100` characters.
- **Auto-Paste (`src/clipboard.rs`):**
  - Pipes text to `/usr/bin/pbcopy` via standard input.
  - Synthesizes `Cmd + V` keystrokes via `enigo` crate (`CGEventPost`).

#### Strengths
- **Proximity Distance Scoring:** The 100-character proximity rule cleanly handles long marketing emails/SMS where extraneous numbers (dates, tracking IDs) appear far away from the word "code".
- **Multi-Language Regex Coverage:** Strong built-in coverage for CJK (Chinese, Japanese, Korean) verification formats.

#### Weaknesses & Vulnerabilities
- **Subprocess Spawning Overhead:** Calling `std::process::Command::new("sqlite3")` and `Command::new("pbcopy")` creates constant fork/exec overhead on macOS, causing battery drain and latency.
- **No Direct SQLite Binding:** Does not utilize SQLite C-APIs or WAL shared memory, missing transactional guarantees.
- **No Clipboard Cleansing:** Copies codes into the global macOS pasteboard without `org.nspasteboard.TransientType` or TTL expiration, leaking secrets to clipboard managers (Paste, Alfred, Raycast).
- **No Email Support:** Strictly limited to Messages (`chat.db`).

---

### 2.2 2fhey (`SoFriendly/2fhey`)

#### Code Analysis & Architecture
- **Language & Runtime:** Swift 5.7+ / AppKit menubar app with SwiftUI settings.
- **Database Access:** Uses `SQLite.swift` to read `~/Library/Messages/chat.db`.
- **WAL File Monitoring (`MessageManager.swift`):**
  - Opens `chat.db-wal` with `O_EVTONLY` and attaches a low-level Grand Central Dispatch source:
  ```swift
  let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .extend],
      queue: .global(qos: .background)
  )
  ```
  - Debounces triggers using a 300ms `DispatchWorkItem`.
- **Parsing Mechanics (`OTPParser.swift`):**
  - Distinguishes **whole-word keywords** (`auth`, `code`, `pin`) vs **substring keywords** (`verification`, `sicherheitscode`).
  - Implements **`NumberGuard`**: explicitly rejects timestamps (`10:45`), currencies (`$100`, `₹350`), dates (`2026-11-16`), and standard phone number formats.
  - Supports downloadable language dictionaries (`en.json`, `fr.json`, `de.json`, `zh.json`, `es.json`, `pt.json`, `he.json`).
- **Android Integration (`GoogleMessagesSetupService.swift`):**
  - Runs a local WebSocket server on port 2847 (`NotificationServer.swift`) communicating with an electron/pake wrapper around Google Messages web.

#### Strengths
- **WAL DispatchSource Monitoring:** Monitoring `chat.db-wal` via `DispatchSourceFileSystemObject` is exceptionally CPU-friendly and triggers instantaneously upon SQLite commit.
- **NumberGuard Rejector:** Explicitly blocking phone numbers, dates, and currency values eliminates the most common false-positive pitfalls in heuristic OTP extraction.
- **Clipboard Restoration:** Includes user toggle to restore previous clipboard contents after auto-copy.

#### Weaknesses & Vulnerabilities
- **Insecure Local WebSocket Server:** Opening a local TCP/WebSocket server on port 2847 exposes an attack surface where arbitrary local processes or malicious browser tabs can attempt localhost RPC injection.
- **Dependency on Remote JSON Patterns:** Relies on fetching dynamic JSON rules from GitHub at runtime; if offline or blocked, new pattern recognition degrades.
- **No Email or Passkey/TOTP Integration:** Lacks IMAP, OAuth, Apple Mail, and vault storage.

---

## 3. AETHER's Competitive Superiority & Edge

AETHER integrates the best engineering principles of both tools while completely eliminating their flaws:

```
                               ┌────────────────────────────────────────────────┐
                               │                 AETHER DROPLET                 │
                               │        (Embedded in Droppy Runtime)            │
                               └──────────────────────┬─────────────────────────┘
                                                      │
         ┌───────────────────────┬────────────────────┼───────────────────────┬──────────────────────┐
         ▼                       ▼                    ▼                       ▼                      ▼
 ┌───────────────┐       ┌───────────────┐    ┌───────────────┐       ┌───────────────┐      ┌───────────────┐
 │   Messages    │       │  Apple Mail   │    │  IMAP / OAuth │       │ Bitwarden CLI │      │   MCP Agent   │
 │   (chat.db)   │       │  (V10 / V11)  │    │(Gmail/Outlook)│       │  (Local TOTP) │      │  (Claude/AGY) │
 └───────┬───────┘       └───────┬───────┘    └───────┬───────┘       └───────┬───────┘      └───────┬───────┘
         │                       │                    │                       │                      │
         └───────────────────────┴────────────────────┼───────────────────────┴──────────────────────┘
                                                      │
                                                      ▼
                                       ┌─────────────────────────────┐
                                       │   3-Tier CodeCatchCore      │
                                       │    Token Stream Engine      │
                                       │  (704 Fixtures Verified)    │
                                       └──────────────┬──────────────┘
                                                      │
                                                      ▼
                                       ┌─────────────────────────────┐
                                       │   Biometric Hardware Vault  │
                                       │    (Touch ID / SEP Key)     │
                                       └──────────────┬──────────────┘
                                                      │
                                                      ▼
                                       ┌─────────────────────────────┐
                                       │      Dynamic Notch HUD      │
                                       │   Brand Icons & Glass UI    │
                                       └─────────────────────────────┘
```

1. **Zero-Daemon, Zero-Process Footprint:**
   - AETHER is compiled as an official macOS dynamic library bundle (`AETHER.droplet`).
   - Runs embedded inside Droppy's process with shared memory and zero IPC overhead.
2. **Deep Multi-Source Ingestion:**
   - While competitors only monitor SMS, AETHER seamlessly monitors Messages, Apple Mail, IMAP inboxes, Google Workspace OAuth, Microsoft Outlook OAuth, and Bitwarden CLI vaults.
3. **Hardware Biometric Security Enclave (Touch ID):**
   - Codes can be encrypted at rest in Keychain with biometric access control. Unauthorized processes or physical shoulder-surfers cannot access live tokens.
4. **Transient Clipboard & Privacy Shield:**
   - Codes copied to the pasteboard include `org.nspasteboard.TransientType` and `org.nspasteboard.AutoGeneratedType`, preventing third-party clipboard apps from permanently archiving them. Auto-clears after configurable TTL (default 90s).
5. **Brand Icon Discovery & Visual Monograms:**
   - Resolves authentic brand icons via multi-proxy failover, direct HTTPS `/favicon.ico` probes, and rich local vector catalogs (supporting Indian government portals, global fintech, and developer platforms).

---

## 4. Key Takeaways & Adopted Optimizations

Based on this audit, AETHER incorporates the following optimizations:
- **Proximity Scoring (from MessAuto):** Refined candidate scoring based on character distance to intent keywords.
- **NumberGuard Rejectors (from 2fhey):** Robust exclusion of phone numbers, timestamps, currencies, and ISO dates.
- **Single-Line Subtitle Heuristics:** Streamlined Notch HUD subtitles that discard technical sender metadata and display clean user intent (e.g., "Password reset request", "Refund of ₹348.10").
- **Double Notification Elimination:** Mutually exclusive HUD vs. Banner routing ensuring exactly one notification per incoming OTP.
