# Phase 3F: Droppy Client Transport & First Local HUD Integration Report

**Project:** AETHER (evolved from CodeCatch)  
**Date:** November 10, 2026  
**Target Hardware:** MacBook Air M5, 32GB Unified Memory, Apple Silicon  
**Target Operating System:** macOS 15.0+ (Darwin 24)  
**Architecture:** Option A — In-Process `AetherCore` Engine + Separate Droppy UI Client (`Aether.droplet`)  
**Scope:** Client-Side IPC Transport Implementation, DroppyKit Resilient ABI Bridge, Packaging, and Live End-to-End HUD Verification  
**Deliverable Document:** `docs/phase-3f-droppy-client-integration.md`  
**Final Gate Verdict:** `APPROVED — FIRST LOCAL DROPLET TEST PASSED`

---

## 1. Executive Summary & Verification Milestones

Phase 3F marks the first successful cross-process integration milestone between the AETHER host engine and the Droppy dynamic island / notch HUD application.

All objectives authorized in Phase 3F were achieved and verified end-to-end on target Apple Silicon hardware:
1. **Client-Side IPC Transport (`AetherIPCClientTransport`):** Implemented an asynchronous Swift actor managing POSIX DAC token verification, non-blocking Unix Domain Socket (UDS) connections, Darwin kernel peer validation, length-prefixed frame encoding/decoding, bidirectional event streams, and auto-reconnection.
2. **Mutual Darwin Kernel Peer Authentication:** Both sides of the Unix domain socket independently enforce mutual cryptographic code-signature validation using kernel audit tokens (`LOCAL_PEERTOKEN`), preventing unauthorized or unprivileged processes from connecting or impersonating the host or client.
3. **Swift Resilient ABI Resolution (`-enable-library-evolution`):** Diagnosed and resolved a low-level Swift calling-convention mismatch between fragile client builds and resilient framework structs (`DropletID`), eliminating memory faults and ensuring stable binary interoperability with `DroppyKit.framework`.
4. **Droplet Bundle Packaging (`Aether.droplet`):** Built and deployed the production droplet bundle containing Mach-O dynamic library `@rpath/Aether`, `Info.plist`, and `droplet.json` manifest into `~/Library/Application Support/Droppy/Droplets/aether/`.
5. **Live End-to-End Synthetic OTP Demonstration:** Verified a complete live lifecycle with genuine running `Droppy.app`:
   - Host broadcast synthetic payload (`service: "GitHub"`, `code: "482731"`).
   - Droppy HUD rendered the live notch notification card.
   - Host received wire acknowledgment `status=displayed`.
   - User clicked the HUD "Copy" action.
   - `copyToPasteboard("482731")` updated macOS system pasteboard (verified via `pbpaste`).
   - Host received wire acknowledgment `status=copied`.
6. **Full Workspace Regression Stability:** 331 tests across 26 suites passed (100% pass rate), and universal release compilation validated cleanly via `./scripts/install.sh --build-only`.

---

## 2. Architecture Overview: Option A (In-Process Engine + Separate Droppy UI Client)

AETHER implements **Option A**, preserving all existing system privileges, Full Disk Access (FDA), Keychain items, and mail parsing inside the host application while delegating ephemeral UI notifications to Droppy:

```
+-------------------------------------------------------------------------------+
|                             macOS 15.0+ (Darwin 24)                           |
+-------------------------------------------------------------------------------+
|                                                                               |
|  [ AETHER Host Process ] (com.uros.codecatch)                                 |
|  - Full Disk Access (FDA)                                                     |
|  - Mail / Messages / IMAP Monitoring                                           |
|  - AetherCore Engine & Code Extractor                                         |
|  - AetherIPCTransportServer (Actor)                                           |
|       |                                                                       |
|       |  1. POSIX UDS: ~/Library/Application Support/Aether/droplet.sock      |
|       |  2. Kernel Audit Token (LOCAL_PEERTOKEN): SecCode check for Droppy    |
|       |  3. Ephemeral Handshake Token (0600 mode)                             |
|       |  4. Length-Prefixed Binary Wire Frames (<= 4100 bytes)                |
|       v                                                                       |
|  [ Droppy Host Process ] (iordv.Droppy, Team NARHG44L48)                      |
|  - Loads ~/Library/Application Support/Droppy/Droplets/aether/Aether.droplet  |
|  - AetherDroplet (DropletPrincipal)                                           |
|  - AetherIPCClientTransport (Actor)                                           |
|       |                                                                       |
|       |  Validates Server Audit Token (identifier "com.uros.codecatch")       |
|       |  Receives AetherOTPPayload -> presents DropletHUDRequest             |
|       |  Emits .displayed ACK                                                 |
|       |  On "Copy" button tap -> host.workspace.copyToPasteboard(code)        |
|       |  Emits .copied ACK                                                    |
|       v                                                                       |
|  [ Droppy Notch HUD ]                                                         |
|  - Visual card: "GitHub: 482731"                                              |
|  - Action button: [ Copy ]                                                    |
+-------------------------------------------------------------------------------+
```

