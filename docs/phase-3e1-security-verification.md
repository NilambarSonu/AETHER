# Phase 3E.1: Independent Security Verification & Transport Hardening Report

**Project:** AETHER (evolved from CodeCatch)  
**Date:** November 10, 2026  
**Target Hardware:** MacBook Air M5, 32GB Unified Memory, Apple Silicon  
**Target Operating System:** macOS 15.0+  
**Architecture:** Option A — In-Process `AetherCore` Engine + Separate Droppy UI Client  
**Scope:** Independent Verification & Hardening of Host-Side Secure IPC Transport  
**Deliverable Document:** `docs/phase-3e1-security-verification.md`  
**Final Gate Verdict:** `APPROVED FOR PHASE 3F`  

---

## 1. Architecture and Verification Summary

Phase 3E implemented the host-side Unix Domain Socket (UDS) transport inside `AetherCore` to establish an authenticated, bounded, event-driven communication channel between the in-process AETHER engine and the future separate Droppy UI client process (`Aether.droplet`).

Phase 3E.1 performs an independent, adversarial security audit and targeted transport hardening of this subsystem prior to authorizing Phase 3F (Droplet Implementation & DroppyKit Bridge).

### 1.1 Non-Negotiable Operational Constraints Preserved
- **Repository Safety:** Verified branch `main`, no commits, no rebases, no destructive cleanups, no git resets.
- **Baseline Backup:** Verified intact baseline backup at `/Users/nilambarbehera/Documents/Projects/Aether_Backups/Aether_baseline_20261109`.
- **Identity & Credentials:** Zero modifications to bundle identifiers, Sparkle update keys, Keychain access, OAuth configuration, Full Disk Access, or existing `CodeCatch` signing identities.
- **Scope Containment:** Zero Droppy UI, HUD, clipboard integration, LaunchAgents, daemons, or XPC services introduced.
- **Zero-Secret Privacy:** Verified zero logging or caching of OTP values, handshake tokens, or raw email content.

---

## 2. Threat Model Analysis: Same-User POSIX DAC vs. Kernel Peer Validation

### 2.1 The Same-User POSIX DAC Reality
A common misconception in local IPC design is that filesystem permissions such as mode `0700` (`rwx------`) on a parent directory or mode `0600` (`rw-------`) on a token file prevent unauthorized local processes from accessing secrets.

On macOS (Darwin), POSIX Discretionary Access Control (DAC) enforces boundaries **between different user accounts (UIDs)**. 
- Process A running as user `nilambarbehera` (UID 501) writes `~/Library/Application Support/Aether/session.token` with mode `0600`.
- Any process B running as the **same user** (UID 501) has full operating system permission to read `~/Library/Application Support/Aether/session.token` and connect to `~/Library/Application Support/Aether/droplet.sock`.
- Standard POSIX DAC does **not** separate applications or processes running within the same user session.

### 2.2 What the Ephemeral Session Token Actually Achieves
Because same-user processes can read 0600 files, the ephemeral session token must NOT be claimed as an isolation barrier against malicious code running under the same UID. Instead, its actual cryptographic and operational guarantees are:
1. **Blind Connection & Port Scan Defense:** Defends against blind port scanners, background sweeps, or opportunistic local scripts that do not specifically know or read the AETHER Application Support path.
2. **Session Desynchronization & Replay Defense Across Host Restarts:** A freshly generated 256-bit cryptographically secure token (`SecRandomCopyBytes`) is written on every host startup. Any stale Droppy client sessions or replayed wire frames from prior runs fail handshake validation immediately.
3. **Cross-Droplet Collision Defense:** Droppy hosts multiple independent droplets within the single `iordv.Droppy` process. The session token prevents accidental cross-talk from other third-party droplets or plugins within Droppy that are not intended to communicate with AETHER.

