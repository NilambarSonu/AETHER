# AETHER — Phase 3F.2: Independent Release-Candidate Audit & GitHub CI Preflight

**Audit Date:** 2026-11-10

**Repository:** `/Users/nilambarbehera/Documents/Projects/Aether`

**Remote (`origin`):** `https://github.com/NilambarSonu/AETHER.git`

**Upstream Reference (`upstream`):** `https://github.com/ugzv/CodeCatch.git`

**Official DroppyKit SDK Verified:** `https://gitlab.com/droppyformac1/droppykit.git` — tag `v1.23.0` (`11e4869898bf13991120e26af347b9007521623b`, ABI `1`)

**Previous Phase Report Audited:** [`docs/droppykit-official-compliance-report.md`](droppykit-official-compliance-report.md)

---

## Executive Verdict

**VERDICT: `APPROVED FOR AUTHORIZED CI EXECUTION`**

All repository, manifest, API compatibility, source-parity, installer security, ZIP distribution structure, and GitHub Actions workflow preflight checks pass independently. Four preflight gaps uncovered during this audit (untracked `Droplet/Package.resolved`, relative/target symlink validation in `scripts/build-droplet.sh`, Xcode `>= 26` hard gate + `Package.resolved` pin verification in CI, and missing ZIP round-trip staging tests) were remediated cleanly and verified before issuing this verdict.

> **Important Scope Condition:** Local execution of `droppykit build`, binary `api-ledger.sh check`, and `droppykit run -- --shots` remains unexecuted on this workstation because only Apple Command Line Tools (`Swift 6.4.2`, no `/Applications/Xcode*.app`) are installed locally and Droppy Playground is not installed. Genuine universal binary build validation and headless harness execution will run for the first time on GitHub Actions (`macos-15`, Xcode 26+) once the user authorizes a commit and push, followed by manual runtime verification of `AETHER-Droplet.zip` inside Droppy Playground / `/Applications/Droppy.app`.

---

## 1. Baseline Git State

- **Current branch:** `main`
- **Local `HEAD` commit:** `0fc474a3940218ec1ee8679b81eb8f8a2bfb06c0` (`ci: select Xcode 26+ SDK on macOS runner for SwiftUI Liquid Glass symbols`)
- **`origin/main` commit:** `0fc474a3940218ec1ee8679b81eb8f8a2bfb06c0` (divergence `origin/main...HEAD`: `0 0` — aligned, zero unpushed commits)
- **`upstream/main` commit:** `c37d836` (`chore(release): v2.0.339`)
- **Original Phase 0 backup (`/Users/nilambarbehera/Documents/Projects/Aether_Backups/Aether_baseline_20261109`):** Verified intact (`c37d8361e0fbf8dd03145035b38fc27a53e980f0`, untouched)
- **Working tree state (`git status --short --branch` prior to writing this report):**
  - **Modified (`M`):** `.github/workflows/macos-build.yml`, `ARCHITECTURE.md`, `NOTICE.md`, `README.md`, `SECURITY.md`, `scripts/build-droplet.sh`
  - **Deleted (`D`):** `Droplet/Aether/Info.plist`, `Droplet/Aether/Sources/AetherDroplet.swift`, `Droplet/Aether/droplet.json`, `Droplet/DroppyKitInterface.swift`
  - **Untracked (`??`):** `Droplet/.gitignore`, `Droplet/Assets/Creator.png`, `Droplet/CHANGELOG.md`, `Droplet/LICENSE`, `Droplet/NOTICE.md`, `Droplet/Package.resolved`, `Droplet/Package.swift`, `Droplet/README.md`, `Droplet/Sources/`, `Droplet/droplet.json`, `Tests/AetherCoreTests/AetherReleaseHardeningTests.swift`, `docs/README-TESTING.md`, `docs/droppykit-official-compliance-report.md`, `docs/phase-3f.1-post-release-hardening.md`, and this report `docs/phase-3f2-independent-release-audit.md`
