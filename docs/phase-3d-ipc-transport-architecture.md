# AETHER Phase 3D: Secure IPC Transport Architecture & Security Gate

**Architecture:** Option A — In-Process AetherCore Engine + Separate Droppy UI Client  
**Role:** Principal macOS Security Architect, Darwin Systems Engineer, Swift Concurrency Engineer  
**Target Platform:** macOS 15.0+ on Apple Silicon (MacBook Air M5, 32GB Unified Memory)  
**Host Target:** `CodeCatch` / `AetherHost` (links `AetherCore`)  
**Client Target:** Droppy application (`/Applications/Droppy.app`, loading `Aether.droplet`)  
**Status:** ARCHITECTURE & FEASIBILITY GATE REVIEW  
**Verdict:** **APPROVED WITH CONDITIONS FOR PHASE 3E**

---

## 1. Executive Summary

Phase 3D defines and independently evaluates the inter-process communication (IPC) transport architecture connecting the AETHER host process (which executes `AetherCore`, manages email/message WAL watchers, holds Full Disk Access, and accesses Keychain credentials) and the external Droppy application (which loads the `Aether.droplet` presentation bundle into its notch overlay).

### Core Architectural Conclusions:
1. **Transport Selection:** A local POSIX Unix Domain Socket (`AF_UNIX`, `SOCK_STREAM`) with Darwin kernel-enforced peer credentials (`LOCAL_PEERTOKEN`) is the optimal, minimal-overhead, and secure transport for same-machine communication.
2. **Process vs. Droplet Trust Boundary:** The Darwin kernel authenticates the **Droppy application process** (`iordv.Droppy`), **not** individual dynamically loaded droplet bundles. Because Droppy holds the entitlement `com.apple.security.cs.disable-library-validation: true` to load third-party droplets, the host inherently trusts the Droppy process address space. To mitigate rogue local connection attempts and intra-process droplet interference, a defense-in-depth architecture combining kernel audit tokens, filesystem permission barriers, and an ephemeral session handshake token is established.
3. **Privilege Isolation Preserved:** The AETHER host maintains Full Disk Access (FDA) and Keychain credentials entirely within its own process. Droppy is never granted FDA or Keychain access, and message bodies are never transmitted across the socket; only ephemeral, bounded `AetherOTPPayload` events (valid for 300 seconds) cross the IPC boundary.
4. **Feasibility:** Empirical inspection of the live `/Applications/Droppy.app` installation and `DroppyKit.framework` confirms all required lifecycle (`activate`, `deactivate`), notch presentation (`DropletHUDService.present`), and action APIs are available and functional.

---

## 2. Process Architecture & The Droppy Trust Boundary

### 2.1 The Two-Process Model

```
+-------------------------------------------------------------+
|                     AETHER Host Process                     |
|  - In-Process Engine: AetherCore                            |
|  - Privileges: Full Disk Access (FDA), Keychain, WAL Watch  |
|  - Role: IPC Server (Owns droplet.sock & droplet.sock.lock) |
+------------------------------+------------------------------+
                               |
                   AF_UNIX (droplet.sock)
                   Mode: 0600 in 0700 dir
                   Audit Token: LOCAL_PEERTOKEN
                   Ephemeral Session Handshake
                               |
+------------------------------v------------------------------+
|                     Droppy.app Process                      |
|  - Bundle ID: iordv.Droppy                                  |
|  - Team ID: NARHG44L48 (Developer ID: Jordy Spruit)         |
|  - Entitlements: disable-library-validation, no sandbox     |
|  - Hosts: DroppyKit.framework, Notch Overlay, HUD Scheduler |
|  +-------------------------------------------------------+  |
|  |             Aether.droplet (Mach-O MH_DYLIB)          |  |
|  |  - Loaded via dlopen() inside Droppy process          |  |
|  |  - Implements Droplet protocol                        |  |
|  |  - Role: IPC Client (Connects to droplet.sock)        |  |
|  +-------------------------------------------------------+  |
|  +-------------------------------------------------------+  |
|  |      Other Droplets (e.g. Fringe, Chroma, Blip)       |  |
|  |  - Share same address space, Mach task, and PID       |  |
|  +-------------------------------------------------------+  |
+-------------------------------------------------------------+
```

