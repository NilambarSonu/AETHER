# AETHER Droplet — Installation & Testing Guide

This directory/archive ships **`AETHER.droplet`** (`2.0.0`), a standalone droplet built with the official **DroppyKit SDK** (`minAPI: 1.23.0`, `abi: 1`, `minAppVersion: 16.2.0`, universal `arm64` + `x86_64` binary dynamically linked against `@rpath/DroppyKit.framework/Versions/A/DroppyKit`).

> [!IMPORTANT]
> **Security & Trust Boundary**
> - `AETHER.droplet` is loaded dynamically (`dlopen`) inside the `Droppy.app` host process and shares Droppy's address space and permissions (including Full Disk Access & Accessibility once granted to Droppy).
> - Review AETHER's declared capabilities (`hud`, `notch-banner`, `menu-bar`, `shelf-read`, `shelf-write`, `global-shortcuts`, `network-client`, `clipboard-write`, `full-disk-access-probe`, `accessibility`, `sound-playback`) carefully and approve enabling AETHER inside Droppy Settings.
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

2. Launch **Droppy Playground**, open **Settings → Droplets → AETHER**, review its declared capabilities, and approve enabling it.
3. Verify AETHER renders all settings pages inside **Droppy Settings → Droplets → AETHER**, appears in the **Notch Shelf** picker and **Command Center**, and delivers a test code via **Send Test Code**.

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

2. Open **Droppy Settings → Droplets → AETHER** and approve/enable **AETHER** when prompted.
3. Configure your sources (**Messages**, **Apple Mail**, **Google Gmail OAuth**, **Microsoft Outlook OAuth**, **iCloud/Yahoo/IMAP**, **Bitwarden TOTP**, **Agents & MCP**, **Privacy**) inside **Droppy Settings → Droplets → AETHER**.
4. Grant **Full Disk Access** to **Droppy** if watching Messages / Apple Mail, and **Accessibility** if using auto-type.
5. Add the **AETHER** widget to your **Notch Shelf** or open **Command Center** to view, search, copy, and open incoming codes and sign-in links.

---

## 4. Building & Running the Official DroppyKit Harness from Source

Building `.droplet` bundles and running `DroppyKitHarness` requires **Xcode 26 or later** (Command Line Tools alone cannot compile `SwiftUIMacros` inside `DroppyKit`).

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
