# AETHER — Phase 3F.1: Post-Publication Security, SDK ABI & Installation Hardening Report

**Date:** November 10, 2026

**Repository:** `https://github.com/NilambarSonu/AETHER`

**Branch:** `main` (`origin/main` at `0fc474a3940218ec1ee8679b81eb8f8a2bfb06c0`, unchanged during audit)

**Initial Release Commit:** `a20c36078312422f9e9979d2ebef7e6e384b9b69`

**Latest Remote CI Commit:** `0fc474a3940218ec1ee8679b81eb8f8a2bfb06c0`

**Phase 0 Backup:** Intact at `/Users/nilambarbehera/Documents/Projects/Aether_Backups/Aether_baseline_20261109`

**Final Verdict:** **`APPROVED WITH CONDITIONS — DOCUMENTED LIMITATIONS REMAIN`**

---

## 1. Preflight Baseline Recorded

Before any Phase 3F.1 modifications:
- **`git status --short --branch`:** `## main...origin/main` (clean working tree).
- **`git log -5 --oneline --decorate`:**
  - `0fc474a (HEAD -> main, origin/main, origin/HEAD) ci: select Xcode 26+ SDK on macOS runner for SwiftUI Liquid Glass symbols`
  - `a20c360 Initial AETHER release: secure Droppy OTP integration`
  - `c37d836 (upstream/main, upstream/HEAD) chore(release): v2.0.339`
  - `a15b8c0 (tag: v2.0.339) docs(changelog): add the 29 October release`
  - `9019cd1 fix(menu): keep a tall popover's top on the display`
- **`git remote -v`:**
  - `origin`: `https://github.com/NilambarSonu/AETHER.git`
  - `upstream`: `https://github.com/ugzv/CodeCatch.git`
- **Backup Integrity:** `/Users/nilambarbehera/Documents/Projects/Aether_Backups/Aether_baseline_20261109` verified present and untouched.
- **Starting Test Baseline (`./scripts/test.sh --force-resolved-versions`):** 331 / 331 tests passed across 26 suites (`CodeCatchTests`: 241, `CodeCatchCoreTests`: 38, `AetherCoreTests`: 52).

---

## 2. Audit A — DroppyKit SDK & ABI Truthfulness

### 2.1 Findings Against Genuine `DroppyKit.framework` & Official Upstream SDK

Inspected [`Droplet/DroppyKitInterface.swift`](../Droplet/DroppyKitInterface.swift), [`scripts/build-droplet.sh`](../scripts/build-droplet.sh), [`Droplet/Aether/Sources/AetherDroplet.swift`](../Droplet/Aether/Sources/AetherDroplet.swift), the installed binary `/Applications/Droppy.app/Contents/Frameworks/DroppyKit.framework/Versions/A/DroppyKit` (`16.2.1-nightly.26110901`), and the public SDK repository (`https://gitlab.com/droppyformac1/droppykit.git`, API `1.23.0`, ABI `1`):

1. **Approximation vs. Exact ABI:** [`Droplet/DroppyKitInterface.swift`](../Droplet/DroppyKitInterface.swift) is a **minimized ABI interface stub**, not a verbatim copy of the full DroppyKit SDK.
2. **ABI Discrepancies Found & Remediated:**
   - **`DroppyKitMinAPI` Version Mismatch:** [`Droplet/Aether/Info.plist`](../Droplet/Aether/Info.plist) and [`Droplet/Aether/droplet.json`](../Droplet/Aether/droplet.json) previously declared `1.9.0` (`minAppVersion: 15.3.0`), even though `DropletHUDCard`, `DropletHUDAction`, `DropletHUDStrip`, and template `DropletHUDRequest` were introduced in **DroppyKit `1.23.0`**. Pre-1.23.0 hosts would pass the version check and crash at `dyld` symbol binding. Updated both metadata files to `1.23.0` (`minAppVersion: 16.2.0`).
   - **Missing `Droplet.prepareForRemoval()` Requirement:** Real `Droplet` protocol (`nm -gU` symbol `_$s9DroppyKit7DropletP17prepareForRemovalSbyFTq`) requires `func prepareForRemoval() -> Bool` with default extension `(extension in DroppyKit):Droplet.prepareForRemoval() -> Bool`. Added both to `DroppyKitInterface.swift`.
   - **Missing `DropletPrincipal.init()`:** Real `@objc protocol DropletPrincipal` requires `init()`. Added cleanly.
   - **`DropletHUDPriority` Raw Values & Conformances:** Real SDK defines `case low = 0, normal = 500, high = 1000` conforming to `Int, Sendable, Codable, Comparable` (not `0, 1, 2`). Fixed raw values and conformances.
   - **Actor Isolation vs. Spurious `Sendable`:** Real `DropletHost`, `DropletHUDService`, `DropletWorkspaceService`, `DropletLogService`, and `DropletHUDRequest` use `@MainActor` isolation rather than explicit `: Sendable`. Aligned `DroppyKitInterface.swift` to `@MainActor public struct DropletHost` and removed the artificial `: Sendable` protocol inheritance.
   - **`DropletID` Validation & Conformances:** Added `Codable`, `CustomStringConvertible`, `validLengthRange`, `isValid(_:)`, and `init?(validating:)`.