- **Staged changes:** None (all working-tree edits remain unstaged; no commits, pushes, rebases, resets, or cleans performed)
- **Whitespace check (`git diff --check`):** Clean (exit `0`, zero diagnostics)

---

## 2. Official DroppyKit Integration & Resolved Package Revision

- **Authoritative local SDK checkout (`/Users/nilambarbehera/Documents/Projects/droppykit`):**
  - Remote `origin`: `https://gitlab.com/droppyformac1/droppykit.git`
  - Exact tag: `v1.23.0` (`11e4869898bf13991120e26af347b9007521623b`)
  - CLI (`droppykit version` from `Droplet/`):
    ```text
    DroppyKit 1.23.0 (ABI 1)
      checkout: /Users/nilambarbehera/Documents/Projects/droppykit (v1.23.0 on main)
      swift:    swift-driver version: 1.168.6 Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1) (build engine: swiftbuild)
      droplet:  /Users/nilambarbehera/Documents/Projects/Aether/Droplet pins DroppyKit 1.23.0 (droppykit update moves it)
    ```
- **Host root `Package.resolved`:** Pins `sparkle` `2.10.0` (`eef1a539a373c1f1a320624b11e4869898bf13991120e26af347b9007521623b`) — unmodified.
- **Droplet `Droplet/Package.swift`:**
  - Product: `.library(name: "AETHER", type: .dynamic, targets: ["AETHER"])`
  - Dependency: `.package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.12.0")`
  - Targets: `AetherIPC` (`.v6`), `AETHER` (depends on `AetherIPC` + `.product(name: "DroppyKit", package: "droppykit")`, `.v6`), executable `AETHERHarness` (depends on `AETHER` + `.product(name: "DroppyKitHarness", package: "droppykit")`, `.v6`)
- **Droplet `Droplet/Package.resolved` (generated & verified during this audit):**
  - Pins `droppykit` from `https://gitlab.com/droppyformac1/droppykit.git` to `version: "1.23.0"`, `revision: "11e4869898bf13991120e26af347b9007521623b"`.
  - Passes both `droppykit lint --no-binary --strict` and `droppykit lint --submit --no-binary --strict` (`✓ no findings`), and prevents drift if upstream releases newer `1.x` versions before CI executes.
- **No unofficial stubs or hidden fallbacks:**
  - Repository-wide search (`rg -n -i "DroppyKit|droplet|stub|skeleton|SIMULATE_CLEAN_CI|askBeforeRunning"`) confirmed `DroppyKitInterface.swift`, `Droplet/Aether/Info.plist`, and `STUB_SKELETON_COMPILE_ONLY` are completely gone from source targets, `scripts/`, and `.github/`.
  - `scripts/build-droplet.sh --validate-only` and `.github/workflows/macos-build.yml` explicitly reject bundled `Contents/Frameworks/DroppyKit.framework` or `libDroppyKit.dylib` copies and `9DroppyKit.*vau` unsafe non-resilient symbol imports.

---

## 3. API & Version Compatibility Audit

Every DroppyKit API, protocol, UI token, and manifest field used by AETHER was checked directly against `/Users/nilambarbehera/Documents/Projects/droppykit/Scripts/api-symbols.txt` (via `xcrun swift-demangle`), SDK source files under `Sources/DroppyKit/`, `COMPATIBILITY.md`, `droppykit lint --app-floor 1.12.0`, and `/Applications/Droppy.app` (`16.2.1-nightly.26110901`).

