# AETHER Phase 3A — Lifecycle Ownership & Implementation Roadmap

## 1. Executive Summary

This document establishes the lifecycle ownership matrix and a concrete, milestone-gated implementation roadmap for transitioning AETHER into a modular, headless engine (`AetherCore`) integrated with DroppyKit (`AetherDroplet`).

---

## 2. Lifecycle & Responsibility Matrix

| Responsibility | `AetherCore` (Engine) | `AetherHost` (App) | `AetherDroplet` (Droppy) | Technical Rationale |
|---|---|---|---|---|
| **Provider Execution** | Primary | Orchestrator | None | Core executes IMAP, Apple Mail, and Messages ingestion loops. |
| **Full Disk Access (FDA)**| None | **Exclusive Holder**| None | TCC grant is tied directly to the main `.app` bundle. |
| **Keychain Access** | Helper | **Exclusive Holder**| None | Secrets (IMAP passwords, OAuth tokens) remain in host's Keychain. |
| **OTP Extraction** | **Exclusive Engine**| None | None | Normalizes Unicode, removes zero-width characters, runs regex. |
| **Deduplication** | **Exclusive Engine**| None | Secondary (HUD ring)| 500-item sliding window prevents duplicate emissions at source. |
| **Event Delivery** | Protocol Contract | Server Host | Client Subscriber | Host serves UDS socket; Droplet connects and listens. |
| **Card Presentation** | None | Fallback | **Primary UI** | Droplet renders native Notch HUD card via `DroppyKit.DropletHUDService`. |
| **Clipboard Action** | None | Fallback | **Primary UI** | Droplet writes to `NSPasteboard` upon user button click. |
| **Auto-Dismiss** | None | None | **Primary UI** | Droplet schedules HUD timeout (30s) through DroppyKit scheduler. |
| **User Preferences** | Model | Storage | Optional Settings | Host stores preferences in UserDefaults; Droplet reads presentation opts. |
| **Shutdown & Recovery**| State Cleanup | Listener Cleanup| Client Teardown | Structured, cooperative cancellation across all components. |

### Operational Lifecycle Matrix

| Operational Event | System Reaction & Recovery Policy |
|---|---|
| **Application Startup** | `AetherHost` launches, binds `droplet.sock`, verifies FDA, and starts `AetherSourceCoordinator`. |
| **Login at Boot** | `AetherHost` launches via `SMAppService` or LoginItem; awaits Droppy connection passively. |
| **DroppyKit Unavailable** | If `droplet.sock` has no connected client, `AetherHost` falls back automatically to its native Menu Bar / HUD. Zero codes are lost. |
| **AETHER Host Unavailable** | `AetherDroplet` displays inactive state in its Settings pane and retries socket connection every 3 seconds with exponential backoff. |
| **Provider Failure** | `AetherSourceCoordinator` isolates the failing provider; healthy sources remain live. Emits diagnostic event. |
| **IPC Disconnect** | `AetherHost` cleans up the dead client file descriptor; `AetherDroplet` re-arms its connection listener. |
| **Mac Sleep & Wake** | `LocalWatcher` heartbeat resumes; FSEvent streams flush kernel buffers; IMAP connections perform TLS ping/reconnect. |
| **User Logout** | Both processes receive `applicationWillTerminate`; close sockets; flush zero-written memory. |
| **App Upgrade** | Sparkle replaces `.app`. On relaunch, new binary re-binds `droplet.sock`; droplet reconnects seamlessly. |
| **Uninstallation** | Deleting `AETHER.app` leaves zero background LaunchAgents. Droplet uninstalls cleanly from Droppy store. |

---

## 3. Implementation Roadmap: Phases 3B through 3G

```
+-------------------------------------------------------------------------------+
| PHASE 3B: Headless AetherCore Module Extraction (Pure Refactoring)            |
| Scope: Package.swift target restructuring; zero runtime or test behavioral delta|
+-------------------------------------------------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 3C: IPC Contract & Serialization (AetherOTPPayload)                     |
| Scope: 4 KB length-prefixed frame codec, Codable models, replay/expiration tests|
+-------------------------------------------------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 3D: Authenticated Droplet IPC Bridge (Server & Client)                  |
| Scope: UDS listener in Host, client in Droplet, audit token peer authentication|
+-------------------------------------------------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 3E: DroppyKit Droplet Package & Notch HUD Presentation                  |
| Scope: Aether.droplet bundle, droplet.json manifest, DropletHUDCard rendering  |
+-------------------------------------------------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 3F: Ephemeral Clipboard Actions & Auto-Dismiss Tuning                   |
| Scope: One-click "Copy Code" action, 30s auto-dismiss, pasteboard clear timer |
+-------------------------------------------------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 3G: End-to-End Hardening, Sleep/Wake Resilience & Release Validation    |
| Scope: Stress testing, zero-allocation idle verification, documentation signoff|
+-------------------------------------------------------------------------------+
```

---

### Milestone Details

#### Milestone 3B: Headless `AetherCore` Module Extraction
- **Scope:** Extract engine components (`AetherSourceCoordinator`, `AetherMailSource`, `AetherIMAPSource`, `LocalWatcher`, `FSEventWatcher`, `CodeExtractor`, `IPCPeerValidator`) into an independent target `AetherCore` in `Package.swift`.
- **Files Affected:** `Package.swift`, `Sources/AetherCore/*`.
- **Acceptance Criteria:** 279/279 tests passing. Zero functional regressions.
- **Rollback Strategy:** Revert target separation in `Package.swift`.

#### Milestone 3C: IPC Contract & Length-Prefixed Framing
- **Scope:** Implement `AetherOTPPayload`, `AetherOTPAcknowledgment`, and `AetherFrameCodec`.
- **Security Limits:** Max frame size 4,096 bytes. Strict JSON decode validation.
- **Tests:** Serialization round-trip, corrupted frame rejection, 4 KB overflow rejection, expired payload rejection.

#### Milestone 3D: Authenticated Droplet IPC Bridge
- **Scope:** Implement `DropletIPCServer` in `AetherHost` and `DropletIPCClient` in `AetherDroplet`.
- **Security:** Darwin kernel `LOCAL_PEERTOKEN` mutual peer verification.
- **Tests:** Peer authorization tests, unauthorized client rejection, connection drop & reconnect tests.

#### Milestone 3E: DroppyKit Droplet Package (`AetherDroplet`)
- **Scope:** Build `Aether.droplet` conforming to `DroppyKit.Droplet` and `HUDPresenting`. Create `droplet.json`.
- **Presentation:** Display `DropletHUDCard` in Notch on message arrival.
- **Tests:** Droplet initialization test, HUD request formatting test.

#### Milestone 3F: Ephemeral Clipboard Interaction & Auto-Dismiss
- **Scope:** Implement `DropletHUDAction` for "Copy Code" and duration-based auto-dismiss (30s).
- **Security:** Immediate in-memory deallocation on dismiss; zero disk caching.
- **Tests:** Clipboard copy verification, dismiss notification test.

#### Milestone 3G: Lifecycle Resilience & Performance Sign-off
- **Scope:** Profile combined system during 24-hour idle simulation, sleep/wake cycles, and burst mail ingestion.
- **Performance Limits:** Idle RSS <= 55 MB, Idle CPU = 0.0%, Detection latency <= 250ms.
- **Approval Gate:** Final architecture and security verification report.
