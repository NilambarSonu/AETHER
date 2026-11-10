# AETHER Phase 3D: Phased Implementation Plan & Verification Strategy

**Architecture:** Option A — In-Process AetherCore Engine + Separate Droppy UI Client  
**Target Module:** `AetherCore` (Host Transport) & `AetherDroplet` (Client Bundle)  
**Parent Architecture Gate:** [docs/phase-3d-ipc-transport-architecture.md](file:///Users/nilambarbehera/Documents/Projects/Aether/docs/phase-3d-ipc-transport-architecture.md)  
**Implementation Date:** November 2026  
**Status:** IMPLEMENTATION ROADMAP (AWAITING PHASE 3E AUTHORIZATION)

---

## 1. Executive Implementation Strategy

The implementation of the AETHER-to-Droppy IPC transport is partitioned into small, independently testable, reversible milestones. Each milestone has strictly defined scope boundaries, explicit acceptance criteria, automated tests, and individual rollback instructions.

### Golden Rules for Implementation:
1. **Host-First Principle:** Implement and verify the host transport server inside `AetherCore` using headless test clients before authoring any Droppy droplet code.
2. **Zero Regressions:** Every milestone must maintain 100% pass rate across the existing 310 tests and 704 OTP email fixtures.
3. **No Network / Cloud Relay:** Strictly local POSIX domain sockets (`AF_UNIX`).
4. **No Plaintext Secrets in Logs:** Zero OTP exposure in logs, debug descriptions, or error messages.
5. **No Production Source File Breakage:** Existing menu bar UI, CLI server, and providers must remain completely functional even if the Droppy socket transport is offline.

---

## 2. Phased Implementation Milestones

```
+-----------------------------------------------------------------------------------+
| Milestone 1: Filesystem & Safe Endpoint Creation (AetherSocketEndpoint)           |
| - Directory creation (0700), lstat symlink check, umask (0177), flock (.lock)     |
+-----------------------------------------+-----------------------------------------+
                                          |
+-----------------------------------------v-----------------------------------------+
| Milestone 2: Kernel Peer Validator Adapter (AetherPeerValidator)                  |
| - LOCAL_PEERTOKEN extraction, SecCodeCopyGuestWithAttributes, Droppy Team ID check|
+-----------------------------------------+-----------------------------------------+
                                          |
+-----------------------------------------v-----------------------------------------+
| Milestone 3: Server Actor & Reconnection Lifecycle (AetherIPCTransportServer)     |
| - Swift Actor isolation, single-client exclusive policy, non-blocking accept loop |
+-----------------------------------------+-----------------------------------------+
                                          |
+-----------------------------------------v-----------------------------------------+
| Milestone 4: Ephemeral Handshake Token & Replay Cache (AetherReplayCache)         |
| - 256-bit session.token file barrier, 2.0s handshake timeout, bounded replay ring |
+-----------------------------------------+-----------------------------------------+
                                          |
+-----------------------------------------v-----------------------------------------+
| Milestone 5: Droplet Client Transport Adapter (AetherIPCClient)                   |
| - Lightweight client actor, exponential backoff reconnect, handshake submission   |
+-----------------------------------------+-----------------------------------------+
                                          |
+-----------------------------------------v-----------------------------------------+
| Milestone 6: Droplet Bundle Packaging & Manifest (Aether.droplet)                 |
| - DroppyKit ABI 1, droplet.json manifest, resources, Mach-O dylib build script    |
+-----------------------------------------+-----------------------------------------+
                                          |
+-----------------------------------------v-----------------------------------------+
| Milestone 7: End-to-End Presentation & User Clipboard Bridge                      |
| - DropletHUDCard presentation in Notch, interactive "Copy" action, auto-dismiss   |
+-----------------------------------------------------------------------------------+
```

---

## 3. Milestone Detailed Specifications

### Milestone 1: Filesystem & Safe Endpoint Creation
- **Scope:** Implement `AetherSocketEndpoint` in `AetherCore/Transport/`.
- **Responsibilities:**
  - Resolve canonical path: `~/Library/Application Support/Aether/droplet.sock`.
  - Path length check: verify path length `< 104` bytes (`sizeof(sockaddr_un.sun_path)`).
  - Parent directory creation: `FileManager` POSIX permissions `0o700`.
  - Directory verification: `lstat` guarantees parent is a real directory (`S_IFDIR`) and NOT a symlink (`S_ISLNK`).
  - Safe lock acquisition: `open(path + ".lock", O_RDWR | O_CREAT | O_CLOEXEC, 0600)` with `flock(LOCK_EX | LOCK_NB)`.
  - Atomic socket permissions: `umask(0o177)` around `bind()` to ensure socket file is created `0o600`.
  - Safe cleanup: `unlink(path)` executed only after holding exclusive `flock`.
- **Unit Tests:**
  - `testParentDirectoryPermissionsEnforced`: Verifies `0o700`.
  - `testSymlinkParentDirectoryRejected`: Verifies failure on symlink.
  - `testExclusiveLockPreventsDuplicateListeners`: Verifies second bind fails gracefully.
  - `testStaleSocketUnlinkedOnlyWithLock`: Verifies dead socket cleanup.
- **Rollback:** Delete `Sources/AetherCore/Transport/AetherSocketEndpoint.swift`.

---

### Milestone 2: Kernel Peer Validator Adapter
- **Scope:** Implement `AetherPeerValidator` in `AetherCore/Transport/`.
- **Responsibilities:**
  - Extract Darwin `audit_token_t` from socket file descriptor via `getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len)`.
  - Convert `audit_token_t` to `SecCode` via `SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: ...], [], &secCode)`.
  - Compile requirement: `"identifier \"iordv.Droppy\" and anchor apple generic and certificate leaf[subject.OU] = \"NARHG44L48\""`.
  - Validate peer using `SecCodeCheckValidity()`.
  - Strict fail-closed policy in production (release builds).
  - `#if DEBUG` explicit bypass parameter `developmentAllowUnsigned` for test runners.
- **Unit Tests:**
  - `testSelfPeerValidationSucceeds`: Validates current process identity.
  - `testAuditTokenExtractionFromConnectedSocket`: Verifies 32-byte token populated.
  - `testMismatchedTeamIDRejected`: Validates rejection of dummy Team ID.
  - `testUnsignedPeerFailsClosedInReleaseMode`: Verifies release security.
- **Rollback:** Delete `Sources/AetherCore/Transport/AetherPeerValidator.swift`.

---

### Milestone 3: Server Actor & Reconnection Lifecycle
- **Scope:** Implement `AetherIPCTransportServer` and `AetherIPCClientSession` actors in `AetherCore/Transport/`.
- **Responsibilities:**
  - `AetherIPCTransportServer` actor owns listening socket FD and accept loop task.
  - Non-blocking accept loop via `Task` and `Darwin.accept()`.
  - Single active client invariant: at most 1 connected Droppy client session.
  - Reconnection policy: if a valid new Droppy connection arrives, terminate stale session cleanly and adopt new connection.
  - Serialized write pipeline: `broadcast(payload: AetherOTPPayload) async throws`.
  - Disconnect detection: `read == 0` (EOF) or error tears down session actor cleanly.
- **Unit Tests:**
  - `testServerAcceptsSingleValidClient`: Verifies connection setup.
  - `testSecondConnectionReplacesDeadClient`: Verifies reconnection.
  - `testClientDisconnectTriggersCleanServerState`: Verifies EOF handling.
  - `testConcurrentConnectionAttemptsSerialized`: Verifies no race in accept loop.
- **Rollback:** Delete `Sources/AetherCore/Transport/AetherIPCTransportServer.swift`.

---

### Milestone 4: Ephemeral Handshake Token & Replay Cache
- **Scope:** Implement `AetherHandshakeFrame` and `AetherReplayCache` in `AetherCore/Transport/`.
- **Responsibilities:**
  - Host generates 32 cryptographically secure random bytes (`SecRandomCopyBytes`).
  - Writes token to `~/Library/Application Support/Aether/session.token` (mode `0o600`).
  - Client must transmit matching `AetherHandshakeFrame` within 2.0 seconds of connect.
  - In-memory `AetherReplayCache`:
    - Ring buffer + Dictionary capped at 256 entries.
    - Tracks `[UUID: Date]`.
    - Auto-purges expired entries (`expiresAt <= Date()`).
    - Duplicate `eventID` rejected with `.rejected` acknowledgment.
- **Unit Tests:**
  - `testValidHandshakeTokenAccepted`: Verifies handshake success.
  - `testInvalidHandshakeTokenDisconnects`: Verifies immediate drop.
  - `testHandshakeTimeoutDropsConnection`: Verifies 2.0s deadline.
  - `testReplayCacheSuppressesDuplicateEventID`: Verifies duplicate rejection.
  - `testReplayCachePurgesExpiredEntries`: Verifies memory reclamation.
- **Rollback:** Delete `Sources/AetherCore/Transport/AetherHandshake.swift` and `AetherReplayCache.swift`.

---

### Milestone 5: Droplet Client Transport Adapter
- **Scope:** Implement `AetherIPCClient` in `AetherCore/Transport/` (or dedicated client module).
- **Responsibilities:**
  - Asynchronous client actor: connects to `~/Library/Application Support/Aether/droplet.sock`.
  - Reads `session.token` from disk and submits initial `AetherHandshakeFrame`.
  - Exponential backoff reconnection: retries on disconnect (1.0s, 2.0s, 4.0s... capped at 30.0s).
  - Inbound streaming: decodes `AetherOTPPayload` frames using `AetherFrameDecoder`.
  - Outbound acknowledgments: encodes `AetherOTPAcknowledgment` frames using `AetherFrameCodec`.
  - Validates `expiresAt > Date()` upon receipt before emitting to UI.
- **Unit Tests:**
  - `testClientConnectsAndPerformsHandshake`: Verifies client setup.
  - `testClientAutoReconnectsAfterServerRestart`: Verifies backoff and reconnection.
  - `testClientRejectsExpiredPayloadOnReceipt`: Verifies expiry check.
  - `testClientEmitsValidAcknowledgment`: Verifies acknowledgment transmission.
- **Rollback:** Delete `Sources/AetherCore/Transport/AetherIPCClient.swift`.

---

### Milestone 6: Droplet Bundle Packaging & Manifest
- **Scope:** Package `Aether.droplet` bundle with `droplet.json`.
- **Responsibilities:**
  - Create bundle structure: `Aether.droplet/Contents/{Info.plist, MacOS/Aether, Resources/droplet.json}`.
  - Configure `droplet.json`:
    - `id`: `"aether"`
    - `name`: `"AETHER"`
    - `category`: `"Productivity"`
    - `kit`: `abi: 1`, `minAPI: "1.16.0"`
    - `capabilities`: `["clipboardWrite"]`
    - `surfaces`: `["notch-hud", "settings-pane"]`
  - Compile dynamic library linked against `DroppyKit.framework`.
  - Verification: install to `~/Library/Application Support/Droppy/Droplets/aether/` and verify Droppy loads without errors.
- **Acceptance Criteria:**
  - `Droppy.app` launches and lists `AETHER` in its installed droplets without crashing.
- **Rollback:** Remove `Aether.droplet` from `~/Library/Application Support/Droppy/Droplets/`.

---

### Milestone 7: End-to-End Presentation & User Clipboard Bridge
- **Scope:** Implement presentation logic inside `Aether.droplet`.
- **Responsibilities:**
  - On `AetherOTPPayload` receipt:
    - Dispatch to `@MainActor`.
    - Construct `DropletHUDCard(title: payload.serviceLabel, message: "Verification Code: " + payload.otpCode, actions: [copyAction])`.
    - Present via `host.hud.present(request)`.
    - Emit `.displayed` acknowledgment back over socket.
  - On user clicking "Copy" or auto-copy:
    - Write to clipboard: `NSPasteboard.general.setString(code, forType: .string)`.
    - Emit `.copied` acknowledgment back over socket.
  - On auto-dismiss timer expiration:
    - Emit `.expired` acknowledgment back over socket.
- **Acceptance Criteria:**
  - Simulated incoming email with OTP triggers native Notch HUD card within 5ms.
  - Clicking "Copy" places code in clipboard and updates acknowledgment state.
- **Rollback:** Disable presentation bridge; revert to menu bar UI only.

---

## 4. Comprehensive Test Plan Matrix

| Test Suite | Test Case Count | Focus Area | Success Metric |
| :--- | :--- | :--- | :--- |
| **`AetherEndpointTests`** | 6 tests | Directory permissions, symlinks, lock files, unmask | 100% pass |
| **`AetherPeerValidatorTests`**| 8 tests | Audit tokens, Team ID, bundle ID, fail-closed policy | 100% pass |
| **`AetherTransportServerTests`**| 10 tests | Accept loop, client session, sequential write, reconnect | 100% pass |
| **`AetherHandshakeReplayTests`**| 8 tests | Session token, 2.0s deadline, replay ring buffer | 100% pass |
| **`AetherIPCClientTests`** | 8 tests | Async connect, auto-reconnect backoff, inbound decode | 100% pass |
| **Existing Test Suites** | 310 tests | `CodeCatchTests`, `CodeCatchCoreTests`, `AetherCoreTests` | 0 regressions |
| **Total Automated Tests** | **350 tests** | Full end-to-end integration | **100% pass** |

---

## 5. Rollback & Emergency Containment

If any defect, regression, or incompatibility is discovered during any milestone:
1. **Immediate Transport Isolation:** Set `Prefs.droppyEnabled = false`. Host immediately closes listening socket FD, unlinks `droplet.sock`, and releases lock.
2. **Fallback Preserved:** Menu bar UI remains 100% functional; user continues receiving OTP notifications via native macOS menu bar popover.
3. **Repository Reversion:** Git working tree changes for the affected milestone can be reverted without touching the untouched baseline backup at `/Users/nilambarbehera/Documents/Projects/Aether_Backups/Aether_baseline_20261109`.