| API / symbol | Introduced in | Used by AETHER | Required host floor | Verified |
|---|---|---|---|---|
| `@objc DropletPrincipal` (`makeDroplet()`) | `1.0.0` (`Droplet.swift:36-44`) | `AETHERPrincipal` | Droppy `15.3.0` (`ABI 1`) | Yes (SDK source doc + protocol contract; `@objc` protocol not emitted in Swift-mangled `api-symbols.txt`) |
| `Droplet` (`id`, `activate(host:)`, `deactivate()`) | `1.0.0` (`api-symbols.txt`) | `AetherDroplet` lifecycle | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `HUDPresenting` | `1.0.0` (`api-symbols.txt`) | `AetherDroplet: NSObject, HUDPresenting` | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `DropletHost.hud`, `.log`, `.workspace`, `.isGranted(_:)` | `1.0.0` (`api-symbols.txt`) | `host.hud`, `host.log`, `host.workspace`, `host.isGranted(.clipboardWrite)` | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `DropletPermission.clipboardWrite`, `.hud` | `1.0.0` (`api-symbols.txt`, `DropletPermission.swift:72,119`) | Capability checks & manifest declarations | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `DropletHUDPriority.normal` | `1.0.0` (`api-symbols.txt`) | `DropletHUDRequest(..., priority: .normal)` | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `DropletHUDService.present(_:)`, `.dismiss(id:)` | `1.0.0` (`api-symbols.txt`) | Presenting and dismissing OTP HUDs | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `DropletWorkspaceService.copyToPasteboard(_:)` | `1.0.0` (`api-symbols.txt`) | Copying OTP code in `Copy Code` action | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `DropletLogService.info(_:)`, `.notice(_:)` & `DropletLogLevel` | `1.0.0` (`api-symbols.txt`) | Lifecycle and refusal logging (zero OTP codes logged) | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `DroppyLiveActivityMetrics.iconSize`, `.labelFontSize` | `1.0.0` (`api-symbols.txt`) | Compact strip icon & monospaced code typography | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `AdaptiveColors.notchSurfacePrimaryText`, `.notchSurfaceSecondaryText` | `1.0.0` (`api-symbols.txt`) | Dark notch HUD text colors | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `DroppySpacing.xs`, `.sm` | `1.0.0` (`api-symbols.txt`) | Expanded card spacing | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.0.0]`) |
| `DropletHUDRequest.init(id:duration:priority:accessibilityLabel:isExpanded:expandedContentHeight:content:expanded:)` | `1.1.0` (`api-symbols.txt`) | Compact strip + `AetherOTPHUDCardView` expanded HUD | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.1.0]`; also verified exported by installed `/Applications/Droppy.app` `DroppyKit.framework`) |
| `DropletCategory.system` (`"category": "System"`) | `1.12.0` (`api-symbols.txt`, `DropletManifest.swift:245-247`) | `droplet.json` Store category | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.12.0]`, `COMPATIBILITY.md:121`, `droppykit lint --app-floor 1.12.0` -> `15.3.0`) |
| `DropletManifest.minMacOS` (`"minMacOS": "15.0"`) | `1.12.0` (`api-symbols.txt`, `COMPATIBILITY.md:121`) | `droplet.json` OS floor (matches `Package.swift` `.macOS(.v15)`) | Droppy `15.3.0` | Yes (`api-symbols.txt` `[1.12.0]`, `COMPATIBILITY.md:121`, `droppykit lint` `min-macos` check) |
| `DropletHarnessApp` (`makeDroplet()`) | `DroppyKitHarness` dev target (non-shipping) | `Droplet/Sources/AETHERHarness/AETHERHarness.swift` | Harness / Xcode 26+ | Yes (`DropletHarness.swift:470-489`) |

### Compatibility Nuance Finding
- The previous compliance report stated *"AETHER uses HUD and UI APIs introduced in SDK versions 1.0.0–1.1.0"*. Independent verification shows that while all **Swift runtime/UI symbols** in `AetherDroplet.swift` were indeed introduced in `1.0.0`–`1.1.0`, `Droplet/droplet.json` also relies on **`1.12.0` manifest features** (`DropletCategory.system` and `DropletManifest.minMacOS`), whose documented minimum Droppy host floor is `15.3.0` (`COMPATIBILITY.md:121`; `droppykit lint --app-floor 1.12.0` returns `15.3.0`).
- `kit.minAPI: "1.12.0"` accurately declares the minimum runtime SDK required by AETHER (not the SDK version `1.23.0` used at compile time), and `Droplet/Package.swift` `from: "1.12.0"` matches `kit.minAPI` per `lint-droplet.py`'s `package-pin` rule while resolving `v1.23.0` (`Droplet/Package.resolved`) under ABI `1` library evolution. Every declared version bound (`kit.minAPI: "1.12.0"`, `minAppVersion: "15.3.0"`, `minMacOS: "15.0"`) is verified exact and consistent.

---

## 4. Actual Principal Class & Manifest Verification

- `Droplet/Package.swift` declares `.library(name: "AETHER", type: .dynamic, targets: ["AETHER"])`, so official `Scripts/build-droplet.sh` sets:
  - `CFBundleExecutable = "AETHER"`
  - `CFBundleIdentifier = "app.getdroppy.droplet.aether"`
  - `NSPrincipalClass = "AETHERPrincipal"` (default `product + "Principal"` per `DroppyKit/Scripts/build-droplet.sh:319`)
  - `DroppyDropletID = "aether"`
  - `DroppyKitABI = 1`
  - `DroppyKitMinAPI = "1.12.0"`
  - `DroppyMinAppVersion = "15.3.0"`
  - `LSMinimumSystemVersion = "15.0"`
  - `DroppyPermissions = ["hud", "clipboard-write"]`
- `Droplet/Sources/AETHER/AetherDroplet.swift` defines:
  - `@objc(AETHERPrincipal) public final class AETHERPrincipal: NSObject, DropletPrincipal` with nonisolated `init()` and `@MainActor public func makeDroplet() -> AnyObject`
  - `@MainActor public final class AetherDroplet: NSObject, HUDPresenting` with `public nonisolated static let id: DropletID = "aether"`
- `Droplet/droplet.json` has `id: "aether"`, 55-character `summary` (`<= 60` char limit), `category: "System"`, `surfaces: ["hud"]`, `capabilities: ["hud", "clipboard-write"]`, `icon: "AETHER.icon"`, `creator.kind: "community"`, valid `512x512` square PNG `Assets/Creator.png`, and `source` (`https://github.com/NilambarSonu/AETHER`, `GPL-3.0`) matching `Droplet/LICENSE` and `Droplet/NOTICE.md`.