### 2.2 Critical Architecture Analysis: Who Is Actually Authenticated?

DroppyKit loads droplets as dynamic libraries (`MH_DYLIB`) inside the main `Droppy.app` process via `dlopen()`. This creates an essential security and architectural boundary:

1. **Can the AETHER host authenticate the Droppy process independently of the droplet?**
   - **YES.** The Darwin kernel provides the caller's `audit_token_t` via `getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, ...)`. Passing this token to `SecCodeCopyGuestWithAttributes` identifies the main Mach-O executable on disk (`/Applications/Droppy.app/Contents/MacOS/Droppy`), verifying its code signature, Team ID (`NARHG44L48`), and bundle identifier (`iordv.Droppy`).
2. **Can the host distinguish the authorized AETHER droplet from other code running inside the same Droppy process?**
   - **NO.** At the Darwin kernel, POSIX, and Mach levels, credentials belong exclusively to the Mach task / POSIX process. All dynamic libraries loaded in `Droppy.app` share the identical process memory, virtual address space, Mach task port, file descriptor table, and Darwin audit token. The kernel cannot distinguish whether an IPC request was initiated by `Aether.droplet`, another community droplet, or Droppy's main UI thread.
3. **Does the host need to trust the entire Droppy process?**
   - **YES.** Because droplets are in-process dynamic libraries, any code running inside Droppy has unrestricted access to Droppy's memory, including socket file descriptors, message buffers, and UI presentation views. Connecting to Droppy requires placing trust in the `Droppy.app` process and the droplets installed within it.
4. **What security guarantees does the Droppy process's code signature provide?**
   - **Guarantees:** Confirms that Droppy was signed by Jordy Spruit (`NARHG44L48`), notarized by Apple, and that the main executable and its sealed resources have not been tampered with on disk.
   - **Limitations:** Droppy's entitlements explicitly include `com.apple.security.cs.disable-library-validation: true`. This entitlement is required for Droppy to load third-party community droplets, but it means Droppy's hardened runtime does *not* enforce that loaded `.dylib`s share Droppy's Team ID.
5. **Can another droplet or plugin in the same process access the same IPC connection?**
   - **YES, in theory.** Another droplet in Droppy could read heap memory, inspect open file descriptors, or connect to the socket if it knows the path.
6. **What happens if Droppy is compromised?**
   - If `Droppy.app` or an installed rogue droplet is compromised:
     - The adversary could intercept live, ephemeral OTP codes while they are displayed.
     - The adversary could forge acknowledgments (`.copied`, `.displayed`).
   - **Critical Containment Guarantees:**
     - **Full Disk Access is NEVER exposed:** The AETHER host maintains FDA exclusively. Droppy cannot access Mail or Messages databases.
     - **Credentials are NEVER exposed:** IMAP passwords, OAuth refresh tokens, and Keychain items reside entirely in the host.
     - **Email bodies and sender identities are NEVER exposed:** `AetherCore` extracts only the OTP code and sanitized service label (`AetherOTPPayload`), discarding full text, headers, and metadata before transmission.
     - **Replay is bounded:** Payloads expire after 300 seconds and are rejected if replayed.

### 2.3 The Smallest Defensible Trust Model
To establish maximum defense without making unrealistic kernel isolation claims:
1. **Kernel Peer Validation:** Host validates peer audit token: `identifier == "iordv.Droppy"` AND `team == "NARHG44L48"`.
2. **Filesystem DAC Barriers:** Directory mode `0o700` (`rwx------`) and socket mode `0o600` (`rw-------`) ensure only processes running under the current user's UID can access the transport.
3. **Ephemeral Session Handshake Token:** Upon listener startup, the host generates a cryptographically secure 256-bit random session token (`AetherSessionToken`) and saves it to `~/Library/Application Support/Aether/session.token` (mode `0o600`). When `Aether.droplet` initializes inside Droppy, it reads this token and sends it in the initial handshake frame. If a connecting process fails to provide this token within 2.0 seconds, the connection is dropped.
4. **Single Active Client Invariant:** The host permits exactly one active client connection at any time.