### 2.3 The Authoritative Defense: Darwin Kernel Audit Tokens
Because the session token does not isolate against same-UID adversaries that specifically target AETHER, **authoritative peer authentication** is delegated to Darwin kernel audit tokens:
- When a client connects to `droplet.sock`, the Darwin kernel records the peer's credentials in its internal socket structure.
- The host retrieves this via `getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, ...)`.
- The peer cannot forge, intercept, or manipulate this audit token in userland.
- `SecCodeCopyGuestWithAttributes` and `SecCodeCheckValidity` enforce that the connecting process is signed with Apple Generic anchor, Bundle Identifier `iordv.Droppy`, and Developer ID Team `NARHG44L48`.
- Malicious processes running as the user fail closed at the kernel audit token verification layer, regardless of whether they have read the session token.

---

## 3. Real macOS Peer Authentication Audit (Audit Token & SecCode)

### 3.1 Kernel Audit Token Inspection
In `Sources/AetherCore/Transport/AetherPeerAuthentication.swift`:
```swift
var token = audit_token_t()
var len = socklen_t(MemoryLayout<audit_token_t>.size)
guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else {
    throw AetherTransportError.peerAuditTokenMissing
}
```
- Darwin's `LOCAL_PEERTOKEN` extracts an `audit_token_t` (8 × 32-bit integers = 32 bytes).
- Field `val[5]` holds the calling PID.
- Field `val[7]` holds the `pidversion` (mach port audit token pidversion), which specifically prevents PID reuse attacks (where a malicious process rapidly assumes an exited Droppy PID).

### 3.2 Security Framework Guest Resolution
The audit token data is converted directly into a `SecCode` object without relying on userland process tables:
```swift
let tokenData = withUnsafeBytes(of: &token) { Data($0) }
var secCode: SecCode?
let attributes = [kSecGuestAttributeAudit: tokenData as CFData] as CFDictionary
guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &secCode) == errSecSuccess,
      let secCode else {
    throw AetherTransportError.unsignedPeerRejected
}
```

### 3.3 Live Verification Against Genuine Running `Droppy.app`
To independently verify that the code signing requirement matches the genuine Droppy application installed on macOS:
1. **Live Process Check:** Verified running process on target hardware:
   - Path: `/Applications/Droppy.app/Contents/MacOS/Droppy`
   - PID: `87262`
   - User: `nilambarbehera`
2. **Designated Requirement Inspection:**
   `codesign -dvvv /Applications/Droppy.app` and `codesign -d -r- /Applications/Droppy.app` revealed:
   - Identifier: `iordv.Droppy`
   - Authority: `Developer ID Application: Jordy Spruit (NARHG44L48)`
   - Authority: `Developer ID Certification Authority`
   - Authority: `Apple Root CA`
   - TeamIdentifier: `NARHG44L48`
   - Hardened Runtime: Enabled (`flags=0x10000(runtime)`)
3. **Execution Verification with Live `SecCodeCheckValidity`:**
   Tested the compiled requirement string:
   `identifier "iordv.Droppy" and anchor apple generic and certificate leaf[subject.OU] = "NARHG44L48"`
   - Evaluated on running `Droppy.app` (PID 87262): **`errSecSuccess` (0 - MATCH / VALID)**.
   - Evaluated on current process / unprivileged processes (PID 72852): **`errSecCSReqFailed` (-67050 - REJECTED)**.
4. **Wire-Level Test Harness:**
   Added `@Test func realDroppyPeerValidatorRejectsUnauthorizedProcess()` in `AetherTransportTests.swift`. The test process connects to an `AetherIPCTransportServer` configured with `AetherDroppyPeerValidator(developmentAllowUnsigned: false)`. The test process connects over the Unix domain socket, the Darwin kernel delivers its real audit token (`com.apple.swift-frontend` / test runner), and the validator immediately rejects the peer and drops the socket.

---

## 4. Filesystem Security, Inode Verification & Race Resistance Audit

