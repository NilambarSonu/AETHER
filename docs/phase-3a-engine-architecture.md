# AETHER Phase 3A — Headless Engine Boundary & Architecture Analysis

## 1. Executive Summary

This document evaluates three architectural models for integrating AETHER's email/message OTP detection engine with DroppyKit.

### Core Recommendation: Option A (In-Process Engine Architecture with Droplet Bridge)
- Package the reusable OTP detection, parsing, and provider coordination logic into an internal library module (**`AetherCore`**).
- Maintain the single, robust **AETHER host process** to manage system permissions (Full Disk Access, Keychain, Accessibility) and provider lifecycle.
- Integrate with DroppyKit via a lightweight, dedicated **`AetherDroplet`** running inside Droppy, communicating with the AETHER host over an authenticated local IPC channel.

Options B (Independent XPC Service) and C (LaunchAgent Background Daemon) are **explicitly rejected** due to prohibitive macOS TCC permission hurdles, multiplied memory footprints, and installation fragility.

---

## 2. Process Architecture Comparison

```
+---------------------------------------------------------------------------------------------------+
| OPTION A: In-Process Engine (Recommended)                                                         |
|                                                                                                   |
|  +-------------------------------------------------+        Authenticated         +------------+  |
|  |                 AETHER Host App                 |        Local IPC             | Droppy.app |  |
|  |  +-------------------------------------------+  | (UDS / LOCAL_PEERTOKEN)      |            |  |
|  |  |                AetherCore                 |  |                              | +--------+ |  |
|  |  |  * AetherSourceCoordinator                |  |<============================>| | Aether | |  |
|  |  |  * AetherIMAPSource / LocalWatcher (FSE)  |  |                              | | Droplet| |  |
|  |  |  * CodeExtractor / Sliding Deduplicator   |  |                              | +--------+ |  |
|  |  +-------------------------------------------+  |                              |   (HUD)    |  |
|  |  FDA: Held by AETHER app (Single Prompt)        |                              +------------+  |
|  |  Keychain: Native In-Process Access             |                                              |
|  |  Memory: 53.8 MB RSS | Idle CPU: 0.0%           |                                              |
|  +-------------------------------------------------+                                              |
+---------------------------------------------------------------------------------------------------+

+---------------------------------------------------------------------------------------------------+
| OPTION B: Independent XPC Service (Rejected)                                                      |
|                                                                                                   |
|  +-------------------+        Mach XPC         +-------------------+       IPC       +------------+
|  |  AETHER Host App  |<----------------------->|    aether.xpc     |<--------------->| Droppy.app |
|  |  (Menu Bar UI)    |                         | (Engine Core)     |                 |            |
|  +-------------------+                         +-------------------+                 +------------+
|  * Extreme TCC Defect: macOS Privacy UI cannot reliably grant Full Disk Access to an .xpc bundle. |
|  * Memory Bloat: Duplicated Swift concurrency runtime and Foundation heaps (~85 MB total).         |
+---------------------------------------------------------------------------------------------------+

+---------------------------------------------------------------------------------------------------+
| OPTION C: LaunchAgent Daemon (Rejected)                                                           |
|                                                                                                   |
|  +-------------------+        Socket           +-------------------+      Socket     +------------+
|  |  AETHER Host App  |<----------------------->|      aetherd      |<--------------->| Droppy.app |
|  |  (Preferences UI) |                         | (LaunchAgent)     |                 |            |
|  +-------------------+                         +-------------------+                 +------------+
|  * Complex Installation: launchctl bootstrap required; leaves orphaned plists on drag-to-trash.  |
|  * Dual TCC Prompts: Both aetherd and host app require independent Full Disk Access grants.       |
|  * Ad-Hoc / Dev Failure: Without Developer ID signing, cross-executable Keychain sharing breaks. |
+---------------------------------------------------------------------------------------------------+
```

---

## 3. Detailed Trade-off Matrix