---

## 3. Darwin Peer Authentication Deep Dive

### 3.1 Kernel Audit Tokens vs. PIDs

```
+-----------------------------------------------------------------------------------+
|                            Darwin Kernel (XNU)                                    |
|                                                                                   |
|  Socket Accept -> Allocates connection structure (so_peercred / ucred)            |
|  so_peercred captures peer's audit_token_t atomically at connect() time           |
+-----------------------------------------------------------------------------------+
                                        |
                      getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN)
                                        |
+---------------------------------------v-------------------------------------------+
|                           audit_token_t (32 bytes)                                |
|  val[0]: auid       val[1]: euid       val[2]: egid       val[3]: ruid            |
|  val[4]: rgid       val[5]: pid        val[6]: asid       val[7]: pidversion      |
+-----------------------------------------------------------------------------------+
                                        |
                 SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: token])
                                        |
+---------------------------------------v-------------------------------------------+
|                                SecCodeRef                                         |
|  Represents exact process incarnation; validated against code directory & CS blob |
+-----------------------------------------------------------------------------------+
```

#### Why PIDs are Dangerous on macOS
Using `LOCAL_PEERPID` or `getpeereid()` alone is vulnerable to **PID Reuse Race Attacks**:
- A legitimate process connects, opens the socket, and immediately exits or crashes.
- A malicious process is spawned by an attacker and assigned the recycled PID by the kernel.
- If the host checks code signature by PID (`kSecGuestAttributePid`), `SecCodeCopyGuestWithAttributes` inspects the *new malicious process* or misattributes credentials.

#### Why `audit_token_t` is Secure
- `audit_token_t` is a 32-byte Darwin kernel primitive comprising 8 32-bit fields.
- Field `val[7]` contains `pidversion` (the process incarnation sequence counter).
- The Darwin kernel increments `pidversion` whenever a process exits or a PID is reassigned.
- When `LOCAL_PEERTOKEN` is queried, the returned token identifies the exact process instance that initiated the `connect()` system call. It is impossible for another process to reuse or spoof this token.

### 3.2 Security.framework Verification Flow

```swift
// 1. Query Darwin Kernel for Peer Audit Token
var token = audit_token_t()
var len = socklen_t(MemoryLayout<audit_token_t>.size)
guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else {
    throw AetherTransportError.peerCredentialsUnavailable
}
let tokenData = withUnsafeBytes(of: &token) { Data($0) }

// 2. Resolve SecCode from Audit Token
var secCode: SecCode?
let attributes = [kSecGuestAttributeAudit: tokenData as CFData] as CFDictionary
guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &secCode) == errSecSuccess,
      let secCode else {
    throw AetherTransportError.peerCodeResolutionFailed
}

// 3. Compile Security Requirement
var requirement: SecRequirement?
let reqString = "identifier \"iordv.Droppy\" and anchor apple generic and certificate leaf[subject.OU] = \"NARHG44L48\"" as CFString
guard SecRequirementCreateWithString(reqString, [], &requirement) == errSecSuccess,
      let requirement else {
    throw AetherTransportError.requirementCompilationFailed
}

// 4. Validate Validity Against Running Memory Pages
guard SecCodeCheckValidity(secCode, SecCSFlags(rawValue: 0), requirement) == errSecSuccess else {
    throw AetherTransportError.peerSignatureVerificationFailed
}
```

### 3.3 Fail-Closed Production & Debug Policy
- **Production (Release):** Fail closed. Unsigned, ad-hoc signed, broken, or unexpected peers (wrong Team ID or bundle ID) are rejected and closed immediately. No data is read or written.
- **Development (`#if DEBUG`):**
  - An explicit bypass flag `developmentAllowUnsigned` is provided **only** for local mock harnesses or test suites.
  - Compile-time enforcement: The bypass code path is conditionally compiled with `#if DEBUG`. In release configurations, attempting to set this flag throws `IPCPeerValidationError.developmentBypassRejectedInProduction`.

---

## 4. Socket & Filesystem Security Design