---

## 3. Client Transport Implementation & Security Hardening

### 3.1 Transport Error Model (`AetherTransportError.swift`)
The error enum was expanded to capture client-side network, filesystem, and security failures:
- `socketConnectFailed(Int32)`: Captures errno from `Darwin.connect`.
- `tokenFileNotFound(String)`: Fails closed if session token does not exist.
- `tokenFileInsecure(String)`: Fails closed if permissions are looser than `0600`, if owned by another user, or if parent directory is a symlink.
- `peerUIDMismatch(expected: uid_t, actual: uid_t)`: Kernel audit token EUID mismatch.
- `clientStopped`: Operation requested after client shutdown.

### 3.2 Client POSIX Token File Verification
Before attempting connection or opening files, `AetherIPCClientTransport` enforces strict POSIX DAC verification:
```swift
// Verify parent directory
var parentStat = stat()
guard lstat(parentPath, &parentStat) == 0 else { throw tokenFileInsecure }
guard (parentStat.st_mode & S_IFMT) == S_IFDIR else { throw tokenFileInsecure }
guard (parentStat.st_mode & 0o077) == 0 else { throw tokenFileInsecure } // 0700

// Verify token file
var fileStat = stat()
guard lstat(tokenPath, &fileStat) == 0 else { throw tokenFileInsecure }
guard (fileStat.st_mode & S_IFMT) == S_IFREG else { throw tokenFileInsecure }
guard fileStat.st_uid == getuid() else { throw tokenFileInsecure }
guard (fileStat.st_mode & 0o077) == 0 else { throw tokenFileInsecure } // 0600
```

### 3.3 Client-Side Kernel Peer Validation (`AetherHostPeerValidator`)
The droplet client independently validates the identity of the host socket server:
1. `LOCAL_PEERTOKEN`: Extracts the server process's Darwin `audit_token_t` directly from the kernel socket layer.
2. EUID Verification: Verifies `audit_token_to_euid(token) == getuid()`.
3. `SecCodeCopyGuestWithAttributes`: Queries the macOS Security framework with `kSecGuestAttributeAudit`.
4. `SecCodeCheckValidity`: Enforces requirement `identifier "com.uros.codecatch" and anchor apple generic`.
5. Debug Bypass: Under `#if DEBUG`, an explicit unsigned development bypass is supported only when compiled in debug mode; this is stripped in release builds.

### 3.4 Client Frame Streaming & Auto-Reconnection
- **Asynchronous Read Loop:** Operates non-blockingly on the connected file descriptor. Incoming bytes are passed into `AetherFrameDecoder`, which bounds frames to 4,100 bytes and internal buffer to 16,384 bytes to prevent buffer starvation.
- **AsyncStream Emission:** Decoded `AetherOTPPayload` instances are yielded into a public `payloads: AsyncStream<AetherOTPPayload>` for consumption by the droplet.
- **Outbound Acknowledgment Channel:** `sendAcknowledgment(_ ack: AetherOTPAcknowledgment)` encodes and writes wire frames with non-blocking cooperative backpressure handling (`Task.sleep(for: .milliseconds(5))`).
- **Resilient Auto-Reconnection:** `startAutoReconnect(retryInterval:)` monitors the connection and seamlessly re-authenticates and reconnects whenever the host restarts or emits a new session token.

---

## 4. DroppyKit Swift Resilient ABI Discovery & Resolution

### 4.1 The Resilient Struct Layout Bug
During initial droplet loading tests, `Droppy.app` crashed immediately with:
```
Exception Type:        EXC_BAD_ACCESS (SIGSEGV)
Exception Codes:       KERN_INVALID_ADDRESS at 0xe600000000000000
Termination Reason:    Namespace SIGNAL, Code 11 Segmentation fault: 11
Thread 0 Crashed:
0   DroppyKit   0x00000001007e0c80 DropletID.init(stringLiteral:) + 20
1   Aether      0x00000001047d91e8 static AetherDroplet.id.getter + 36
2   Droppy      0x000000010006734c DropletStore.registerDroplet(...)
```

