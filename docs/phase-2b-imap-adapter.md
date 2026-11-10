# AETHER — Phase 2B AetherIMAPSource Implementation Report

**Date:** November 10, 2026  
**Architect:** Principal macOS Engineer, Swift Concurrency Architect  
**Status:** Implementation Complete — 100% Tests Passing

---

## 1. Overview & Architecture

`AetherIMAPSource` provides a modernized, Swift Concurrency-native adapter conforming to the `AetherMailSource` protocol.

Rather than destructively rewriting working, battle-tested IMAP networking code, `AetherIMAPSource` cleanly wraps and coordinates `MailWatcher` and `IMAPConnection`, translating raw connection events, status updates, health checks, and incoming messages into a structured asynchronous stream (`AsyncStream<AetherSourceOutput>`).

```
┌────────────────────────────────────────────────────────┐
│                   AetherIMAPSource                     │
│  - Conforms to AetherMailSource: Sendable              │
│  - Exposes messages() -> AsyncStream<AetherSourceOutput>│
│  - Exposes stop() async                                │
└───────────────────────────┬────────────────────────────┘
                            │
               Task { MailWatcher.watch(...) }
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
   [IMAPConnection (TLS)]          [Health & Cursors]
   - RFC 2177 IDLE push            - UID / UIDVALIDITY
   - 9-minute watchdog renewal     - Backfill 60 newest
   - Exponential retry backoff     - Reconnect after sleep
```

---

## 2. Swift Concurrency & Thread Safety Guarantees

1. **Sendable Conformance:**
   `AetherIMAPSource` conforms to `AetherMailSource: Sendable`. Internal mutable state (`activeTask`, `streamContinuation`, `isStopped`) is isolated behind a private `NSLock`.
2. **Deadlock Elimination:**
   In Swift `AsyncStream`, invoking `continuation.finish()` or `continuation.yield()` synchronously triggers `continuation.onTermination`. If the lock is held across the `finish()` call, any recursive attempt by `onTermination` to acquire the lock causes a thread deadlock. `AetherIMAPSource` extracts the continuation inside the critical section and executes `finish()` and `yield()` strictly outside the lock.
3. **Idempotent Termination:**
   `stop()` is fully idempotent. The first call flips `isStopped = true`, cancels the running background task, yields `.status(.off)`, and finishes the stream. Subsequent invocations detect `isStopped == true` and return immediately without side effects.
4. **Cooperative Cancellation:**
   If the consumer task terminates or cancels iteration, `AsyncStream.Continuation.onTermination` cancels the underlying watcher task and frees resource handles immediately.
5. **Zero Leaked Continuations:**
   When the stream finishes or is stopped, references to the continuation and task are set to `nil`, preventing memory leaks or retain cycles.

---

## 3. Preservation of Existing Network Infrastructure

- [`Sources/CodeCatch/Mail/IMAPConnection.swift`](file:///Users/nilambarbehera/Documents/Projects/Aether/Sources/CodeCatch/Mail/IMAPConnection.swift) was completely preserved.
- TLS enforcement via `NWConnection(using: .tls)` remains intact.
- IMAP `IDLE` protocol state handling, untagged `* n EXISTS` processing, and 540-second watchdog timers remain untouched.
- Authentication error backoff (300 seconds) and connection loss exponential backoff (5s–120s) remain intact.
- Existing `MailAccount` model, password retrieval, and Keychain access are preserved.

---

## 4. Test Verification Matrix

Automated unit tests in [`Tests/CodeCatchTests/AetherIMAPSourceTests.swift`](file:///Users/nilambarbehera/Documents/Projects/Aether/Tests/CodeCatchTests/AetherIMAPSourceTests.swift) verified the adapter's behavior:

| Test Case | Scenario Evaluated | Verification Result |
| :--- | :--- | :--- |
| **1. Connection & Delivery** | Streams status `.connecting` -> `.live` -> `.off` and delivers parsed message. | **VERIFIED** (`successfulConnectionStreamsMessage`) |
| **2. Auth Failure Propagation** | Simulates `IMAPError.noPassword` and verifies `.needsSignIn` status is yielded. | **VERIFIED** (`authenticationFailureReportsStatus`) |
| **3. Reconnection on Drop** | Simulates connection loss on initial fetch; verifies automatic reconnection and recovery to `.live`. | **VERIFIED** (`connectionLossTriggersReconnect`) |
| **4. Explicit Stop** | Verifies `stop()` terminates the stream, closes sockets, and yields `.off`. | **VERIFIED** (`explicitStopIsIdempotent`) |
| **5. Repeated Stop** | Verifies multiple consecutive `stop()` calls execute without errors or deadlocks. | **VERIFIED** (`explicitStopIsIdempotent`) |
| **6. Consumer Cancellation** | Verifies cancelling the consumer Task cleanly cancels the stream and stops the task. | **VERIFIED** (`consumerCancellationTerminatesGracefully`) |
| **7. No Event Duplication** | Message delivery strictly checks UID boundaries; duplicate backfill messages suppressed. | **VERIFIED** |
| **8. No Leaked Tasks** | `stop()` awaits completion of the underlying task before returning. | **VERIFIED** |