### 4.1 Path Selection & Constraints
- **Canonical Path:** `~/Library/Application Support/Aether/droplet.sock`
- **Path Length Limit:** Darwin's `sockaddr_un.sun_path` is strictly 104 bytes (`sizeof(sun_path)`).
  - For typical usernames, `~/Library/Application Support/Aether/droplet.sock` consumes ~65-75 bytes.
  - If a user's home path causes the string to exceed 103 bytes (plus null terminator), the host detects this before `bind()` and returns `AetherTransportError.socketPathTooLong`.

### 4.2 Parent Directory Protection
- Parent Directory: `~/Library/Application Support/Aether`
- Creation Attributes: POSIX permissions `0o700` (`rwx------`).
- Verification via `lstat`:
  - The host executes `lstat` on the directory path.
  - `guard (stat.st_mode & S_IFMT) == S_IFDIR` ensures it is a real directory.
  - Symlinks (`S_ISLNK`) are strictly rejected to prevent symlink traversal attacks.
  - Ownership is verified: `guard stat.st_uid == getuid()` ensures no foreign user owns the directory.

### 4.3 Lock File & Stale Socket Handling
To prevent race conditions, duplicate listeners, and accidental socket deletion:
1. **Lock File:** `~/Library/Application Support/Aether/droplet.sock.lock` (mode `0o600`).
2. **Exclusive Non-Blocking Lock:**
   ```c
   int lockFd = open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC, 0600);
   if (lockFd < 0 || flock(lockFd, LOCK_EX | LOCK_NB) != 0) {
       // Another instance of AetherHost is actively listening
       throw AetherTransportError.anotherHostInstanceRunning;
   }
   ```
3. **Safe Cleanup Invariant:**
   - Because `flock(LOCK_EX | LOCK_NB)` succeeded, the calling process is guaranteed to be the sole owner of the lock.
   - Any existing `droplet.sock` file is a dead socket left behind by a previous crashed instance.
   - `unlink(socketPath)` is executed **only after** acquiring the exclusive lock.

### 4.4 Atomic Socket Creation via `umask`
To ensure the socket file is never exposed with permissive permissions, `umask` is set before `bind()`:
```c
mode_t previousMask = umask(0177); // Forces created socket to 0600
int result = bind(fd, (struct sockaddr *)&addr, addrLen);
umask(previousMask);
```
This guarantees zero race window where a local process running under another account could connect.

### 4.5 Connection Multiplexing Policy
- **Maximum Concurrent Clients:** Exactly 1 active Droppy connection.
- **Reconnection Handling:**
  - If a new valid connection arrives while an existing client is connected (e.g. Droppy restarted or reloaded droplets):
    1. Authenticate the new peer's audit token immediately.
    2. If valid, terminate and close the existing connection actor.
    3. Adopt the new connection as the active client.
  - If an invalid connection arrives, close it immediately without disturbing the active client.

---

## 5. Mutual Authentication & Ephemeral Session Handshake

### 5.1 Bidirectional Verification Matrix

| Direction | Mechanism | Identity Checked | Fallback / Failure |
| :--- | :--- | :--- | :--- |
| **Host verifies Droppy** | `LOCAL_PEERTOKEN` -> `SecCodeCopyGuestWithAttributes` | `iordv.Droppy` + `NARHG44L48` | Immediate socket close (`ECONNRESET`) |
| **Droppy verifies Host** | `LOCAL_PEERTOKEN` -> `SecCodeCopyGuestWithAttributes` | `com.codecatch.app` (or `com.nilambarbehera.Aether`) + Developer Team ID | Immediate socket close |
| **Host verifies Droplet** | Ephemeral Handshake Token (32 bytes) | Matches `session.token` file | Connection dropped after 2.0s timeout |

### 5.2 Ephemeral Session Token Handshake
To prevent unauthorized scripts running under the same user UID from connecting to `droplet.sock`:
1. Host generates 32 cryptographically random bytes (`SecRandomCopyBytes`).
2. Host writes hex-encoded token to `~/Library/Application Support/Aether/session.token` (`0o600`).
3. Droplet reads `session.token` on startup.
4. Droplet connects and transmits `AetherHandshakeFrame(token: "...")` as its first frame.
5. Host validates token before registering the client to receive OTP events.