3. **CI Framework Skeleton:** In CI/standalone mode (`STUB_SKELETON_COMPILE_ONLY`), `scripts/build-droplet.sh` compiles `Droplet/DroppyKitInterface.swift` into a temporary `.framework` stub exclusively for `swiftc`/`ld` symbol resolution. It contains **zero** Droppy runtime implementations.
4. **Runtime Binding & Packaging:** `Aether.droplet` does **not** embed `DroppyKit.framework`. `otool -L` confirms a dynamic dependency on `@rpath/DroppyKit.framework/Versions/A/DroppyKit` resolved at `dlopen` runtime by `Droppy.app`.
5. **CI Build vs. Real Runtime Validation:** GitHub Actions performs **compile, `-enable-library-evolution` linkage, `@rpath`, bundle structure, `Info.plist`/`droplet.json`, and Mach-O `arm64` validation ONLY**. It does **not** load or execute `Aether.droplet` inside `Droppy.app`.
6. **Repeatability Against Published Commit `0fc474a`:** Commit `0fc474a` successfully ran in Phase 3F locally only while `scripts/build-droplet.sh` disabled `droplet.approvals.askBeforeRunning = false`. Once Phase 3F.1 restored `droplet.approvals.askBeforeRunning = true`, live `Droppy.app` (`PID 87520`) legitimately deferred launching the newly rebuilt ad-hoc `Aether.droplet` pending explicit user confirmation in Droppy's frontmost UI (`"Droplet launch approval question deferred until Droppy is frontmost"`).

### 2.2 SDK/ABI Verification Matrix

Matched via `nm -u Droplet/.build/Aether.droplet/Contents/MacOS/Aether` against `nm -gU /Applications/Droppy.app/Contents/Frameworks/DroppyKit.framework/Versions/A/DroppyKit` (**25 / 25 referenced DroppyKit symbols matched; 0 missing**):

| Declaration / Type | Status | Verification Evidence |
| :--- | :--- | :--- |
| `DropletPrincipal` (`init()`, `makeDroplet()`) | **Verified** | Objective-C runtime protocol; `Droplet.swift:36` |
| `DropletID` (`init(stringLiteral:)`, resilient layout) | **Verified** | `_$s9DroppyKit9DropletIDV13stringLiteralACSS_tcfC` & `VMa` matched |
| `Droplet` (`id`, `activate(host:)`, `deactivate()`, `prepareForRemoval()`) | **Verified** | `_$s9DroppyKit7DropletMp`, all 4 `Tq` method descriptors & `PAAE17prepareForRemoval` matched |
| `DropletHUDService` (`present(_:)`, `dismiss(id:)`) | **Verified** | Dispatch thunks `Tj` matched byte-for-byte |
| `DropletWorkspaceService` (7 requirements in witness order) | **Verified** | `copyToPasteboard(_:)` dispatch thunk `Tj` matched; order matches `DropletServices.swift:890` |
| `DropletLogService` (`log(_:_:)`, `info` extension) | **Verified** | `_$s9DroppyKit17DropletLogServicePAAE4infoyySSF` matched |
| `DropletHUDPriority` (`low=0`, `normal=500`, `high=1000`) | **Verified** | Enum metadata `OMa`, case `high` `OWC`, raw values matched `DropletServices.swift:382` |
| `DropletHUDAction`, `DropletHUDCard`, `DropletHUDStrip` | **Verified** | All initializers & metadata accessors matched |
| `DropletHUDRequest` (`init(...card:isExpanded:leading:trailing:)`) | **Verified** | Generic template initializer mangled symbol matched byte-for-byte |
| `DropletHost` (`hud`, `log`, `workspace` resilient getters) | **Verified (Getters)** / **Inferred (Struct Layout)** | Resilient getters (`hud`, `log`, `workspace`), `VMa`, and `VMn` matched. Note: `DroppyKitInterface.swift` omits 11 other host services (`preferences`, `shelf`, etc.) and uses a 3-arg `init` placeholder; safe only because `-enable-library-evolution` enforces indirect metadata/getter access and droplets never invoke `DropletHost.init`. |
| Unreferenced SDK APIs (`Shelf`, `LiveActivity`, `Notifications`, `Launcher`) | **Unverified / Omitted** | Intentionally excluded from stub header; unused by `Aether.droplet`. |