---

## 5. IPC & Source-Parity Review

- **File Inventory & SHA-256 Parity:** All 10 files across `Protocol/`, `Codec/`, and `Transport/` in `Droplet/Sources/AetherIPC/` match `Sources/AetherCore/` **byte-for-byte** (verified independently by Python SHA-256 comparison and enforced by `AetherReleaseHardeningTests`).
- **Module Isolation & Dependencies:** `AetherIPC` imports only `Foundation`, `Darwin`, and `Security`; zero host-only dependencies (`CodeCatchCore`, SQLite, Mail/Messages DBs, OAuth, Keychain vault, or `AppKit` host UI) exist anywhere inside `Droplet/`.
- **Swift 6 Concurrency:** `AetherIPC` and `AETHER` both declare `.swiftLanguageMode(.v6)`; `Droplet/Sources/AetherIPC/` was compiled standalone for both `arm64` and `x86_64` under `-swift-version 6`; `AetherDroplet` avoids capturing non-`Sendable` `DropletHost` inside `@Sendable` closures (`Task` captures `[weak self, clientTransport]`, HUD builders capture `[weak self]` cleanly without retaining `self`).
- **Privacy & Logging:** Audited all occurrences of `host.log`, `otpCode`, `print`, `NSLog`, `UserDefaults`, `Keychain` in `Droplet/Sources/`: zero plaintext OTP codes or session tokens appear in logs (`AetherOTPPayload.description` redacts `otpCode`), and the droplet persists zero secrets or preferences.
- **Lifecycle & Teardown:** `AetherDroplet.deactivate()` dismisses any active OTP HUD by ID, cancels `eventTask`, clears `host = nil`, and spawns `await activeTransport?.stop()`. `AetherIPCClientTransport.stop()` sets `isStopped = true`, cancels `autoReconnectTask`, invokes `disconnect()` (cancelling `readTask`, calling `Darwin.shutdown` + `Darwin.close` on `socketFD`, resetting frame decoder), and calls `payloadContinuation.finish()` to terminate the `AsyncStream` loop.
- **Architecture & Maintenance Assessment:** Synchronizing the 10 standalone `Foundation`/`Darwin`/`Security` files into `Droplet/Sources/AetherIPC/` is **architecturally justified** here because `DroppyKit/Scripts/build-droplet.sh` (`LOCAL_TARGETS`) only links regular SwiftPM targets defined *inside* the droplet package itself and does not link external local package products into the manual `xcrun swiftc -emit-library` step. The synchronization risk is strictly mitigated by the automated SHA-256 drift check in `Tests/AetherCoreTests/AetherReleaseHardeningTests.swift` (`#expect(SHA256.hash(data: coreBytes) == SHA256.hash(data: ipcBytes))`). Future changes to host IPC protocol/codec/transport files must copy updated files into `Droplet/Sources/AetherIPC/` or tests will immediately fail.