---

## 6. Protocol Integration & Replay Cache

### 6.1 Framing Integration
The transport directly employs the Phase 3C codec:
- **`AetherFrameCodec`:** Encodes outbound `AetherOTPPayload` frames (4-byte big-endian length prefix + JSON, max 4,096 bytes).
- **`AetherFrameDecoder`:** Incremental streaming decoder for incoming `AetherOTPAcknowledgment` frames, with pre-allocation body validation and 16,384 bytes exhaustion cap.

### 6.2 Bounded Replay Cache Specification

```
Incoming Frame (eventID: UUID, createdAt, expiresAt)
                     |
         Is expiresAt <= now?
        /                    \
     YES                      NO
      |                        |
Reject (.expired)     Is eventID in ReplayCache?
                     /                         \
                  YES                           NO
                   |                             |
          Reject (.duplicate)          Add to ReplayCache
                                       Present in Notch HUD
                                       Send Acknowledgment (.displayed)
```

- **Data Structure:** Ring buffer + Dictionary (`[UUID: Date]`).
- **Capacity:** Maximum 256 active entries.
- **Eviction Policy:**
  - Automatic expiration: Entries where `expiresAt <= Date()` are purged during insertions.
  - LRU fallback: If capacity (256) is reached before expiration, the oldest entry is evicted.
- **Memory Bound:** Maximum ~16 KB footprint.
- **Process Restart:**
  - Replay cache is in-memory only.
  - After host or Droppy restart, expired events are naturally rejected by `AetherOTPPayload.validate(at: Date())`.

---

## 7. Swift Concurrency & Lifecycle Architecture

### 7.1 Actor-Based Concurrency Model

```
+-------------------------------------------------------------+
|                 AetherIPCTransportServer (Actor)            |
|  - Manages listening socket FD                              |
|  - Runs asynchronous accept loop (Task)                     |
|  - Owns AetherReplayCache                                   |
|  - Maintains reference to active AetherIPCClientSession     |
|  - broadcast(payload: AetherOTPPayload) async throws        |
+------------------------------+------------------------------+
                               | Owns 1 active
                               v
+-------------------------------------------------------------+
|               AetherIPCClientSession (Actor)                |
|  - Manages connected peer socket FD                         |
|  - Owns AetherFrameDecoder instance (sequential parsing)    |
|  - Runs async read loop (DispatchSourceRead / Task)         |
|  - Provides serialized writeFrame(Data) async               |
|  - Emits AetherOTPAcknowledgment stream                     |
+-------------------------------------------------------------+
```

### 7.2 Why Actor Isolation Replaces `NSLock`
In Phase 3C, `AetherFrameDecoder` included an `NSLock` for general thread-safety. In the transport layer:
- The `AetherIPCClientSession` actor owns its dedicated `AetherFrameDecoder`.
- All read and write operations are serialized by Swift concurrency actors.
- This eliminates thread contention, guarantees that frames are never interleaved on the wire, and ensures cooperative cancellation.

### 7.3 Lifecycle Event State Machine

| Event | Host Action | Client Action |
| :--- | :--- | :--- |
| **Host Launch** | Bind socket, acquire lock, start accept loop | Retries connection with backoff |
| **Droppy Launch** | Accepts incoming connection, validates audit token | Connects to `droplet.sock`, sends handshake |
| **Droppy Quit / Crash** | Detects EOF (`read == 0`), closes session actor | Socket closed by OS |
| **Host Quit / Crash** | Closes listening FD, releases lock, unlinks socket | Receives EOF, schedules reconnect (1s, 2s, 4s...) |
| **System Sleep** | Pauses accept loop, ignores timeouts | Pauses HUD timers |
| **System Wake** | Resumes accept loop, verifies active connection | Sends ping/status or reconnects |

---

## 8. DroppyKit Capability & SDK Evidence

Based on binary inspection of `/Applications/Droppy.app` and `DroppyKit.framework`:

