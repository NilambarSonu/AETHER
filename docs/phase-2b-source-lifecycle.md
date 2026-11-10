# AETHER — Phase 2B Provider Lifecycle and Source Management Report

**Date:** November 10, 2026  
**Architect:** Principal macOS Engineer, Swift Concurrency Architect  
**Status:** Implementation Complete — 100% Tests Passing

---

## 1. Overview & Architecture

`AetherSourceCoordinator` introduces a centralized, actor-isolated lifecycle manager for modern `AetherMailSource` providers.

The coordinator eliminates main-thread blocking, isolates failures between providers, and provides sliding-window message deduplication before messages reach the OTP extraction pipeline.

```
                  ┌────────────────────────────────────────────────────────┐
                  │                AetherSourceCoordinator                 │
                  │  - actor-isolated                                      │
                  │  - registers/starts/stops any AetherMailSource         │
                  │  - tracks [String: SourceStatus]                       │
                  │  - deduplicates by message.dismissKey                  │
                  └───────┬────────────────────────┬───────────────────────┘
                          │                        │
               AsyncStream consumption  AsyncStream consumption
                          │                        │
                          ▼                        ▼
                 [AetherIMAPSource]       [FixtureMailSource]
                          │                        │
                          └───────────┬────────────┘
                                      │
                        onDeliver: (IncomingMessage)
                                      ▼
                      [OTP Ingestion Pipeline / AppModel]
```

---

## 2. Core Responsibilities & Concurrency Architecture

1. **Actor Isolation & Main-Thread Safety:**
   `AetherSourceCoordinator` is an `actor`. Consumer tasks (`Task { for await output in stream { ... } }`) execute independently on Swift's cooperative pool. Handing off received messages to the pipeline (`onDeliver(message)`) is non-blocking.
2. **Failure Isolation:**
   Each source is isolated. If one source fails (e.g. IMAP credentials expire or network drops), it reports its status via `.status(status)`. The coordinator updates `statuses[key] = status` and triggers `onStatusChange` without affecting other healthy sources.
3. **Sliding-Window Message Deduplication:**
   When reconnecting or recovering from sleep, email servers may re-transmit recent messages. The coordinator maintains a bounded set and FIFO eviction queue (`maxDeduplicationWindow = 500`) of `message.dismissKey`. Duplicate items within the window are discarded immediately with zero CPU or memory penalty in the regex extraction pipeline.
4. **Graceful Concurrent Shutdown:**
   `stopAll()` leverages Swift structured concurrency (`withTaskGroup`) to cancel consumer tasks and stop all registered sources concurrently:
   ```swift
   await withTaskGroup(of: Void.self) { group in
       for source in activeSources {
           group.addTask { await source.stop() }
       }
   }
   ```
5. **Idempotency:**
   Repeated invocations of `stop(key)`, `unregister(key)`, or `stopAll()` are completely safe and idempotent.

---

## 3. Test Verification Matrix

Automated unit tests in [`Tests/CodeCatchTests/AetherSourceCoordinatorTests.swift`](file:///Users/nilambarbehera/Documents/Projects/Aether/Tests/CodeCatchTests/AetherSourceCoordinatorTests.swift) verified the coordinator:

| Test Case | Scenario Evaluated | Verification Result |
| :--- | :--- | :--- |
| **1. Multiple Sources** | Registers 2 independent sources yielding messages concurrently; verifies both messages are delivered. | **VERIFIED** (`multipleSourcesDeliverConcurrently`) |
| **2. Failure Isolation** | Simulates failure in one source; verifies that healthy source continues delivering messages and remaining live. | **VERIFIED** (`failureInOneSourceLeavesOtherSourceLive`) |
| **3. Duplicate Suppression** | Submits identical message twice; verifies only 1 message is forwarded downstream. | **VERIFIED** (`duplicateMessagesAreSuppressed`) |
| **4. Unregistration** | Unregisters a source; verifies no further messages are delivered from it. | **VERIFIED** (`unregisterStopsConsumption`) |
| **5. Repeated StopAll** | Executes consecutive `stopAll()` calls; verifies clean, idempotent status transition to `.off`. | **VERIFIED** (`repeatedStopAllIsSafeAndIdempotent`) |