---

## 6. Installer & Rollback Security Findings (`scripts/build-droplet.sh`)

Line-by-line inspection evaluated every safety invariant and **identified and remediated three gaps** during this audit:

1. **Symlink Redirection & Traversal Protection Added:**
   - **Finding prior to audit fix:** `validate_droplet_bundle` checked symlinks *inside* the bundle only against leading `/` (`/*`), missing escaping relative symlinks (e.g., `../../../../etc/hosts`), did not reject `[ -L "$bundle" ]` when the bundle root itself was a symlink, and `install`/`rollback` did not reject symlinked `$TARGET_DIR`, `$PREVIOUS_BACKUP`, or `..` traversal segments in `AETHER_DROPLET_INSTALL_DIR`.
   - **Fix applied:** Added `reject_traversal_or_symlink_target` checking `..`/`.` traversal and `[ -L ]` on target directory & parent, explicit symlink rejection for `$bundle`, `$PREVIOUS_BACKUP`, and `$EXISTING_BUNDLE`, and Python `os.path.realpath` containment enforcement rejecting both absolute and escaping relative symlinks inside the bundle. Verified via new adversarial tests in `AetherReleaseHardeningTests`.
2. **Case-Insensitive APFS Handling Improved:**
   - **Finding prior to audit fix:** `find_existing_case_insensitive_bundle` gated Python directory scanning behind `[ -e "$dir/$DROPLET_INSTALL_NAME" ]`, which skips broken symlinks.
   - **Fix applied:** `find_existing_case_insensitive_bundle` now inspects `os.listdir` directly for case-insensitive matches of `aether.droplet` (and installer rejects any matching symlink), preserving unrelated sibling bundles (`Other.droplet`, markers) untouched. Verified by test.
3. **Atomicity Scope & Swap Integrity Verified Honest:**
   - All pre-install validations and `cp -R` staging into `.AETHER.droplet.staging.$$` complete and pass post-copy `validate_droplet_bundle` *before* touching any existing install (`Aether.droplet` / `AETHER.droplet`).
   - Replacement uses two same-directory renames (`mv existing -> backup_tmp` then `mv staging -> INSTALL_BUNDLE`, with automatic `mv backup_tmp -> existing` rollback on failure), avoiding any destructive `rm -rf` prior to a validated copy. Rollback validates `.AETHER.droplet.previous` both before and after staging restore.
4. **Privilege & Prompt Preservation Verified:**
   - Zero `defaults write`, `askBeforeRunning`, or `droplet.aether.enabled` modifications exist anywhere in `scripts/build-droplet.sh`.
   - Default Droppy (`~/Library/Application Support/Droppy/Droplets/aether`) and `--playground` (`~/Library/Application Support/Droppy Playground/Droplets/aether`) paths are strictly distinct (verified under isolated `HOME` test).

---

## 7. GitHub Actions CI Preflight (`.github/workflows/macos-build.yml`)

Line-by-line review of all 162 lines (enhanced to 199 lines during this audit):