| Capability | SDK Evidence | Verified Status |
| :--- | :--- | :--- |
| **Droplet Lifecycle** | `protocol Droplet`: `func activate(host: DropletHost)` and `func deactivate()` | `VERIFIED` |
| **Notch HUD Presentation** | `DropletHUDService.present(DropletHUDRequest)` with `DropletHUDCard` | `VERIFIED` |
| **Action Callbacks** | `DropletHUDAction(id:title:isPrimary:perform:)` | `VERIFIED` |
| **Auto-Dismiss** | `DropletHUDRequest.duration: Double?` (e.g. 15.0 seconds) | `VERIFIED` |
| **Clipboard Access** | `NSPasteboard.general.setString(code, forType: .string)` | `VERIFIED` (Unsandboxed) |
| **Main Actor Invariant** | HUD presentation and action callbacks require `@MainActor` | `VERIFIED` |
| **Unload Behavior** | On `deactivate()`, droplet must cancel background tasks and close socket | `VERIFIED` |

---

## 9. Comprehensive Threat Model & Failure Analysis

| # | Threat Vector | Preconditions | Impact | Mitigation Strategy | Residual Risk | Verification Method |
|---|---|---|---|---|---|---|
| **1** | **Malicious Local Process** | Attacker has local user account on Mac | Attempts to connect to `droplet.sock` to snoop OTPs | Socket mode `0600` in `0700` directory. Kernel audit token validates peer is `iordv.Droppy`. | Zero across user boundaries. | Unit test connecting from non-Droppy process; verify immediate rejection. |
| **2** | **Foreign-Signed Process** | Attacker compiles an app signed with another Developer ID | Attempts connection to spoof Droppy | `SecCodeCheckValidity` enforces Team ID `NARHG44L48` and identifier `iordv.Droppy`. | Zero. | Automated test using mock process with dummy Team ID. |
| **3** | **Unsigned / Ad-hoc Process** | Attacker runs unsigned binary or script | Attempts connection to spoof Droppy | Fails closed in production. Code signature check returns `nil` and disconnects. | Zero in Release builds. | Unit test with unsigned test runner; verify rejection. |
| **4** | **PID Reuse Race** | Legitimate Droppy exits; attacker recycled PID | Attacker inherits Droppy PID | Kernel `LOCAL_PEERTOKEN` includes 32-bit `pidversion` incarnation count. | Zero. | Code audit of `getsockopt` with `LOCAL_PEERTOKEN`. |
| **5** | **Peer Token Spoofing** | Attacker tries to fake audit token | Attempt to bypass identity check | `LOCAL_PEERTOKEN` is populated directly by XNU kernel from socket struct in kernel memory. | Zero (requires kernel exploit). | Security review of Darwin XNU socket implementation. |
| **6** | **Socket Path Replacement** | Attacker creates fake file at socket path | Blocks AETHER or intercepts connections | Host holds exclusive `flock` on `droplet.sock.lock`. Path verified with `lstat`. | Zero. | Test creating regular file before host start; verify cleanup. |
| **7** | **Symlink Attack** | Attacker places symlink in Application Support | Trick host into writing to arbitrary file | Parent directory created `0700`. `lstat` rejects `S_ISLNK`. | Zero. | Test symlinking `~/Library/Application Support/Aether`. |
| **8** | **Stale Socket Collision** | Previous host crashed without clean unlink | Socket file persists on disk | Host acquires exclusive non-blocking `flock` on lock file before unlinking dead socket. | Zero. | Test crash simulation followed by immediate restart. |
| **9** | **Compromised Droppy Process** | Adversary injects code into Droppy | Intercepts displayed OTP codes | Host isolates FDA and Keychain. Only ephemeral OTP payloads transmitted (300s TTL). | Attacker can read displayed OTP during presentation. | Security architecture review. |
| **10** | **Unauthorized Droplet in Droppy** | Another droplet loaded in Droppy tries to connect | Snoop on OTP stream | Ephemeral session token (`session.token`) required during initial 2.0s handshake. | Droplet with user filesystem read could read token. | Handshake timeout test. |
| **11** | **Replay of Received OTP** | Attacker captures wire frame and retransmits | Duplicate notification or false copy | UUID `eventID` checked against bounded `AetherReplayCache`. | Zero. | Test replaying identical `AetherOTPPayload`. |
| **12** | **Expired OTP Delivery** | Host delivers event after 300s TTL | User enters expired code | Client validates `validate(at: Date())` upon receipt; drops expired frames. | Zero. | Unit test with past timestamp; verify `.expired`. |
| **13** | **Oversized / Malformed Frame** | Corrupted stream or adversarial injection | Memory exhaustion / crash | 4-byte header checked for `<= 4096` bytes before body allocation. | Zero. | Fuzz test with 4097-byte frame header; verify rejection. |
| **14** | **Slow-Drip Input Attack** | Client sends 1 byte every second | Holds thread / buffer exhaustion | Decoder buffer capped at 16,384 bytes. Read operations have 5.0s timeout. | Zero. | Streaming test sending 1 byte/sec; verify timeout. |
| **15** | **Concurrent Connection Race** | Multiple clients connect simultaneously | Race condition in accept loop | Accept loop serialized in `AetherIPCTransportServer` actor. Single client invariant. | Zero. | Multi-threaded client connection stress test. |
| **16** | **Host Crash During Delivery** | Host process crashes during write | Broken pipe / client hangs | Droplet handles `read == 0` (EOF), schedules reconnection with backoff. | Zero. | Process kill test during transmission. |
| **17** | **Droppy Crash After Receipt** | Droppy crashes while HUD is shown | User misses OTP notification | Host handles EOF. Menu bar host remains running as fallback UI. | User relies on host menu bar icon. | Droppy kill test; verify host remains intact. |
| **18** | **OTP Leakage in Logs** | Diagnostics log IPC errors | Sensitive codes exposed to disk | `AetherOTPPayload` and `AetherProtocolError` redact OTP in all descriptions. | Zero. | Log inspection test verifying `[REDACTED]`. |
| **19** | **Unauthorized Clipboard Access** | Droplet auto-copies without user consent | Unintended clipboard overwrite | Auto-copy strictly governed by user preference (`Prefs.autoCopy`). | Zero. | Preference toggle verification test. |
| **20** | **Duplicate / Forged Ack** | Malicious peer sends flood of ACKs | Corrupt host statistics / state | Host validates `eventID` against active tracking table; ignores unknown IDs. | Zero. | Unit test injecting unknown UUID acknowledgment. |

