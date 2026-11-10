# NOTICE & ATTRIBUTION

## 1. Project Origin & License Notice

**AETHER** evolved from and incorporates software from **CodeCatch**, originally authored by Uros (`ugzv/CodeCatch`).

This software is licensed under the **GNU General Public License, Version 3.0 (GPLv3)**.  
A complete copy of the license is provided in the [`LICENSE`](LICENSE) file in the root directory of this repository.

In accordance with Section 5 of the GNU General Public License v3:
- Modified files carry notices identifying that they have been modified.
- The date of initial modification under AETHER is November 2026.
- The work as a whole is licensed and distributed under GNU GPLv3.

---

## 2. Copyright Holders & Attribution

### Upstream Software (CodeCatch)
- **Copyright (C) 2024–2026 Uros / CodeCatch contributors.**
- Upstream repository: [https://github.com/ugzv/CodeCatch](https://github.com/ugzv/CodeCatch)
- Original components include the verification code extractor (`CodeExtractor`), local database monitoring foundations, Touch ID / Keychain vault infrastructure, and menu bar components.

### AETHER Evolution & Contributions
- **Copyright (C) 2026 Nilambar Behera.**
- Original contributions authored for AETHER include:
  1. **AetherCore Architecture:** In-process headless verification engine extraction and coordinator (`Sources/AetherCore/`).
  2. **IPC Protocol & Frame Codec:** Length-prefixed binary wire frame encoder/decoder (`AetherFrameCodec`, `AetherFrameDecoder`) and versioned OTP payload/acknowledgment contracts (`AetherOTPPayload`, `AetherOTPAcknowledgment`).
  3. **Secure IPC Transport:** Host and client Unix Domain Socket transport engine with POSIX DAC security, filesystem race prevention, advisory locking (`droplet.sock.lock`), and inode tracking (`AetherIPCTransportServer`, `AetherIPCClientTransport`, `AetherSocketEndpoint`).
  4. **Darwin Kernel Peer Authentication:** Mutual peer verification via Darwin kernel audit tokens (`LOCAL_PEERTOKEN`) and Security framework (`SecCodeCopyGuestWithAttributes`, `SecCodeCheckValidity`) validating `iordv.Droppy` (Team `NARHG44L48`) and `com.uros.codecatch`.
  5. **DroppyKit Bridge & Droplet:** Complete droplet implementation (`Droplet/Aether/Sources/AetherDroplet.swift`), resilient ABI alignment (`-enable-library-evolution`), manifest, and bundle packaging pipeline (`scripts/build-droplet.sh`).
  6. **Event-Driven Provider Monitoring:** Modern FSEvents-based file monitoring (`FSEventWatcher`), asynchronous mail sources (`AetherMailSource`, `AetherIMAPSource`), and lifecycle coordinator (`AetherSourceCoordinator`).

---

## 3. Third-Party Licenses & Dependencies

### DroppyKit SDK
- **Copyright (c) 2026 Jordy Spruit. All rights reserved.**
- Repository: [https://gitlab.com/droppyformac1/droppykit](https://gitlab.com/droppyformac1/droppykit)
- Licensed under the DroppyKit SDK License 1.0. Droplets built for Droppy link against the DroppyKit SDK framework provided at runtime by the Droppy application.

### Sparkle Project
- **Copyright (c) Andy Matuschak and Sparkle project contributors.**
- Licensed under the MIT License.