### 4.1 Parent Directory Validation & Hardening
In `AetherSocketEndpoint.validateAndCreateParentDirectory(_:)`:
- Parent directory (`~/Library/Application Support/Aether`) is inspected using `lstat` to prevent symlink traversal (`O_NOFOLLOW` semantics).
- Verified that `(st.st_mode & S_IFMT) == S_IFDIR`. If `S_IFLNK` is encountered, it throws `parentDirectoryIsSymlink`.
- Verified ownership matches `getuid()`.
- Mode is strictly set and enforced to `0700` (`rwx------`).

### 4.2 Non-Blocking Advisory Locking
In `AetherSocketEndpoint.bindAndListen()`:
- Lockfile `droplet.sock.lock` is opened with `O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600`.
- Verified regular file ownership via `fstat` before acquiring `flock(lock, LOCK_EX | LOCK_NB)`.
- If another host instance is running, `flock` returns `EWOULDBLOCK`, throwing `AetherTransportError.anotherHostInstanceRunning`.
- Stale socket check: only if exclusive lock is held and `lstat(socketPath, &st)` confirms `(st.st_mode & S_IFMT) == S_IFSOCK` is `unlink(socketPath)` permitted.

### 4.3 Inode & Device Verification on Cleanup (Hardening Implemented)
Prior to Phase 3E.1, cleanup routines called `unlink(tokenPath)` and `unlink(lockPath)` directly by path name. If a race occurred or an unexpected file was substituted at that path, calling `unlink` could remove an unverified file.

**Hardening Implemented:**
1. In `AetherSessionTokenManager`:
   - Added `boundInode: ino_t?` and `boundDev: dev_t?`.
   - On `generateAndPersistToken()`, `fstat(fd, &st)` records `st.st_ino` and `st.st_dev`.
   - In `cleanup()`, `lstat(tokenPath, &checkStat)` verifies `checkStat.st_ino == boundInode && checkStat.st_dev == boundDev` before unlinking. If the inode changed, `unlink` is refused.
   - Tested by `@Test func tokenManagerInodeVerificationPreventsSwappedUnlink()`.
2. In `AetherSocketEndpoint`:
   - Added `lockInode: ino_t = 0` and `lockDev: dev_t = 0`.
   - On lock acquisition, records `lockStat.st_ino` and `lockStat.st_dev`.
   - In `closeLock()`, verifies `lstat(lockPath, &check)` matches `lockInode` and `lockDev` before unlinking.

---

## 5. Socket I/O and Concurrency Audit

### 5.1 Strict Frame Bounds & DoS Prevention
- **Wire Frame Header:** 4-byte UInt32 big-endian payload length.
- **Maximum Payload:** 4,096 bytes JSON body.
- **Maximum Wire Frame:** 4,100 bytes (header + payload).
- **Decoder Internal Buffer:** Hard ceiling of 16,384 bytes. If an unauthenticated or misbehaving client streams excess data without valid frame boundaries, `AetherFrameDecoder.append()` throws `AetherProtocolError.decoderBufferExceeded` before memory allocation grows unbounded.
- **Pre-Allocation Length Verification:** Header length is checked immediately; if `payloadLength > 4096` or `== 0`, header is discarded and error is thrown without slicing or allocating body memory.

### 5.2 Swift Concurrency Cooperative Thread Pool Hygiene (Hardening Implemented)
Prior to Phase 3E.1, `AetherIPCClientSession.writeFrame` contained a synchronous retry loop with `Thread.sleep(forTimeInterval: 0.005)` on socket backpressure (`EAGAIN` / `EWOULDBLOCK`). In Swift concurrency, calling `Thread.sleep` blocks the underlying worker thread of the cooperative thread pool.