---

## 3. Audit B — Process Isolation & Security Documentation (Before / After)

| Document | Unsupported / Inaccurate Prior Claim | Updated Accurate Statement |
| :--- | :--- | :--- |
| [`README.md`](../README.md) (§1 Design Principles) | *"runs as a sandboxed plug-in inside Droppy with zero disk or credential access"* and *"enforcing strict zero-trust boundaries"* | Clarifies that `Aether.droplet` is dynamically loaded (`dlopen`) into `Droppy.app` (`iordv.Droppy`), **shares Droppy's address space, entitlements, and security context**, is **not** an independent macOS App Sandbox, and reads `session.token` from disk under Droppy's permissions while host FDA/Keychain/mail access remain in AETHER. |
| [`README.md`](../README.md) (§4 IPC & Auth) | Implied `LOCAL_PEERTOKEN` and POSIX `0700`/`0600` provided complete per-droplet isolation; omitted same-UID POSIX nuance. | Explains that `LOCAL_PEERTOKEN` authenticates the **`Droppy.app` process** (not individual droplets inside it), co-loaded droplets share Droppy's process space, and POSIX `0700`/`0600` enforces cross-UID boundaries (not same-UID). |
| [`README.md`](../README.md) (§6 & §8 Toolchain & Validation) | Stated CLT alone builds everything and didn't distinguish CI stub compile checks from runtime execution. | Distinguishes CLT compatibility (`AetherCore` / `Droplet`) from **Xcode 26+ SDK** requirement (`CodeCatch` macOS 26 UI `CodeRow.swift`); explicitly separates CI stub compile/package validation from genuine runtime testing. |
| [`ARCHITECTURE.md`](../ARCHITECTURE.md) | Described `Aether.droplet` as *"Standalone"* without documenting Droppy shared-process model or IPC identity limits. | Updated target table and added **`## Droppy Bridge & Trust Boundaries (Option A)`** detailing `dlopen` into `Droppy.app`, process-level `LOCAL_PEERTOKEN`, POSIX UID scope, and co-loaded droplet risks. |
| [`SECURITY.md`](../SECURITY.md) | Lacked process trust-boundary disclosures for Droppy host vs. droplet plugin model. | Added **`### Process Trust Boundary & Residual Risks`** clarifying shared process space, process-level audit tokens, and POSIX DAC limits. |
| [`NOTICE.md`](../NOTICE.md) | Summarized DroppyKit linking without explaining zero proprietary binary redistribution. | Clarifies that `DroppyKitInterface.swift` contains clean ABI stub declarations only, with no proprietary Droppy binaries or SDK implementations redistributed. |

---

## 4. Audit C — Installer Safety & Rollback Hardening