- **Runner & Xcode 26+ Selection:** `runs-on: macos-15`. Added explicit `Xcode 26+` major-version gate (`xcodebuild -version` major `>= 26`), supporting `Xcode_2[6-9]*.app` and failing immediately if absent instead of hitting cryptic macro errors downstream.
- **Reproducible Pinning:** Official DroppyKit checkout is cloned from `https://gitlab.com/droppyformac1/droppykit.git` and checked out detached at verified commit `11e4869898bf13991120e26af347b9007521623b` (`v1.23.0`). CI now also asserts pre-build and post-build that `Droplet/Package.resolved` pins `https://gitlab.com/droppyformac1/droppykit.git` at `version: "1.23.0"`, `revision: "11e4869898bf13991120e26af347b9007521623b"`.
- **Genuine SDK Build, Ledger Check, Lint & Harness:** Runs `droppykit version`, `droppykit lint --no-binary --strict`, `droppykit build`, `droppykit validate` (which executes `api-ledger.sh check` against `AETHER.droplet/Contents/MacOS/AETHER`, universal `arm64 x86_64` slice verification, manifest/creator/icon checks, and binary lint), `./scripts/build-droplet.sh --validate-only`, and `droppykit run -- --shots ./shots --report ./shots/report.json`.
- **Argument Forwarding & Harness Fail Gate:** Verified `Scripts/droppykit` (`run`) -> `Scripts/run-harness.sh` (`case " $* " in *" --shots "*`) -> `DropletHarnessApp` forwards `--shots ./shots --report ./shots/report.json` cleanly; Python gate asserts `report["verdict"] == "ok"`, `report["problems"] == []`, and `len(report["shots"]) >= 1`.
- **No Stub Fallback & Strict Gate Ordering:** Zero fallback to static-only checks; `actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2` (14-day retention) executes only after every build, test, validate, harness, and ZIP layout check succeeds.
- **Security & Least Privilege:** Top-level `permissions: contents: read`; `actions/checkout` uses `persist-credentials: false`; host release build strips local paths via `-debug-prefix-map` / `-file-prefix-map`; zero secrets or local machine paths are referenced.
- **Status Note:** Workflow has not executed remotely yet because no commit/push was made in this audit phase.

---

## 8. Artifact ZIP Structure Verification (`AETHER-Droplet.zip`)

- **Shared Packaging Logic (`scripts/build-droplet.sh --stage-dist`):** Added deterministic clean distribution staging used directly by CI (`./scripts/build-droplet.sh --stage-dist .build-droplet-dist --bundle Droplet/.build/AETHER.droplet`) and covered by automated unit tests.
- **CI ZIP Preflight:** In addition to checking `.build-droplet-dist`, CI builds a temporary ZIP archive and asserts via `unzip -Z1` that top-level entries are exclusively `AETHER.droplet/` and `README-TESTING.md`.
- **Local Test Fixture Verification:** `dropletDistributionZipLayoutMatchesOfficialSpec()` builds a real universal (`arm64` + `x86_64`) test bundle fixture, stages via `--stage-dist`, archives via `/usr/bin/zip`, extracts with `/usr/bin/unzip` into a clean directory, and verifies:
  - Top-level extracted entries are strictly `["AETHER.droplet", "README-TESTING.md"]` (no `content/`, `output/`, or wrapper directory).
  - `AETHER.droplet/Contents/Info.plist`, `AETHER.droplet/Contents/MacOS/AETHER` (executable `+x`), and `AETHER.droplet/Contents/Resources/droplet.json` exist.
  - Zero forbidden entries (`CodeCatch`, `CodeCatchCLI`, `DroppyKit.framework`, `.droppykit`, `.build`, `.swiftpm`, `.git`, `.DS_Store`, `content`).

---

## 9. Local Verification Results (Re-Run After Final Audit Edits)

