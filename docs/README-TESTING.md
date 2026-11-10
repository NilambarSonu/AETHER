# AETHER Droplet — Installation & Testing Guide

This directory/archive ships **`AETHER.droplet`**, built with the official **DroppyKit SDK** (`minAPI: 1.12.0`, `abi: 1`, `minAppVersion: 15.3.0`, universal `arm64` + `x86_64` binary dynamically linked against `@rpath/DroppyKit.framework/Versions/A/DroppyKit`).

> [!IMPORTANT]
> **Security & Trust Boundary**
> - `AETHER.droplet` is loaded dynamically (`dlopen`) inside the Droppy host process and shares Droppy's address space and permissions.
> - Sensitive sources (Full Disk Access, Apple Mail/Messages databases, IMAP credentials, Keychain, OAuth tokens) stay strictly inside the **AETHER host application** (`CodeCatch`). `AETHER.droplet` receives only ephemeral verification codes over the same-user Unix Domain Socket after Darwin kernel audit-token verification (`LOCAL_PEERTOKEN`).
> - **Never disable Droppy's launch approval prompt (`askBeforeRunning`).** The droplet requests explicit capabilities (`hud`, `clipboard-write`) and must be manually reviewed and enabled by you inside Droppy.
> - CI-built bundles are unsigned for local testing and CI verification (not Developer ID notarized).

---

## 1. Archive Contents

Unzipping **`AETHER-Droplet.zip`** extracts directly to the root folder:

```text
AETHER.droplet/
  Contents/
    Info.plist
    MacOS/AETHER              # Universal arm64 + x86_64 resilient Mach-O dylib
    Resources/
      droplet.json
      AETHER.icon
      Assets/Creator.png
README-TESTING.md             # This guide
```

---

## 2. Option A — Test in Droppy Playground (Recommended First Step)

[Droppy Playground](https://getdroppy.app/docs/droppykit) lets you test community droplets cleanly without touching your main Droppy configuration.

1. Copy **`AETHER.droplet`** into the Playground Droplets directory (note the required droplet ID folder `aether`):

   ```bash
   mkdir -p "$HOME/Library/Application Support/Droppy Playground/Droplets/aether"
   cp -R AETHER.droplet "$HOME/Library/Application Support/Droppy Playground/Droplets/aether/"
   ```

   *(Or run `./scripts/build-droplet.sh --install --playground --bundle /path/to/AETHER.droplet` from the AETHER repository.)*

2. Launch **Droppy Playground** and approve **AETHER** when prompted (`hud`, `clipboard-write`).
3. Verify the droplet loads, displays in Droppy Playground's droplet list, and reports its `HUD` surface without linkage or manifest errors.

---

## 3. Option B — Install in Droppy

1. Copy **`AETHER.droplet`** to Droppy's local droplets directory (under the `aether` ID folder):

   ```bash
   mkdir -p "$HOME/Library/Application Support/Droppy/Droplets/aether"
   cp -R AETHER.droplet "$HOME/Library/Application Support/Droppy/Droplets/aether/"
   ```

   Or from the AETHER repository (uses safe staged atomic swap and keeps `.AETHER.droplet.previous` for rollback):

   ```bash
   ./scripts/build-droplet.sh --install --bundle /path/to/AETHER.droplet
   ```

   To roll back to the previous installed bundle if needed:

   ```bash
   ./scripts/build-droplet.sh --rollback
   ```

2. Open **Droppy Settings -> Droplets**.
3. Review AETHER's declared capabilities (`hud`, `clipboard-write`) and explicitly approve/enable **AETHER** when Droppy prompts.
4. Start the **AETHER host app** separately (`CodeCatch`) so it opens `~/Library/Application Support/Aether/droplet.sock` and writes `session.token` (`0600`) for live OTP HUD delivery.

---

## 4. Building & Running the Official DroppyKit Harness from Source

Building `.droplet` bundles and running `DroppyKitHarness` requires **Xcode 26 or later** (Command Line Tools alone cannot compile SwiftUI macros used inside `DroppyKit`).

```bash
# 1. Clone the official DroppyKit SDK and add Scripts to PATH
git clone https://gitlab.com/droppyformac1/droppykit.git ../droppykit
export PATH="$PWD/../droppykit/Scripts:$PATH"

# 2. Check environment & run official DroppyKit pipeline
cd Droplet
droppykit version
droppykit build
droppykit validate
droppykit lint --strict
droppykit run -- --shots ./shots --report ./shots/report.json
```

Or use the repository wrapper script:

```bash
DROPPYKIT_DIR=/path/to/droppykit ./scripts/build-droplet.sh
DROPPYKIT_DIR=/path/to/droppykit ./scripts/build-droplet.sh --install
```