### 4.1 Remediations in [`scripts/build-droplet.sh`](../scripts/build-droplet.sh)
- **Eliminated Destructive Pre-Delete:** Removed `rm -rf "$TARGET_DIR/Aether.droplet"` prior to copy.
- **Pre-Install & Post-Stage Validation:** `validate_droplet_bundle()` checks bundle layout, Mach-O `arm64` shared library (`file`), `@rpath/Aether` and `DroppyKit.framework` (`otool -L`), `Info.plist` (`plutil -lint`), `manifest.id`/`minAPI` consistency (`1.23.0`), and `codesign --verify --deep --strict` before touching any installed bundle.
- **Atomic Staged Replacement & Automatic Rollback:** Copies into `$TARGET_DIR/.Aether.droplet.staging.$$`, moves existing bundle to `.Aether.droplet.backup_tmp.$$`, and automatically restores the exact original bundle inode if the swap fails (`trap` cleanup prevents leftover staging debris).
- **Preserved Recoverable Backup & `--rollback` Command:** Retains `.Aether.droplet.previous` across upgrades and implements `./scripts/build-droplet.sh --rollback` with full pre-restore validation.
- **Removed All Preference Weakening:** Deleted `defaults write iordv.Droppy "droplet.aether.enabled" -bool true` and `defaults write iordv.Droppy "droplet.approvals.askBeforeRunning" -bool false`. Restored `droplet.approvals.askBeforeRunning = true` on the local machine (`defaults read` confirmed `1`). Explicitly prints manual Droppy approval instructions.

### 4.2 Rollback Verification Results (`AetherReleaseHardeningTests`)
Tested inside an isolated temporary directory (`AETHER_DROPLET_BUILD_DIR` & `AETHER_DROPLET_INSTALL_DIR`) with `SIMULATE_CLEAN_CI=1`:
1. Clean stub build reports `STUB_SKELETON_COMPILE_ONLY` and explicitly states it does not validate runtime loading inside Droppy.
2. Initial `--install` succeeds with `User preferences were NOT modified` and `Manual approval required`.
3. Simulated swap failure (`AETHER_SIMULATE_INSTALL_SWAP_FAILURE=1`) fails non-zero, prints `Rollback succeeded`, and preserves the exact `v1` binary inode (`inode == inodeV1`) and byte contents (`data == dataV1`).
4. Subsequent `--install` installs new binary (`inodeV2 != inodeV1`) while moving `inodeV1` intact into `.Aether.droplet.previous`.
5. Explicit `--rollback` replaces `v2` (`inodeRestored != inodeV2`) with verified `v1` binary bytes (`data == dataV1`) while keeping `.Aether.droplet.previous` intact.

---

## 5. Audit D — CI Maintenance & Exact Diff

Inspected Run `42755793969` (`actions/upload-artifact@v4` emitted a Node.js 20 deprecation annotation). Querying the GitHub API confirmed:
- `actions/upload-artifact` commit `cf430e030ddbb5b0abf93d22962f4752f3646cd9` (`v7.0.2`) runs on `node24`.
- `actions/checkout` commit `3d3c42e5aac5ba805825da76410c181273ba90b1` (`v7.0.1`) runs on `node24`.

Prepared local changes in [`.github/workflows/macos-build.yml`](../.github/workflows/macos-build.yml) (unpushed):
```diff
-      - name: Build AETHER Droplet
+      - name: Build AETHER Droplet (Stub Compile & Package Validation)
         run: |
-          echo "==> Building Aether.droplet..."
+          echo "==> Building Aether.droplet against ABI stub declarations (compile/link/package validation only; does not execute Droppy.app at runtime)..."
           ./scripts/build-droplet.sh
...
+          echo "==> Verifying droplet.json manifest and Info.plist metadata..."
+          plutil -lint "$BUNDLE/Contents/Info.plist"
           python3 -c '
-          import json
+          import json, plistlib
           with open("Droplet/.build/Aether.droplet/Contents/Resources/droplet.json") as f:
               m = json.load(f)
+          with open("Droplet/.build/Aether.droplet/Contents/Info.plist", "rb") as f:
+              p = plistlib.load(f)
           assert m.get("id") == "aether", "Invalid droplet id"
+          assert m.get("kit", {}).get("minAPI") == "1.23.0", "Unexpected minAPI in droplet.json"
+          assert p.get("DroppyKitMinAPI") == "1.23.0", "Unexpected DroppyKitMinAPI in Info.plist"
           assert "hud" in m.get("capabilities", []), "Missing hud capability"
-          print("droplet.json manifest verification PASSED")
+          print("droplet.json & Info.plist verification PASSED")
           '

       - name: Upload Droplet Bundle Artifact
-        uses: actions/upload-artifact@v4
+        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
...
       - name: Upload Host Release Binaries
-        uses: actions/upload-artifact@v4
+        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
```