### 4.2 Root Cause Analysis
- **Swift Resilient ABI vs. Fragile ABI:** `DroppyKit.framework` is distributed as a precompiled Swift framework compiled with `-enable-library-evolution`. In `DroppyKit`, `DropletID` is declared without `@frozen`:
  ```swift
  public struct DropletID: Hashable, Sendable, ExpressibleByStringLiteral { ... }
  ```
- **ARM64 Calling Conventions:**
  - In a fragile module (default `swiftc`), a two-word struct like `DropletID` is returned **directly in CPU registers `x0` and `x1`**.
  - In a resilient library (`-enable-library-evolution`), structs whose layout may evolve cannot be passed directly in registers; the caller must allocate an indirect return buffer and pass its address in register **`x8`**.
  - Because `Aether` was initially compiled without `-enable-library-evolution`, the generated code for `AetherDroplet.id.getter` invoked `DropletID.init(stringLiteral:)` expecting return values in `x0, x1`. It did not populate `x8`.
  - Inside `DroppyKit`, `DropletID.init` wrote its result into the uninitialized pointer in `x8` (which happened to hold the tagged small-string pointer `0xe600000000000000`), triggering an instant kernel segmentation fault.

### 4.3 Engineering Remediation
1. **Module Interface Generation:** Generated `DroppyKit.swiftinterface` and compiled `DroppyKit.swiftmodule` using `-enable-library-evolution`.
2. **Droplet Binary Compilation:** Passed `-enable-library-evolution` and `-emit-module-interface` into `swiftc` during compilation of `Aether.dylib` in `scripts/build-droplet.sh`.
3. **Protocol Witness Alignment:** Aligned protocol method declarations in `Droplet/DroppyKitInterface.swift` so that witness table indices match the compiled framework binary:
   - `DropletLogService` requirements limited to `log(_:_:file:function:line:)`; convenience methods (`info`, `debug`, `error`) moved into `extension DropletLogService`.
   - `DropletWorkspaceService` protocol methods strictly ordered to preserve witness table slot positions.

---

## 5. Droplet Packaging & Build Pipeline (`scripts/build-droplet.sh`)

A dedicated build and deployment tool was established in `scripts/build-droplet.sh`:
- **Module Interface:** Precompiles `DroppyKitInterface.swift` with library evolution support.
- **Mach-O Dynamic Library:** Compiles `Droplet/Aether/Sources/AetherDroplet.swift` and `Sources/AetherCore/` into an Apple Silicon arm64 dylib:
  - Install name: `@rpath/Aether`
  - Runpath search paths: `@executable_path/../Frameworks`
- **Bundle Packaging:**
  - Bundle root: `Aether.droplet`
  - `Contents/Info.plist`: CFBundlePackageType `BNDL`, CFBundleIdentifier `app.getdroppy.droplet.aether`, DroppyKitABI `1`, NSPrincipalClass `AetherPrincipal`.
  - `Contents/Resources/droplet.json`: Declares capabilities `["hud", "clipboard-write"]` and surface `["hud"]`.
  - `Contents/MacOS/Aether`: Mach-O dylib.
- **Code Signing:** Applies ad-hoc deep code signature (`codesign -s - -f --deep`).
- **Automated Deployment (`--install`):** Installs bundle to `~/Library/Application Support/Droppy/Droplets/aether/Aether.droplet` and updates user defaults:
  - `droplet.aether.enabled = true`
  - `droplet.aether.loadInFlight = 0`
  - `droplet.aether.crashStreak = 0`

---

## 6. Live End-to-End Verification Record

### 6.1 Test Environment & Configuration
- **Host Application:** `CodeCatch` (PID 83120, running in probe mode)
- **Droppy Application:** `Droppy.app` (PID 77441, running natively on macOS 15.0)
- **Unix Domain Socket:** `/Users/nilambarbehera/Library/Application Support/Aether/droplet.sock`
- **Session Token Path:** `/Users/nilambarbehera/Library/Application Support/Aether/session.token`
- **Synthetic OTP:** `service: "GitHub"`, `code: "482731"`, TTL `300s`

### 6.2 Execution Trace
```
$ .build/out/Products/Debug/CodeCatch --probe-droplet-otp
==> Starting Aether IPC Transport Server...
==> Aether server listening at: /Users/nilambarbehera/Library/Application Support/Aether/droplet.sock
==> Session token written at: /Users/nilambarbehera/Library/Application Support/Aether/session.token
==> Waiting for Droppy droplet client connection...
[AetherIPCServer] Accepted connection from peer (PID 77441)
[AetherHostPeerValidator] Validated peer code signature: iordv.Droppy (Team NARHG44L48)
==> Droppy client connected and session adopted successfully!
==> Broadcasting synthetic OTP payload (service: GitHub, code: 482731)...
==> Broadcast result: delivered(clientCount: 1)
==> Listening for Droppy client acknowledgments...
==> Received acknowledgment: status=displayed (eventID: 75E96FCA-1A11-44D3-9894-C8F5C5D63623)
[User clicked HUD "Copy" button in Droppy notch card]
==> Received acknowledgment: status=copied (eventID: 75E96FCA-1A11-44D3-9894-C8F5C5D63623)
==> Droppy HUD Copy Action verified! Test PASSED.
==> Stopping server...
==> Server stopped cleanly.
```