| Evaluation Dimension | Option A: In-Process Engine (Recommended) | Option B: Independent XPC Service | Option C: LaunchAgent Daemon |
|---|---|---|---|
| **Full Disk Access (FDA)** | **Single grant** to main application. User sees standard macOS prompt once. | **Severe failure mode.** macOS TCC UI does not list `.xpc` services; requires manual file dragging. | **Dual grants required.** Both `aetherd` and `AETHER.app` must receive separate FDA authorizations. |
| **Keychain & Secrets** | **Native in-process access.** Zero cross-process entitlement requirements. | Requires shared Keychain Access Group (`$(TeamIdentifier).com.aether`). | Requires shared Keychain Access Group; breaks completely in unsigned/ad-hoc development builds. |
| **Developer ID Signing** | Works seamlessly in both Developer ID and unsigned ad-hoc builds. | Strict code signature requirement for `SecCodeCopyGuestWithAttributes`. | Requires code-signed binary for persistent launchd permission grants. |
| **IPC Attack Surface** | Minimal: Single authenticated point-to-point bridge between AETHER and Droplet. | Moderate: Host ↔ XPC, plus Droplet ↔ XPC. Two separate IPC listeners. | High: Daemon ↔ Host, plus Daemon ↔ Droplet. Multi-tenant socket complexity. |
| **Background Lifecycle** | Managed cleanly by macOS as an agent menu bar app (`LSUIElement = true`). | Subject to XPC lifetime idle exit; sudden termination drops active IMAP streams. | Managed by `launchd`. Requires crash throttling, socket activation, and sleep monitors. |
| **Memory Footprint (RSS)** | **53.8 MB** (single process). | ~85.0 MB (two processes with separate runtimes). | ~95.0 MB (three processes running concurrently). |
| **Idle CPU Utilization** | **0.0%** (proven in Phase 2B). | ~0.0% – 0.05% (extra XPC pinging). | ~0.0% – 0.10% (launchd monitoring). |
| **Install & Upgrade** | **Zero-touch.** Drag `.app` to Applications. Sparkle updates seamlessly. | Embedded in `.app`, but XPC caching can cause version mismatches. | Requires installer package (`.pkg`), `postinstall` launchctl commands, and custom uninstaller. |
| **DroppyKit Compatibility**| **Ideal.** Droplet is a lightweight UI client connected to the persistent host. | Complex. Droplet must locate and speak to an auxiliary XPC endpoint. | Complex. Droplet must coordinate with an independent background daemon. |

---

## 4. Why Alternatives Were Rejected

### 4.1 Rejection of Option B (Independent XPC Service)
1. **The macOS TCC Black Box:** On macOS 14 and 15, `kTCCServiceSystemPolicyAllFiles` (Full Disk Access) expects an application bundle (`.app`) or a top-level Mach-O binary. XPC services residing inside `Contents/XPCServices/` inherit sandboxing by default and do not cleanly appear in System Settings → Privacy & Security → Full Disk Access. Users attempting to grant permissions are presented with opaque errors or cannot drag the `.xpc` bundle into the settings table.
2. **State Drop on Idle Exit:** macOS XPC services are designed to be ephemeral (`exit(0)` on idle). Because AETHER maintains long-lived TCP sockets with IMAP servers (IDLE loop) and kernel FSEvent streams on disk directories, an XPC service would have to disable idle exits entirely, negating the sole architectural advantage of XPC.

### 4.2 Rejection of Option C (LaunchAgent Background Daemon)
1. **Uninstaller & Orphaned State:** AETHER is an open-source, user-centric utility. Users expect to uninstall it by dragging the application to the Trash. A LaunchAgent requires an entry in `~/Library/LaunchAgents/com.aether.daemon.plist` and a background binary in `~/Library/Application Support/Aether/`. If the user deletes the `.app`, `launchd` repeatedly attempts to spawn the missing binary, spamming system crash logs.
2. **Development Barrier:** Without an Apple Developer ID certificate with Keychain Access Group sharing entitlements, an independent daemon cannot access credentials saved by the GUI application in the macOS Keychain. This would prevent local open-source contributors from building and running the project without a paid Apple Developer account.

---

## 5. Architectural Recommendation

1. **Internal Architecture:**
   - Factor the core domain logic into an internal library target: `AetherCore`.
   - `AetherCore` contains: `AetherSourceCoordinator`, `AetherMailSource`, `AetherIMAPSource`, `LocalWatcher`, `FSEventWatcher`, `CodeExtractor`, and `IPCPeerValidator`.
   - `AetherHost` (the main `.app`) links `AetherCore` statically, holds the Full Disk Access grant, accesses Keychain, and manages the lifecycle.
2. **DroppyKit Integration Architecture:**
   - Create a dedicated Droppy droplet: `AetherDroplet` (`Aether.droplet`).
   - The droplet implements `DroppyKit.Droplet` and `DroppyKit.HUDPresenting`.
   - On activation, `AetherDroplet` establishes a local, mutual-authenticated Unix domain socket connection to `AetherHost`.
   - When `AetherHost` detects an OTP code, it transmits a signed, transient `AetherOTPEvent` payload to `AetherDroplet`.
   - `AetherDroplet` presents the code natively in the Droppy Notch / Island UI using `host.hud.present(...)`.