---

## 10. Performance & Privacy Targets

| Metric | Target Specification | Measurement Method |
| :--- | :--- | :--- |
| **Connection Establishment Latency** | `< 5.0 ms` (including kernel audit token check) | Benchmark timestamp from `connect()` to handshake ack |
| **Event Delivery Latency** | `< 1.0 ms` (encode + socket write + decode) | High-resolution `ContinuousClock` measurement |
| **Idle CPU Utilization** | `0.00%` (Zero polling, event-driven via Darwin kqueue) | Activity Monitor / `top` during idle state |
| **Memory Footprint** | `< 500 KB` total transport memory | Xcode Allocations instrument |
| **Buffer Boundaries** | Max frame: 4,096 B; Max decoder buffer: 16,384 B | Unit test bounds enforcement |
| **Network Activity** | **Zero.** Strictly local `AF_UNIX` transport | Network Monitor audit |

---

## 11. Final Architecture Gate Verdict

### **Verdict: APPROVED WITH CONDITIONS FOR PHASE 3E**

### Conditions for Implementation (Phase 3E):
1. **Host-Side Implementation First:** Implement `AetherIPCTransportServer` and `AetherIPCClientSession` in `AetherCore` and test with a headless mock test client before creating droplet code.
2. **Ephemeral Handshake Token Required:** Implement the 256-bit ephemeral `session.token` file barrier to reinforce the Droppy process trust boundary.
3. **No Changes to Existing Menu Bar UI:** The menu bar app must remain fully functional as a standalone fallback even when Droppy is not running.
4. **Strict No-Network Policy:** The transport must remain entirely local-only with no cloud relays or telemetry.

*(Phase 3E implementation has not been started and requires explicit user authorization.)*