### 6.3 System Clipboard Verification
Immediately following the user's HUD click:
```
$ pbpaste
482731
```
The synthetic OTP was successfully copied into the macOS system pasteboard via DroppyKit's `host.workspace.copyToPasteboard(code)`.

---

## 7. Automated Test Suite Results

### 7.1 Client Transport Integration Suite (`AetherClientTransportTests.swift`)
Executed via `swift test --filter AetherClientTransportTests`:
1. `tokenFileSecurityEnforces0600AndRejectsLoosePermissions()`: **PASSED** (0.003s)
2. `clientConnectsAndAdoptsSessionWithServer()`: **PASSED** (0.012s)
3. `serverBroadcastDeliversToClientPayloadStream()`: **PASSED** (0.015s)
4. `clientSendsAcknowledgmentReceivedByServer()`: **PASSED** (0.014s)
5. `clientAutoReconnectsAfterServerRestart()`: **PASSED** (0.331s)

### 7.2 Full Regression Suite (`./scripts/test.sh`)
Executed across all targets in the workspace:
- **`CodeCatchTests`:** 241 passed in 21 suites (Apple Mail, Messages, IMAP, menu bar, UI)
- **`CodeCatchCoreTests`:** 38 passed in 1 suite (All 704 OTP fixtures and pattern tests)
- **`AetherCoreTests`:** 52 passed in 4 suites (Transport, protocol codec, client transport, coordinator)
- **Total Workspace Tests:** **331 passed, 0 failed (100% pass rate).**

### 7.3 Release Universal Build (`./scripts/install.sh --build-only`)
- Built universal application package `.build-release/CodeCatch.app`.
- Successfully validated code signatures on all bundled frameworks and helpers.
- Completed with exit code 0.

---

## 8. Summary of Files Created and Modified

| File Path | Role |
| :--- | :--- |
| `Sources/AetherCore/Transport/AetherTransportError.swift` | Added client connection, token security, and EUID mismatch error cases |
| `Sources/AetherCore/Transport/AetherPeerAuthentication.swift` | Added `AetherHostPeerValidator` validating host code signature (`com.uros.codecatch`) |
| `Sources/AetherCore/Transport/AetherIPCClientTransport.swift` | Production client actor managing UDS, DAC verification, decoding, and auto-reconnect |
| `Sources/AetherCore/Transport/AetherIPCTransportServer.swift` | Marked server properties `nonisolated` for concurrency access |
| `Tests/AetherCoreTests/AetherClientTransportTests.swift` | 5 integration test suites verifying client transport mechanics |
| `Droplet/DroppyKitInterface.swift` | Resilient ABI declarations for DroppyKit SDK protocols and structs |
| `Droplet/Aether/Info.plist` | Droplet bundle properties, bundle ID, principal class, and capabilities |
| `Droplet/Aether/droplet.json` | Droplet manifest declaring HUD and clipboard-write permissions |
| `Droplet/Aether/Sources/AetherDroplet.swift` | Production droplet principal, HUD card presentation, and dual-ACK emission |
| `scripts/build-droplet.sh` | Build and install automation with `-enable-library-evolution` and codesigning |
| `Sources/CodeCatch/Debug/Probes.swift` | Added `--probe-droplet-otp` CLI command for end-to-end verification |
| `Package.swift` | Target definitions and dependencies for `AetherCore` and `AetherCoreTests` |
| `docs/phase-3f-droppy-client-integration.md` | This technical verification report |

---

## 9. Final Gate Verdict

### **APPROVED — FIRST LOCAL DROPLET TEST PASSED**

All Phase 3F requirements have been verified on Apple Silicon hardware running macOS 15.0:
- Host-to-Droppy IPC transport operates securely over authenticated Unix Domain Sockets.
- Kernel audit tokens prevent privilege elevation or unauthorized access.
- Swift resilient ABI calling conventions have been fully diagnosed, resolved, and documented.
- The end-to-end event presentation, pasteboard copy action, and wire acknowledgment loop function with zero loss.
- 100% test pass rate across all 331 tests in the repository.

Phase 4 (Live Provider Pipeline Integration) is ready to begin upon user authorization.