---

## 6. Test & Validation Evidence

| Command Executed | Scope | Result |
| :--- | :--- | :--- |
| `./scripts/test.sh --filter AetherReleaseHardeningTests` | Installer safety, no preference weakening, stub labelling, rollback, doc/manifest integrity | **3 / 3 passed (20.459s)** |
| `./scripts/test.sh --force-resolved-versions` | Complete workspace suite (`CodeCatchTests`, `CodeCatchCoreTests` + 704 OTP fixtures, `AetherCoreTests`) | **334 / 334 tests passed in 27 suites** (`241 + 38 + 55`) |
| `swift build --product CodeCatch && python3 scripts/test-release-privacy.py` | Host debug build & privacy verification scripts | **Passed (7 / 7 privacy tests OK)** |
| `SIMULATE_CLEAN_CI=1 ./scripts/build-droplet.sh` | Clean CI/stub framework skeleton compile & packaging check | **Passed (`Bundle validation PASSED`)** |
| `./scripts/build-droplet.sh --install` | Local `DroppyKit.framework` link + safe staged install (with `.previous` backup) | **Passed (zero preference writes)** |
| `swift format lint -r -p Sources/AetherCore Tests/AetherCoreTests Droplet Package.swift` | Formatting verification | **0 warnings** |
| `bash -n scripts/build-droplet.sh scripts/test.sh scripts/install.sh && git diff --check` | Shell syntax & whitespace cleanliness | **Exit code 0** |
| `nm -u` vs `DroppyKit.framework` `nm -gU` | External DroppyKit Mach-O symbol check | **25 / 25 matched, 0 missing** |

---

## 7. Changed Files & Current Git Status

**Changed / Created (Uncommitted, Unpushed):**
- `M .github/workflows/macos-build.yml`
- `M ARCHITECTURE.md`
- `M Droplet/Aether/Info.plist`
- `M Droplet/Aether/droplet.json`
- `M Droplet/DroppyKitInterface.swift`
- `M NOTICE.md`
- `M README.md`
- `M SECURITY.md`
- `M scripts/build-droplet.sh`
- `?? Tests/AetherCoreTests/AetherReleaseHardeningTests.swift`
- `?? docs/phase-3f.1-post-release-hardening.md`

Confirmed **zero commits and zero pushes** were made during Phase 3F.1 (`origin/main` remains `0fc474a3940218ec1ee8679b81eb8f8a2bfb06c0`).

---

## 8. Remaining Risks & Conditions

1. **Awaiting Live User Re-Approval of Rebuilt Droplet:** After restoring `droplet.approvals.askBeforeRunning = true` on the local Mac and staging the updated `Aether.droplet` (`DroppyKitMinAPI = 1.23.0`, `prepareForRemoval()`), `Droppy.app` (`PID 87520`) legitimately deferred activation until explicit user approval in Droppy UI (`"Droplet launch approval question deferred until Droppy is frontmost"`). Therefore, fresh runtime HUD + Copy verification of the *post-3F.1 rebuilt* bundle has not been re-executed without user confirmation.
2. **Shared Droppy Process Space:** `Aether.droplet` runs inside `Droppy.app` alongside any other active droplets and does not reside in a separate OS sandbox. Peer authentication verifies the `Droppy.app` process as a whole.
3. **CI Stub Interface Synchronization:** GitHub Actions validates droplet compilation against minimized stub declarations (`Droplet/DroppyKitInterface.swift`) rather than real `DroppyKit.framework` runtime loading; future DroppyKit API changes require keeping stub signatures aligned.
4. **Ad-Hoc Bundle Signing:** Droplet builds continue to use ad-hoc signing (`-s -`) suitable for local testing/CI rather than Developer ID notarized redistribution.

---

## 9. Final Verdict

### **`APPROVED WITH CONDITIONS — DOCUMENTED LIMITATIONS REMAIN`**