| Check / Command | Exit Code | Result & Exact Counts |
|---|---|---|
| `droppykit lint --package .../Droplet --no-binary --strict` | `0` | `✓ no findings` (binary: not checked) |
| `droppykit lint --package .../Droplet --submit --no-binary --strict` | `0` | `✓ no findings` (binary: not checked) |
| `bash -n scripts/build-droplet.sh` | `0` | Passed cleanly |
| `ruby -ryaml` (`.github/workflows/macos-build.yml`) | `0` | `Workflow YAML valid; jobs=build-and-test` |
| `python3 scripts/test-release-privacy.py` | `0` | `Ran 7 tests in 1.179s` — `OK` |
| `git diff --check` | `0` | Passed cleanly (zero whitespace errors) |
| `./scripts/test.sh --force-resolved-versions` (`CodeCatchTests`) | `0` | **241 tests in 21 suites passed** |
| `./scripts/test.sh --force-resolved-versions` (`CodeCatchCoreTests`) | `0` | **38 tests in 1 suite passed** (including all 704 `CodeExtractorTests` OTP fixtures) |
| `./scripts/test.sh --force-resolved-versions` (`AetherCoreTests`) | `0` | **57 tests in 5 suites passed** (IPC protocol/codec/transport, SHA-256 parity, `Package.resolved` pin, no-stub check, universal staged install/rollback, symlink/traversal rejection, APFS casing, Playground destination, ZIP extraction layout) |
| **Total Automated Tests Run Locally** | **`0`** | **343 checks passed (336 Swift + 7 Python privacy tests), 0 failed, 0 skipped** |

**Explicitly NOT Executed Locally (Cannot Pass Locally Without Xcode 26+ / Playground):**
- Genuine `droppykit build` universal compilation (`arm64` + `x86_64`)
- Genuine `droppykit validate` binary `api-ledger.sh check` & symbol scan on compiled `AETHER` binary
- Headless `droppykit run -- --shots ./shots --report ./shots/report.json` harness rendering
- Live loading & approval prompt verification in Droppy Playground or `/Applications/Droppy.app`

---

## 10. Remaining Blockers Before Final Release Sign-Off

1. **GitHub Actions CI Run Required:** Commit and push `main` (only after explicit user authorization) so `macos-15` with Xcode 26+ compiles the real universal `AETHER.droplet`, executes `api-ledger.sh check`, runs `droppykit run -- --shots ./shots --report ./shots/report.json`, and publishes `AETHER-Droplet.zip`.
2. **Manual Runtime Testing Required Post-CI:** Download `AETHER-Droplet.zip` from the CI run, confirm clean unzip root (`AETHER.droplet/` + `README-TESTING.md`), test in **Droppy Playground** and/or `/Applications/Droppy.app` (`16.2.1-nightly.26110901`) following `README-TESTING.md`, approve requested capabilities (`hud`, `clipboard-write`), and verify live synthetic OTP HUD presentation + Copy action with AETHER host running (`--probe-droplet-otp`).
3. **Distribution Signing Notice:** Official `droppykit build` artifacts are unsigned (appropriate for CI/Playground testing and Droppy's explicit user approval flow); public end-user distribution outside CI/Store requires Developer ID code signing and Apple notarization.

---

## 11. Exact Files Created or Modified During Phase 3F.2 Audit

1. Created `Droplet/Package.resolved` — resolves & pins `droppykit` (`https://gitlab.com/droppyformac1/droppykit.git`) to exact `1.23.0` commit `11e4869898bf13991120e26af347b9007521623b`.
2. Updated `scripts/build-droplet.sh` — added symlink/traversal guards, escaping relative-symlink containment validation inside bundles, broken-symlink-safe APFS case handling, `$1` option error fix, and `--stage-dist` clean distribution staging helper.
3. Updated `.github/workflows/macos-build.yml` — added strict Xcode `>= 26` check, pre/post-build `Droplet/Package.resolved` pin assertions, `--stage-dist` invocation, and CI `zip`/`unzip -Z1` root-entry verification.
4. Updated `Tests/AetherCoreTests/AetherReleaseHardeningTests.swift` — added `Droplet/Package.resolved` pin assertions, symlink/traversal rejection tests, APFS case-preservation + Playground isolation tests, and end-to-end `--stage-dist` + `zip`/`unzip` layout round-trip test.
5. Created `docs/phase-3f2-independent-release-audit.md` — this independent release-candidate audit report.
