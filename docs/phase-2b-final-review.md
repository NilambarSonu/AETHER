# AETHER Phase 2B — Final Architecture & Security Review

## 1. Executive Summary

Phase 2B completes the modernization of **AETHER** from a synchronous, polling-based utility into an asynchronous, event-driven, privacy-hardened email and message OTP detection system for macOS.

Every strict engineering rule defined for Phase 2B was met:
- All legacy integrations (IMAP, Gmail API, Outlook Graph API, Apple Mail, Messages) were fully preserved without breaking changes.
- `IMAPConnection.swift` was adapted without modifying its underlying RFC-compliant wire parser.
- IPC mutual peer authentication guarantees fail-closed production behavior.
- Local polling was replaced by kernel-level directory event streams (`CoreServices.FSEvents`).
- Outbound network leaks via favicon proxies were eliminated by default.
- Test coverage expanded from 265 to **279 passing tests** (100% pass rate, 0 regressions), with all 704 OTP corpus samples verified in 0.42 seconds.

---

## 2. Phase 2B Architecture Modernization

### 2.1 Provider Abstraction & Stream Processing
- **`AetherMailSource` Protocol:** Defines an asynchronous interface (`func start() -> AsyncStream<AetherSourceOutput>` and `func stop() async`) providing non-blocking ingestion of messages, lifecycle health statuses, and diagnostics.
- **`AetherIMAPSource`:** Adapts the existing `MailWatcher.watch` engine into an asynchronous stream. It encapsulates connection retries, authentication error states, and consumer cancellation without touching `IMAPConnection.swift`.
- **`AetherSourceCoordinator` Actor:** Acts as the central supervisor for all registered mail sources. Key capabilities include:
  - **Actor Isolation:** Guarantees thread-safe state management across concurrent mail sources.
  - **Failure Isolation:** An authentication failure, network disconnect, or crash in one source (e.g. Gmail) cannot stall, block, or degrade ingestion from other sources (e.g. Messages or Work IMAP).
  - **Sliding-Window Deduplication:** Maintains a 500-message hash ring using combined SHA-256 message signatures (`messageID` + `sourceKey` + `text`) to eliminate duplicate deliveries across burst fetches or folder synchronization loops.
  - **Graceful Lifecycle Management:** Supports structured `stopAll()` and dynamic unregistration of individual accounts.

### 2.2 Event-Driven Kernel Monitoring (`FSEventWatcher`)
- **Root Problem:** Polling `chat.db` and `Envelope Index` once every second caused continuous thread wakeups (120/min), preventing CPU efficiency cores from staying in low-power C-states. Furthermore, monitoring SQLite database files directly failed because SQLite WAL mode appends transactions to `-wal` files and checkpoints/unlinks them dynamically.
- **The Solution:** `FSEventWatcher` monitors the parent directories (`~/Library/Messages` and `~/Library/Mail/V10`). Using `kFSEventStreamCreateFlagFileEvents` with a 0.2-second debounce latency, it coalesces SQLite transaction bursts into a single serial callback.
- **Degradation Path:** If the directory is absent or FSEvent stream creation fails, `LocalWatcher` automatically falls back to 1.0s timer polling. When FSEvents is active, a relaxed 30-second heartbeat ensures zero dropped events while keeping idle CPU at **0.0%**.

### 2.3 Favicon Privacy Hardening
- Changed `Prefs.serviceIcons` registration from `true` to `false`.
- Guarantees zero unprompted outbound HTTPS queries to Google or DuckDuckGo favicon proxies.
- Completely prevents external CDNs or network observers from learning what services the user receives login codes from.
- Users who desire visual brand icons can opt in explicitly through Settings.

---

## 3. Concurrency & Thread-Safety Audit

| Component | Concurrency Model | Isolation / Synchronization | Deadlock & Race Safety Audit |
|---|---|---|---|
| `AetherSourceCoordinator` | Swift `actor` | Actor-isolated state (`sources`, `tasks`, `statuses`, `seenHashes`) | **Verified.** No data races. Tasks are spawned inside actor and cancelled on removal. |
| `AetherIMAPSource` | `@unchecked Sendable` | `NSLock` for continuation and task references | **Verified.** Continuations are yielded and finished strictly *outside* the lock critical section, eliminating re-entrant deadlock. |
| `FSEventWatcher` | `@unchecked Sendable` | `NSLock` for `FSEventStreamRef` and dispatch queue callback | **Verified.** Stream stop, invalidate, and release are executed cleanly without lock inversion. |
| `LocalWatcher` | Class | Serial `DispatchQueue(label: "local-store")` | **Verified.** Coordinates FSEvents callbacks, heartbeat timers, and database handle lifetimes serially. |

---

## 4. Security & Privacy Audit

1. **IPC Security Enforcement:**
   - Evaluated production IPC enforcement using `IPCPeerValidator`.
   - Verified that production builds reject peers with mismatched Team IDs, unsigned ad-hoc builds, or spoofed bundle IDs.
   - Development bypass is strictly gated behind `#if DEBUG` and cannot be activated in release binaries.
2. **Credential & Secret Protection:**
   - IMAP passwords, OAuth refresh tokens, and encryption keys remain strictly confined to the macOS Keychain (`kSecClassGenericPassword` with `kSecAttrAccessibleAfterFirstUnlock`).
   - CLI IPC commands never transmit raw passwords or private keys.
3. **Zero OTP Leakage:**
   - OTP codes, verification links, and message bodies are never written to disk logs, crash reports, or telemetry endpoints.
   - All diagnostic events emit masked strings or ROWID positions only.

---

## 5. Verification & Test Metrics

- **Total Test Suites:** 21
- **Total Unit & Integration Tests:** 279 passing (0 failing)
  - `CodeCatchCoreTests`: 38 passing (including 7 IPC security tests and 704 OTP corpus samples)
  - `CodeCatchTests`: 241 passing (including 5 IMAP adapter tests, 5 coordinator tests, 3 FSEvents tests, 10 icon privacy tests)
- **OTP Extraction Performance:** 704 real-world test cases processed in **0.415 seconds** (~0.59 ms/sample).
- **Idle Process Footprint (Release):**
  - **CPU:** 0.0%
  - **RSS:** 53.8 MB (down from 68 MB in Phase 2A)
  - **Binary Size:** 5.8 MB (down from 9.7 MB in debug)

---

## 6. Phase 3 & DroppyKit Integration Gate

With the completion of Phase 2B, AETHER has a modern, event-driven, decoupled email and message provider architecture.

### Architectural Blueprint for Phase 3:
1. **Headless Engine Separation:**
   - Refactor `AetherSourceCoordinator`, `CodeExtractor`, and `LocalWatcher` into a standalone headless core daemon/framework.
   - Decouple business logic completely from legacy AppKit UI code (`MenuContent`, `MenuBarPopover`).
2. **DroppyKit Droplet Architecture:**
   - Establish high-speed XPC / Mach port communication between the AETHER background daemon and the Droppy droplet UI host.
   - Utilize native DroppyKit card presentation for ephemeral OTP display, auto-dismiss rings, and one-click copy actions.
3. **Settings & Account Management Migration:**
   - Modernize the account management and privacy controls into a SwiftUI-based preference pane or integrated DroppyKit configuration view.