**Hardening Implemented:**
- Updated `writeFrame(_ data: Data) async throws`.
- Non-blocking socket write loop performs `Darwin.write` via `data.withUnsafeBytes`.
- On `EAGAIN` / `EWOULDBLOCK` / `EINTR`, yields cooperatively via `try await Task.sleep(for: .milliseconds(5))`.
- This ensures zero thread pool starvation, supports cooperative task cancellation, and eliminates test deadlocks.

### 5.3 Bounded Replay Cache
- **Capacity:** Strictly capped at 256 entries in `AetherReplayCache`.
- **Memory Footprint:** 256 × (16-byte UUID + 8-byte Date) < 16 KB.
- **Eviction Strategy:** Purges expired entries first; if still at 256, evicts oldest entry (FIFO / LRU ring).
- **Privacy:** Caches only `eventID: UUID` and `expiresAt: Date`. Secret OTP codes are never cached or accessible.
- **Broadcast Boundary Expiration Check:** In `AetherIPCTransportServer.broadcast(payload:)`, `payload.expiresAt > Date()` is re-verified at the immediate point of socket transmission.

---

## 6. Release Configuration Audit & Compiler Stripping Verification

### 6.1 `#if DEBUG` Bypass Stripping
In `Sources/AetherCore/Transport/AetherPeerAuthentication.swift`:
- `developmentAllowUnsigned` and `developmentMockIdentity` are enclosed strictly in `#if DEBUG`.
- The initializer is hardened so that in Release builds (`#else`), the `developmentAllowUnsigned` parameter does not exist on `AetherDroppyPeerValidator.init`, making it a compile-time impossibility to enable bypasses in production.

### 6.2 Binary Inspection Results
Compiled full release build (`swift build -c release`) and inspected object files using `nm` and `otool`:
- **Debug Object:** `nm .build/.../Debug/.../AetherPeerAuthentication.o | swift demangle` confirmed `developmentAllowUnsigned` property descriptor, getter, setter, and modify exist.
- **Release Object:** `nm .build/.../Release/.../AetherPeerAuthentication.o | swift demangle` confirmed:
  - Zero `developmentAllowUnsigned` property descriptors, getters, or setters.
  - Zero `developmentMockIdentity` symbols.
  - Only `expectedIdentifier` and `expectedTeamID` properties exist.
  - Disassembly of `authenticatePeer` in the release binary contains strictly the fail-closed Darwin audit token and `SecCodeCheckValidity` path.

---

## 7. Test Matrix & Verification Results

### 7.1 Test Suites Execution (`./scripts/test.sh`)
Ran the full test suite across the workspace:
- **`CodeCatchTests`:** 241 passed in 21 suites (all Apple Mail, Messages, IMAP, menu bar, and UI tests).
- **`CodeCatchCoreTests`:** 38 passed in 1 suite (including all 704 OTP test fixtures and regex edge cases).
- **`AetherCoreTests`:** 47 passed in 3 suites (including all protocol codecs, framing, transport lifecycle, peer authentication, inode protection, replay protection, and coordinator tests).
- **Total Workspace Tests:** **326 passed, 0 failed (100% pass rate).**

### 7.2 Release Universal Packaging (`./scripts/install.sh --build-only`)
- Built universal application package `.build-release/CodeCatch.app`.
- Successfully validated code signatures on helper binaries and frameworks:
  - `CodeCatch.app/Contents/Helpers/codecatch`
  - `Sparkle.framework` and helper XPC services (`Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`)
  - Main app bundle `CodeCatch.app`
- Build completed with exit code 0.

---

## 8. Final Gate Verdict

### **APPROVED FOR PHASE 3F**

All security properties, kernel audit token mechanics, filesystem race mitigations, inode cleanup verifications, Swift concurrency thread pool hygiene, and release compiler stripping have been independently verified and proven against both unit test harnesses and the live running `Droppy.app` process on target hardware.

> [!IMPORTANT]
> **Phase 3F is NOT started.** Phase 3E.1 is complete. Implementation of the Droppy droplet and DroppyKit bridge awaits explicit authorization.

