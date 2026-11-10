# AETHER

[![CI](https://github.com/NilambarSonu/AETHER/actions/workflows/macos-build.yml/badge.svg)](https://github.com/NilambarSonu/AETHER/actions/workflows/macos-build.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform: macOS 15.0+](https://img.shields.io/badge/macOS-15.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/Architecture-Apple%20Silicon-orange)](https://support.apple.com/en-us/HT211814)

**AETHER** is a high-performance, privacy-first verification code (OTP) detection engine and Dynamic Island / notch notification bridge for macOS. Evolved from [CodeCatch](https://github.com/ugzv/CodeCatch), AETHER extracts ephemeral verification codes in real time from email and messaging channels and projects them directly into your macOS notch or Dynamic Island HUD via [Droppy](https://getdroppy.app) with seamless one-click clipboard copying.

---

## 1. Project Purpose & Design Principles

Traditional verification workflows require leaving your active window, opening a mail or messaging client, searching for the message, manually selecting the code, and returning to the target site. AETHER eliminates this friction while separating host data access from UI presentation:

- **Zero-Secret Persistence:** Ephemeral OTP codes are processed in memory and never written to disk, databases, or log files.
- **Mutual Kernel Peer Authentication:** Cross-process communication between the AETHER engine and Droppy enforces kernel-level audit tokens (`LOCAL_PEERTOKEN`) and cryptographic code signatures (`SecCodeCheckValidity`).
- **Host/Droplet Privilege Separation (Option A):** All Full Disk Access (FDA), mailbox reads, OAuth credentials, and Keychain secrets remain strictly inside the AETHER host process. The UI presentation plug-in (`AETHER.droplet`) is dynamically loaded (`dlopen`) into the `Droppy.app` process (`iordv.Droppy`) and receives only ephemeral OTP event payloads over the local Unix Domain Socket. Note that `AETHER.droplet` shares Droppy's process address space and entitlements and is **not** an independent macOS App Sandbox.
- **Modern Swift Concurrency:** Fully asynchronous, actor-isolated architecture without blocking thread pools or busy-wait polling.

---

## 2. Current Implementation Status

AETHER is developed across structured engineering phases:

- [x] **Phase 1.1–1.2:** IPC Security Verification & Peer Validator Foundation
- [x] **Phase 2A–2B:** Provider Modernization, FSEvents Event-Driven Engine & Icon Privacy
- [x] **Phase 3A–3B:** Headless Engine Architecture & `AetherCore` Module Extraction
- [x] **Phase 3C:** Versioned Length-Prefixed Binary Frame Codec
- [x] **Phase 3D–3E.1:** Secure Host IPC Transport, Kernel Audit Tokens & Inode Hardening
- [x] **Phase 3F:** Droppy Client Transport, Resilient ABI Alignment & First Local HUD Integration
- [ ] **Phase 4 (Upcoming):** Live Provider Pipeline Integration (Connecting live Apple Mail, Messages, and IMAP streams to Droppy HUD)

> [!NOTE]
> **Implementation Scope:** The cross-process IPC transport, mutual kernel code validation, and Droppy HUD card presentation have been verified end-to-end using synthetic OTP events. Direct background monitoring from live mailboxes into the Droppy HUD is scheduled for Phase 4.

---

## 3. Architecture & Subsystem Relationship

AETHER adopts **Option A (In-Process Engine + Separate Droppy UI Client)**:

```
+-----------------------------------------------------------------------------------+
|                              macOS 15.0+ (Darwin 24)                              |
+-----------------------------------------------------------------------------------+
|                                                                                   |
|  [ AETHER Host Process ] (com.uros.codecatch)                                     |
|  ├── Mail & Messages Monitoring (Apple Mail SQLite, Messages DB, IMAP IDLE)       |
|  ├── CodeCatchCore: Regex & Deterministic Code Extraction (704 test fixtures)     |
|  ├── AetherCore: Headless Engine & Source Coordinator                             |
|  └── AetherIPCTransportServer (Actor)                                             |
|        │                                                                          |
|        │  POSIX Unix Domain Socket: ~/Library/Application Support/Aether/droplet.sock
|        │  Security: 0700 dir, 0600 token, advisory lock, inode verification       |
|        │  Authentication: Darwin audit token (LOCAL_PEERTOKEN) -> SecCode check   |
|        │  Wire Protocol: Bounded length-prefixed binary frames (max 4,100 bytes)   |
|        ▼                                                                          |
|  [ Droppy Host Application ] (iordv.Droppy, Team ID: NARHG44L48)                  |
|  ├── Droplet Host & Notch HUD Management                                          |
|  └── Loads AETHER.droplet Bundle                                                  |
|        ├── AETHERPrincipal & AetherDroplet (Swift 6 resilient ABI, HUDPresenting)    |
|        ├── AetherIPCClientTransport (Actor)                                       |
|        │     └── Validates Server Audit Token (identifier "com.uros.codecatch")   |
|        └── On Event -> Presents OTP HUD Card & emits .displayed ACK               |
|              └── On "Copy Code" Button -> host.workspace.copyToPasteboard(code)   |
|                    └── Emits .copied ACK to Host Transport                        |
|                                                                                   |
+-----------------------------------------------------------------------------------+
```

---

## 4. IPC Authentication & Security Model

Communication between the host and droplet occurs over a local Unix Domain Socket (UDS) protected by multiple defense layers:

1. **Kernel Audit Tokens (`LOCAL_PEERTOKEN`):** Both sides query Darwin kernel credentials using `getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN)`. Userland process forgery is prevented by the kernel.
2. **Security Framework Code Signing (Process-Level Identity):**
   - **Host verifies Droppy:** Enforces `anchor apple generic and identifier "iordv.Droppy" and certificate leaf[subject.OU] = "NARHG44L48"`.
   - **Droplet verifies Host:** Enforces `anchor apple generic and identifier "com.uros.codecatch"`.
   - **Process Trust Boundary:** Darwin peer authentication identifies the **`Droppy.app` process** as a whole (`iordv.Droppy`), not individual droplets inside it. Because all enabled Droppy droplets share `Droppy.app`'s address space and security context (`Droplet` does not run in an independent macOS App Sandbox), any co-loaded droplet or plugin inside `Droppy.app` shares the same runtime permissions.
3. **POSIX DAC & Filesystem Race Resistance:**
   - Socket directory `~/Library/Application Support/Aether` is enforced to mode `0700` owned by `getuid()`.
   - Ephemeral 256-bit session token is regenerated on every launch, stored with mode `0600`, and validated against inode/device swaps before unlinking.
   - **POSIX Scope Note:** Mode `0700`/`0600` POSIX permissions prevent access from other macOS user accounts (different UIDs), **not** from other processes running under the same user UID (which the droplet client itself relies on to read `session.token`). Same-UID protection relies primarily on Darwin kernel audit token validation above.
   - Advisory locking (`flock`) on `droplet.sock.lock` prevents dual-instance conflicts.
4. **Bounded Framing & DoS Resistance:**
   - Wire frames are prefixed with a 4-byte big-endian length header strictly capped at 4,096 bytes (4,100 bytes wire limit).
   - The frame decoder enforces a hard memory cap of 16,384 bytes, dropping misbehaving streams before memory starvation.

---

## 5. Synthetic OTP Demonstration

Phase 3F verified end-to-end HUD presentation and pasteboard interaction:

```
$ .build/out/Products/Debug/CodeCatch --probe-droplet-otp
==> Starting Aether IPC Transport Server...
==> Aether server listening at: ~/Library/Application Support/Aether/droplet.sock
==> Waiting for Droppy droplet client connection...
[AetherIPCServer] Accepted connection from peer (PID 77441)
[AetherHostPeerValidator] Validated peer code signature: iordv.Droppy (Team NARHG44L48)
==> Droppy client connected and session adopted successfully!
==> Broadcasting synthetic OTP payload (service: GitHub, code: 482731)...
==> Broadcast result: delivered(clientCount: 1)
==> Received acknowledgment: status=displayed (eventID: ...)
[User clicked HUD "Copy" button in Droppy notch card]
==> Received acknowledgment: status=copied (eventID: ...)
==> Droppy HUD Copy Action verified! Test PASSED.
```

Clipboard verification:
```
$ pbpaste
482731
```

---

## 6. System Requirements & Hardware Architecture

- **Operating System:** macOS 15.0 (Sequoia) or later
- **Architecture:** Apple Silicon (`arm64` / Apple M-series)
- **Toolchain:**
  - `AetherCore` and `CodeCatchCore` build cleanly with Apple Command Line Tools / Swift 6.x toolchain.
  - The full host application (`CodeCatch`) uses macOS 26 SDK SwiftUI APIs (`#available(macOS 26, *)`) in `CodeRow.swift`, and official `DroppyKit` (`SwiftUIMacros`) + `droppykit build`/`run` require **Xcode 26+ SDK** (provided automatically on GitHub-hosted `macos-15` CI runners).
- **Optional Companion:** [Droppy](https://getdroppy.app) (`15.3+`, DroppyKit API `1.12.0+`, including Droppy Playground and Droppy 16.x) for Dynamic Island / notch HUD card presentation.

---

## 7. Repository Layout

```
Aether/
├── Droplet/                       # Official DroppyKit SwiftPM droplet package
│   ├── Package.swift              # Dynamic AETHER library + DroppyKit SDK dependency (>= 1.12.0)
│   ├── droplet.json               # Official Droplet manifest (HUD & clipboard capabilities)
│   ├── Assets/Creator.png         # Community creator mark (512x512 square PNG)
│   ├── LICENSE & NOTICE.md        # GPLv3 license & upstream attribution
│   └── Sources/
│       ├── AETHER/AetherDroplet.swift       # AETHERPrincipal, HUDPresenting & OTP HUD view
│       ├── AETHERHarness/AETHERHarness.swift# Official DropletHarnessApp target
│       └── AetherIPC/                       # Synchronized protocol/codec/transport sources
├── Sources/
│   ├── AetherCore/                # Extracted headless verification engine
│   │   ├── Codec/                 # Length-prefixed frame encoder & decoder
│   │   ├── Coordinator/           # Provider lifecycle management
│   │   ├── Models/                # Engine message and status types
│   │   ├── Protocol/              # Ephemeral OTP payload & ACK contracts
│   │   ├── Sources/               # Asynchronous mail source protocols
│   │   └── Transport/             # Secure UDS server, client & peer validators
│   ├── CodeCatchCore/             # Deterministic regex code extraction engine
│   ├── CodeCatch/                 # Host application & macOS system adapters
│   └── CodeCatchCLI/              # Local developer CLI tool
├── Tests/
│   ├── AetherCoreTests/           # Client/server transport, codec & security tests
│   ├── CodeCatchCoreTests/        # 704 OTP regex fixture test suites
│   └── CodeCatchTests/            # macOS integration & provider test suites
├── docs/                          # Architectural reports, security audits & README-TESTING.md
├── scripts/
│   ├── build-droplet.sh           # Official DroppyKit build/validate & safe staged installer
│   ├── test.sh                    # Full workspace test suite runner
│   └── install.sh                 # Production packaging tool
├── NOTICE.md                      # Upstream attribution & modification history
└── LICENSE                        # GNU General Public License v3.0
```

---

## 8. Build & Test Instructions

### Building Locally or via GitHub Actions

GitHub Actions builds the entire workspace — including the official universal `AETHER.droplet` artifact (`AETHER-Droplet.zip`) and `DroppyKitHarness` report — without requiring Xcode installed on your personal machine:

```bash
# Resolve dependencies
swift package resolve

# Build AetherCore engine (CLT compatible)
swift build --target AetherCore

# Build host application in Release (requires macOS 26 SDK / Xcode 26+)
swift build -c release --scratch-path .build-release
```

### Building & Installing the AETHER Droplet

`scripts/build-droplet.sh` wraps the official [DroppyKit](https://gitlab.com/droppyformac1/droppykit) CLI (`droppykit build` and `droppykit validate`) with staged atomic replacement and rollback:

```bash
# Build universal (arm64 + x86_64) AETHER.droplet (requires Xcode 26+ & official DroppyKit)
DROPPYKIT_DIR=/path/to/droppykit ./scripts/build-droplet.sh

# Safely stage and install a built bundle or CI artifact (preserves .AETHER.droplet.previous; never disables approvals)
./scripts/build-droplet.sh --install --bundle /path/to/AETHER.droplet
```

See [`docs/README-TESTING.md`](docs/README-TESTING.md) for Droppy Playground and Droppy approval/testing steps.

### Running the Test Suite

Run the full workspace test suite:

```bash
./scripts/test.sh --force-resolved-versions
```

Verify the 704 OTP test fixtures individually:

```bash
swift test --filter CodeExtractorTests
```

---

## 9. Known Limitations

1. **Phase 3F Milestone:** Live background provider monitoring (Apple Mail SQLite, Messages DB, and IMAP) currently flows into the existing host menu bar UI; routing live provider events into the Droppy IPC transport is the primary objective of Phase 4.
2. **Shared Droppy Process Trust Boundary:** `AETHER.droplet` is dynamically loaded (`dlopen`) into `Droppy.app` and shares its address space and entitlements with Droppy and any other installed droplets. It is not an isolated macOS App Sandbox. IPC peer authentication validates the `Droppy.app` process (`iordv.Droppy`), not an individual droplet within it.
3. **CI vs. Live Droppy.app Runtime:** GitHub Actions compiles `AETHER.droplet` against the genuine pinned official DroppyKit SDK (`v1.23.0`), validates linkage/manifest/ABI compliance (`droppykit validate`), and runs the headless `DroppyKitHarness` (`droppykit run -- --shots ... --report ...`). Live UDS/HUD verification inside `Droppy.app` (`15.3+` / `16.x`, DroppyKit API `1.12.0+`) requires running AETHER and Droppy together on macOS hardware.
4. **Droppy Companion Requirement:** Notch and Dynamic Island visual cards require the [Droppy](https://getdroppy.app) application. When Droppy is not running, the AETHER engine operates in headless mode without error.
5. **Distribution Signing:** Official `droppykit build` CI bundles are unsigned (compatible with Droppy Playground and Droppy's explicit approval flow); public Store/Sparkle redistribution requires Developer ID signing and Apple notarization.

---

## 10. Security Disclosure

Because AETHER processes sensitive verification credentials, security vulnerabilities are treated with highest urgency. Please report vulnerabilities privately rather than in public GitHub issues:

1. Open the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Include reproducible steps, macOS version, and system logs with all real credentials redacted.

Refer to [`SECURITY.md`](SECURITY.md) for complete details.

---

## 11. License & Upstream Attribution

AETHER is licensed under the **GNU General Public License v3.0 (GPLv3)**.  
See [`LICENSE`](LICENSE) for the full license text.

AETHER is an evolution of **CodeCatch**, Copyright (C) 2024–2026 Uros and CodeCatch contributors.  
Original AETHER modifications, `AetherCore`, IPC transport, and Droplet integrations are Copyright (C) 2026 Nilambar Behera.

For complete upstream attribution and modification records, see [`NOTICE.md`](NOTICE.md).
