# AETHER Phase 3A — Repository & Baseline Audit

## 1. Executive Summary

This audit establishes the empirical baseline of the AETHER repository prior to undertaking any Phase 3 architectural separation or DroppyKit integration design. In accordance with Phase 3A non-negotiable rules, all findings are derived from direct inspection of the live filesystem, executable binaries, test suites, and system permissions without modifying source files.

---

## 2. Test Suite & Verification Results

Execution of `./scripts/test.sh` on macOS 15.0+ (Darwin 24.x, Apple Silicon M5):

| Test Target | Suite Count | Test Count | Pass Count | Failures | Duration | Status |
|---|---|---|---|---|---|---|
| `CodeCatchCoreTests` | 1 | 38 | 38 | 0 | 0.412s | `VERIFIED` |
| `CodeCatchTests` | 20 | 241 | 241 | 0 | 2.368s | `VERIFIED` |
| **Total** | **21** | **279** | **279** | **0** | **2.780s** | `VERIFIED` |

### Corpus Validation:
- **704 real-world OTP test cases** executed via `CodeExtractorTests.swift`: 100% pass rate in 0.412s (average 0.585 ms per case). Zero regressions.

---

## 3. Project Structure & Executable Targets

Defined in `Package.swift`:

| Target Name | Target Type | Dependencies | Linker Settings / Notes |
|---|---|---|---|
| `CodeCatchCore` | Swift Target | None | Shared business logic, extraction algorithms, IPC validator |
| `CodeCatch` | Executable Target | `CodeCatchCore`, `Sparkle` | Links `libsqlite3`, `@rpath` to `@executable_path/../Frameworks` |
| `CodeCatchCLI` | Executable Target | `CodeCatchCore` | Embedded helper binary (`Contents/Helpers/codecatch`) |
| `CodeCatchCoreTests` | Test Target | `CodeCatchCore` | Excludes raw test corpus text fixtures |
| `CodeCatchTests` | Test Target | `CodeCatch` | Comprehensive integration and unit test suite |

---

## 4. Packaging, Process Boundaries & Entitlements

Inspection of `scripts/install.sh`, `Resources/Info.plist`, and `codesign`:

1. **Bundle Identity & Layout:**
   - Main Bundle: `com.uros.codecatch` (`CodeCatch.app`)
   - Main Executable: `Contents/MacOS/CodeCatch`
   - CLI Helper Executable: `Contents/Helpers/codecatch` (signed with identifier `com.uros.codecatch.cli`)
   - Frameworks: `Contents/Frameworks/Sparkle.framework`
   - Embedded XPC Services: `Sparkle.framework/.../Installer.xpc` and `Downloader.xpc`
2. **Entitlements Audit:**
   - **No `.entitlements` file exists in the repository.**
   - The application does **not** enable the macOS App Sandbox (`com.apple.security.app-sandbox` is absent).
   - Hardened Runtime is enabled in production (`codesign --options runtime`).
3. **Process Boundaries:**
   - `CodeCatch` runs as a single user-space GUI menu bar process (`LSUIElement = true`).
   - `CLIServer` hosts a Unix Domain Socket at `~/Library/Application Support/CodeCatch/CodeCatch.sock`.
   - `CodeCatchCLI` connects over this socket and validates mutual identity using kernel audit tokens (`LOCAL_PEERTOKEN`) via `IPCPeerValidator`.

---

## 5. Security & Permission Dependencies

| Dependency | Purpose | macOS Enforcement Mechanism | Impact on Architectural Separation |
|---|---|---|---|
| **Full Disk Access (FDA)** | Reading `chat.db` (Messages) and `Envelope Index` (Apple Mail) | macOS TCC (`kTCCServiceSystemPolicyAllFiles`) | **FDA is granted per executable bundle/binary identity.** If engine runs in a separate daemon or XPC service, that process must obtain its own FDA grant. |
| **macOS Keychain** | Storing IMAP passwords, OAuth refresh tokens, Mac Unlock secrets | `Security.framework` (`kSecClassGenericPassword`) | Keychain items scoped to code-signing identity and access groups. A separated process must share the same Team ID or access group. |
| **File System Events (FSEvents)** | Real-time monitoring of `~/Library/Messages` and `~/Library/Mail/V10` | `CoreServices.FSEvents` | Requires read permissions on parent directories, backed by FDA. |
| **Accessibility (AX)** | Optional auto-typing of verification codes (`KeyTyper.swift`) | macOS TCC (`kTCCServiceAccessibility`) | Bound to the presenting application process. |

---

## 6. Audit of Phase 2B Deliverables

All eight Phase 2B documentation files were independently verified in `docs/`:
1. `docs/phase-2b-baseline.md` (`VERIFIED`)
2. `docs/phase-2b-ipc-verification.md` (`VERIFIED`)
3. `docs/phase-2b-imap-adapter.md` (`VERIFIED`)
4. `docs/phase-2b-source-lifecycle.md` (`VERIFIED`)
5. `docs/phase-2b-fsevents.md` (`VERIFIED`)
6. `docs/phase-2b-icon-privacy.md` (`VERIFIED`)
7. `docs/phase-2b-performance-report.md` (`VERIFIED`)
8. `docs/phase-2b-final-review.md` (`VERIFIED`)

Baseline backup verified readable and intact at:
`/Users/nilambarbehera/Documents/Projects/Aether_Backups/Aether_baseline_20261109`.
