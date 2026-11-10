# AETHER — Phase 2B Baseline & Security Verification Report

**Date:** November 10, 2026  
**Auditor:** Principal macOS Engineer, Swift Concurrency Architect & Application Security Engineer  
**Repository Root:** `/Users/nilambarbehera/Documents/Projects/Aether`  
**Target Hardware:** MacBook Air M5 (Apple Silicon, 32GB Unified Memory)  
**Target Operating System:** macOS 15.0+ (Sequoia)  
**Status:** Baseline Established — Independent Verification Complete

---

## 1. Test Suite & Corpus Verification

### 1.1 Test Counts and Execution Time
- **Total Tests Executed:** **265 tests**
- **Test Failures:** **0**
- **Regressions:** **0**
- **CodeCatchCoreTests Target:** **38 tests** across 1 suite (`IPCSecurityTests`) + top-level test functions  
  - Execution duration: **0.433 seconds**
  - Includes 7 IPC security tests (`IPCSecurityTests`)
  - Includes 2 Unicode & Zero-Width normalizer tests
  - Includes 704-sample corpus verification
- **CodeCatchTests Target:** **227 tests** across 18 test suites  
  - Execution duration: **2.659 seconds**
  - Includes 3 provider abstraction tests (`AetherMailSourceTests`)
  - Includes `MonitoringTests`, `AgentAccessTests`, `IconPrivacyTests`, `MailSignInTests`, etc.
- **Combined Test Execution Duration:** **3.092 seconds**

### 1.2 OTP Corpus Verification
- **Corpus File:** `Tests/CodeCatchCoreTests/code-samples.txt`
- **Total Samples:** **704 lines** (473 positive OTP extractions, 231 hard negative cases `NONE`)
- **Execution Test:** `CodeExtractorTests.extractsCode()`
- **Corpus Test Duration:** **0.432 seconds**
- **Pass Rate:** **100% (704/704 passing)**

---

## 2. Build & Signing Configuration

- **Swift Tools Version:** 6.0 (`// swift-tools-version: 6.0` in `Package.swift`)
- **Swift Language Mode:** Swift 5 compatibility mode (`swiftLanguageModes: [.v5]`)
- **Deployment Target:** macOS 15.0+ (`platforms: [.macOS(.v15)]`)
- **Dependencies:** Sparkle 2.6.0 (`github.com/sparkle-project/Sparkle`)
- **Debug Signing:** Ad-hoc signing (`codesign -s -`) applied by SPM on Apple Silicon
- **Release Signing (`scripts/install.sh`):** Configured for `Developer ID Application` with hardened runtime (`--options runtime --timestamp`) and notarization (`xcrun notarytool`)

---

## 3. Git Status & Repository State

```text
On branch main
Your branch is up to date with 'origin/main'.

Changes not staged for commit:
	modified:   Sources/CodeCatch/Agents/CLIServer.swift
	modified:   Sources/CodeCatch/Model/IncomingMessage.swift
	modified:   Sources/CodeCatch/Model/SourceHealth.swift
	modified:   Sources/CodeCatch/Model/SourceStatus.swift
	modified:   Sources/CodeCatch/System/Updater.swift
	modified:   Sources/CodeCatchCLI/main.swift
	modified:   Sources/CodeCatchCore/CodeExtractor.swift
	modified:   Tests/CodeCatchCoreTests/CodeExtractorTests.swift

Untracked files:
	Sources/CodeCatch/Mail/AetherMailSource.swift
	Sources/CodeCatchCore/IPCPeerValidator.swift
	Tests/CodeCatchCoreTests/IPCSecurityTests.swift
	Tests/CodeCatchTests/AetherMailSourceTests.swift
```

---

## 4. Component Inspection Summary

| File / Component | Role in Architecture | Verification Findings |
| :--- | :--- | :--- |
| `Sources/CodeCatchCore/IPCPeerValidator.swift` | Mutual code signature & Team ID validator | Enforces strict matching in production (`peerTeam == localTeam`); fail-closed policy. Debug bypass requires `#if DEBUG` and explicit flag. |
| `Sources/CodeCatchCLI/main.swift` | Command-line client | Verifies host via `IPCPeerValidator.validate(peer:role: .server)`. Unsigned fallback removed. |
| `Sources/CodeCatch/Agents/CLIServer.swift` | Host IPC server | Verifies client via `IPCPeerValidator.validate(peer:role: .client)`. Unsigned bypass removed. |
| `Sources/CodeCatch/Mail/AetherMailSource.swift` | Async provider abstraction protocol | Defines `AetherMailSource`, `AetherSourceOutput`, and prototype `FixtureMailSource` using `AsyncStream`. Thread-safe, non-deadlocking. |
| `Sources/CodeCatch/Mail/IMAPConnection.swift` | TLS IMAP actor | Clean TLS over `NWConnection`, IDLE push support, 9m watchdog renewal, exponential backoff (5s–120s). |
| `Sources/CodeCatch/Mail/MailWatcher.swift` | IMAP mailbox watcher loop | Manages connection loop, history backfill (60 newest), UID/UIDVALIDITY tracking. |
| `Sources/CodeCatch/Mail/GmailAPI.swift` | Gmail REST API client | Ephemeral `URLSession`, history ID cursor sync, raw RFC 822 MIME retrieval. |
| `Sources/CodeCatch/Mail/APIWatcher.swift` | Polling watcher for REST APIs | Polls Gmail/Outlook every 10 seconds. |
| `Sources/CodeCatch/Mail/OutlookAPI.swift` | Microsoft Graph API client | OData `$filter` queries, pagination host validation (`graph.microsoft.com`), token rotation. |
| `Sources/CodeCatch/Messages/MessagesStore.swift` | SQLite reader for `chat.db` | Queries `~/Library/Messages/chat.db`, decodes `attributedBody` via `TypedStream`. Requires Full Disk Access. |
| `Sources/CodeCatch/Model/LocalWatcher.swift` | Local store polling timer | Currently polls SQLite once every 1.0 second via `DispatchSourceTimer`. |
| `Sources/CodeCatch/System/IconStore.swift` | Favicon proxy cache | Fetches via Google / DuckDuckGo proxies when enabled. Leaks sender domains. |
| `Sources/CodeCatch/Model/Prefs.swift` | User preferences & defaults | `serviceIcons` currently registered as `true` in `Prefs.register`. |

---

## 5. Performance Baseline Summary (Reported & Verified)

- **Idle Memory (Debug):** `69,840 KB` (~68.2 MB RSS)
- **Idle CPU:** **0.1%** average steady-state idle
- **Local Watcher Polling Interval:** 1.0 second (`DispatchSourceTimer`)
- **IMAP IDLE Overhead:** 0.0% CPU between packets; 540s renewal watchdog
- **Gmail/Outlook Polling Interval:** 10.0 seconds
