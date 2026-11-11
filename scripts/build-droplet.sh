#!/bin/bash
# Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
# Licensed under the GNU General Public License, Version 3.0 (GPLv3).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DROPLET_PKG="$PROJECT_ROOT/Droplet"
BUILD_DIR="$DROPLET_PKG/.build"
DEFAULT_BUNDLE="$BUILD_DIR/AETHER.droplet"

DROPLET_INSTALL_NAME="AETHER.droplet"
LEGACY_CASE_INSTALL_NAME="Aether.droplet"
PREVIOUS_BACKUP_NAME=".AETHER.droplet.previous"

INSTALL_FLAG=false
ROLLBACK_FLAG=false
VALIDATE_ONLY=false
PLAYGROUND_FLAG=false
NO_SUBMISSION_VALIDATE=false
PREBUILT_BUNDLE=""
STAGE_DIST_DIR=""
BUILD_ARCH=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --install) INSTALL_FLAG=true; shift ;;
        --rollback) ROLLBACK_FLAG=true; shift ;;
        --validate-only) VALIDATE_ONLY=true; shift ;;
        --playground) PLAYGROUND_FLAG=true; shift ;;
        --no-submission) NO_SUBMISSION_VALIDATE=true; shift ;;
        --bundle)
            [ "$#" -ge 2 ] || { echo "ERROR: --bundle requires a path" >&2; exit 2; }
            PREBUILT_BUNDLE="$2"
            shift 2
            ;;
        --stage-dist)
            [ "$#" -ge 2 ] || { echo "ERROR: --stage-dist requires a directory path" >&2; exit 2; }
            STAGE_DIST_DIR="$2"
            shift 2
            ;;
        --arch)
            [ "$#" -ge 2 ] || { echo "ERROR: --arch requires a value (arm64|x86_64|universal)" >&2; exit 2; }
            BUILD_ARCH="$2"
            shift 2
            ;;
        --help|-h)
            cat <<'EOF'
Usage: scripts/build-droplet.sh [OPTIONS]

Official DroppyKit wrapper with safe staged installation and rollback.
Building from source requires Xcode 26+ and the official DroppyKit SDK
(https://gitlab.com/droppyformac1/droppykit). No stub SDK builds are permitted.

Options:
  (default)             Build universal AETHER.droplet via official `droppykit build`
                        and validate it with `droppykit validate`
  --install             Safely stage, validate, and install AETHER.droplet with
                        recoverable backup (.AETHER.droplet.previous)
                        (Never modifies Droppy preferences or disables approval prompts)
  --playground          Target Droppy Playground Droplets directory when installing/rolling back
  --bundle <path>       Use an existing prebuilt AETHER.droplet instead of invoking `droppykit build`
                        (Useful for installing CI-built artifacts without local Xcode)
  --stage-dist <dir>    Validate bundle and stage clean distribution directory containing ONLY
                        AETHER.droplet/ and README-TESTING.md (no host binaries or build caches)
  --rollback            Restore the preserved previous installation (.AETHER.droplet.previous)
  --validate-only       Validate an existing bundle (--bundle <path> or Droplet/.build/AETHER.droplet)
  --arch <arch>         Forward `--arch <arm64|x86_64|universal>` to `droppykit build`
  --no-submission       Pass `--no-submission` to `droppykit validate`
EOF
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

reject_traversal_or_symlink_target() {
    local dir="$1"
    local label="$2"
    [ -n "$dir" ] && [ "$dir" != "/" ] || { echo "ERROR: Invalid $label path: '$dir'" >&2; return 1; }
    case "/$dir/" in
        */../*|*/./*)
            echo "ERROR: $label path must not contain traversal or relative dot segments: $dir" >&2
            return 1
            ;;
    esac
    local parent
    parent="$(dirname "$dir")"
    if [ -L "$dir" ] || [ -L "$parent" ]; then
        echo "ERROR: Refusing symlinked $label path or parent directory: $dir" >&2
        return 1
    fi
}

if [ -n "${AETHER_DROPLET_INSTALL_DIR:-}" ]; then
    TARGET_DIR="$AETHER_DROPLET_INSTALL_DIR"
elif [ "$PLAYGROUND_FLAG" = true ]; then
    TARGET_DIR="$HOME/Library/Application Support/Droppy Playground/Droplets/aether"
else
    TARGET_DIR="$HOME/Library/Application Support/Droppy/Droplets/aether"
fi

INSTALL_BUNDLE="$TARGET_DIR/$DROPLET_INSTALL_NAME"
PREVIOUS_BACKUP="$TARGET_DIR/$PREVIOUS_BACKUP_NAME"

resolve_droppykit_cli() {
    if [ -n "${DROPPYKIT_BIN:-}" ] && [ -x "$DROPPYKIT_BIN" ]; then
        printf '%s\n' "$DROPPYKIT_BIN"
        return 0
    fi
    if [ -n "${DROPPYKIT_DIR:-}" ] && [ -x "$DROPPYKIT_DIR/Scripts/droppykit" ]; then
        printf '%s\n' "$DROPPYKIT_DIR/Scripts/droppykit"
        return 0
    fi
    if command -v droppykit >/dev/null 2>&1; then
        command -v droppykit
        return 0
    fi
    if [ "${DROPPYKIT_DISABLE_AUTO_DISCOVERY:-}" = "1" ]; then
        return 1
    fi
    for candidate in \
        "$PROJECT_ROOT/.ci/droppykit/Scripts/droppykit" \
        "$PROJECT_ROOT/../droppykit/Scripts/droppykit" \
        "$HOME/Developer/droppykit/Scripts/droppykit"
    do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

find_existing_case_insensitive_bundle() {
    local dir="$1"
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
    local matches
    matches="$(python3 -c 'import os, sys
d, want = sys.argv[1], sys.argv[2].lower()
for entry in sorted(os.listdir(d)):
    if entry.lower() == want:
        print(os.path.join(d, entry))
' "$dir" "$DROPLET_INSTALL_NAME" 2>/dev/null || true)"
    if [ -n "$matches" ]; then
        local first
        first="$(printf '%s\n' "$matches" | head -1)"
        printf '%s\n' "$first"
        return 0
    fi
    return 1
}

validate_droplet_bundle() {
    local bundle="$1"
    echo "==> Validating droplet bundle structure, linkage, and manifest: $bundle"
    [ ! -L "$bundle" ] || { echo "ERROR: Bundle path must not be a symlink: $bundle" >&2; return 1; }
    [ -d "$bundle" ] || { echo "ERROR: Bundle directory missing: $bundle" >&2; return 1; }
    [ -f "$bundle/Contents/MacOS/AETHER" ] || { echo "ERROR: Missing executable $bundle/Contents/MacOS/AETHER" >&2; return 1; }
    [ -x "$bundle/Contents/MacOS/AETHER" ] || { echo "ERROR: $bundle/Contents/MacOS/AETHER is not executable" >&2; return 1; }
    [ -f "$bundle/Contents/Info.plist" ] || { echo "ERROR: Missing $bundle/Contents/Info.plist" >&2; return 1; }
    [ -f "$bundle/Contents/Resources/droplet.json" ] || { echo "ERROR: Missing $bundle/Contents/Resources/droplet.json" >&2; return 1; }

    local binary="$bundle/Contents/MacOS/AETHER"

    # Never ship embedded DroppyKit copies or absolute/escaping symlinks
    if [ -e "$bundle/Contents/Frameworks/DroppyKit.framework" ] || [ -e "$bundle/Contents/Frameworks/libDroppyKit.dylib" ]; then
        echo "ERROR: Bundle illegally contains an embedded copy of DroppyKit" >&2
        return 1
    fi

    python3 - "$bundle" <<'PY'
import os, pathlib, sys

bundle_root = os.path.realpath(sys.argv[1])
for dirpath, dirnames, filenames in os.walk(bundle_root, followlinks=False):
    for name in dirnames + filenames:
        full = os.path.join(dirpath, name)
        if os.path.islink(full):
            target = os.readlink(full)
            if os.path.isabs(target):
                raise SystemExit(f"ERROR: Bundle contains absolute symlink: {full} -> {target}")
            resolved = os.path.realpath(full)
            if resolved != bundle_root and not resolved.startswith(bundle_root + os.sep):
                raise SystemExit(f"ERROR: Bundle contains escaping relative symlink: {full} -> {target} ({resolved})")
PY

    # Check Mach-O shared library and architectures (expect universal arm64 + x86_64 unless --arch specified)
    file "$binary" | grep -q "Mach-O.*dynamically linked shared library" \
        || { echo "ERROR: $binary is not a Mach-O dynamically linked shared library" >&2; return 1; }

    local archs
    archs="$(lipo -archs "$binary" 2>/dev/null || true)"
    if [ -n "$BUILD_ARCH" ] && [ "$BUILD_ARCH" != "universal" ]; then
        echo "$archs" | grep -qw "$BUILD_ARCH" \
            || { echo "ERROR: Missing expected architecture $BUILD_ARCH (got: $archs)" >&2; return 1; }
    else
        if ! echo "$archs" | grep -qw "arm64" || ! echo "$archs" | grep -qw "x86_64"; then
            echo "ERROR: Expected universal binary (arm64 x86_64), got: $archs" >&2
            return 1
        fi
    fi

    # Verify resilient DroppyKit framework linkage and absence of SwiftPM static/dylib stubs
    otool -L "$binary" | grep -q "@rpath/AETHER" \
        || { echo "ERROR: Missing @rpath/AETHER install name" >&2; return 1; }
    otool -L "$binary" | grep -q "@rpath/DroppyKit.framework/Versions/A/DroppyKit" \
        || { echo "ERROR: Missing @rpath/DroppyKit.framework/Versions/A/DroppyKit dependency" >&2; return 1; }
    if otool -L "$binary" | grep -q "libDroppyKit\.dylib"; then
        echo "ERROR: Binary illegally links against libDroppyKit.dylib instead of DroppyKit.framework" >&2
        return 1
    fi
    if nm -u "$binary" 2>/dev/null | grep -Eq '9DroppyKit.*vau'; then
        echo "ERROR: Binary imports non-resilient unsafe accessor symbols (9DroppyKit...vau)" >&2
        return 1
    fi

    plutil -lint "$bundle/Contents/Info.plist" >/dev/null \
        || { echo "ERROR: Invalid Info.plist XML" >&2; return 1; }

    python3 - "$bundle/Contents/Resources/droplet.json" "$bundle/Contents/Info.plist" <<'PY'
import json, plistlib, sys

with open(sys.argv[1]) as f:
    manifest = json.load(f)
with open(sys.argv[2], "rb") as f:
    plist = plistlib.load(f)

manifest_id = manifest.get("id")
if manifest_id != "aether" or plist.get("DroppyDropletID") != "aether":
    raise SystemExit("Droplet ID mismatch between manifest and Info.plist")
if plist.get("CFBundleIdentifier") != "app.getdroppy.droplet.aether":
    raise SystemExit(f"Unexpected CFBundleIdentifier: {plist.get('CFBundleIdentifier')}")
if plist.get("CFBundleExecutable") != "AETHER":
    raise SystemExit(f"Unexpected CFBundleExecutable: {plist.get('CFBundleExecutable')}")
if plist.get("NSPrincipalClass") != "AETHERPrincipal":
    raise SystemExit(f"Unexpected NSPrincipalClass: {plist.get('NSPrincipalClass')}")

kit = manifest.get("kit", {})
if int(kit.get("abi", 0)) != int(plist.get("DroppyKitABI", -1)):
    raise SystemExit("DroppyKitABI mismatch between manifest and Info.plist")
if kit.get("minAPI") != plist.get("DroppyKitMinAPI"):
    raise SystemExit("minAPI mismatch between manifest and Info.plist")
if manifest.get("minAppVersion") != plist.get("DroppyMinAppVersion"):
    raise SystemExit("minAppVersion mismatch between manifest and Info.plist")

caps = set(plist.get("DroppyPermissions") or [])
if not {"hud", "clipboard-write"}.issubset(caps):
    raise SystemExit(f"Missing required capabilities in DroppyPermissions: {caps}")
PY

    # If the bundle carries a sealed code signature directory, verify it strictly;
    # unsigned/unsealed bundles from `droppykit build` are accepted by Playground and Droppy approval flow.
    if [ -d "$bundle/Contents/_CodeSignature" ]; then
        codesign --verify --deep --strict "$bundle" >/dev/null 2>&1 \
            || { echo "ERROR: Code signature verification failed on $bundle" >&2; return 1; }
    fi

    echo "==> Bundle structural/linkage validation PASSED ($archs)."
}

perform_rollback() {
    echo "==> Rolling back $DROPLET_INSTALL_NAME in $TARGET_DIR..."
    reject_traversal_or_symlink_target "$TARGET_DIR" "target install directory"
    if [ -L "$PREVIOUS_BACKUP" ]; then
        echo "ERROR: Preserved backup path is a symlink ($PREVIOUS_BACKUP); refusing rollback." >&2
        exit 1
    fi
    if [ ! -d "$PREVIOUS_BACKUP" ]; then
        echo "ERROR: No preserved backup found at $PREVIOUS_BACKUP; cannot roll back." >&2
        exit 1
    fi
    validate_droplet_bundle "$PREVIOUS_BACKUP"

    local stage_restore="$TARGET_DIR/.AETHER.droplet.restore.$$"
    local displaced_current="$TARGET_DIR/.AETHER.droplet.displaced.$$"
    rm -rf "$stage_restore" "$displaced_current"

    cp -R "$PREVIOUS_BACKUP" "$stage_restore"
    validate_droplet_bundle "$stage_restore"

    local existing_bundle=""
    if existing_bundle="$(find_existing_case_insensitive_bundle "$TARGET_DIR")"; then
        if [ -L "$existing_bundle" ]; then
            echo "ERROR: Existing bundle path is a symlink ($existing_bundle); refusing rollback swap." >&2
            rm -rf "$stage_restore"
            exit 1
        fi
        mv "$existing_bundle" "$displaced_current"
    fi

    if mv "$stage_restore" "$INSTALL_BUNDLE"; then
        rm -rf "$displaced_current"
        echo "==> Successfully rolled back $INSTALL_BUNDLE from preserved backup."
    else
        echo "ERROR: Failed to move restored bundle into place; restoring original state..." >&2
        rm -rf "$stage_restore"
        if [ -e "$displaced_current" ] && [ -z "$(find_existing_case_insensitive_bundle "$TARGET_DIR" || true)" ]; then
            mv "$displaced_current" "${existing_bundle:-$INSTALL_BUNDLE}" || true
        fi
        exit 1
    fi
}

stage_clean_distribution() {
    local src_bundle="$1"
    local dist_dir="$2"
    reject_traversal_or_symlink_target "$dist_dir" "distribution staging directory"
    validate_droplet_bundle "$src_bundle"

    local dist_parent
    dist_parent="$(dirname "$dist_dir")"
    mkdir -p "$dist_parent"
    local tmp_stage="${dist_dir}.staging.$$"
    rm -rf "$tmp_stage"
    mkdir -p "$tmp_stage"

    cp -R "$src_bundle" "$tmp_stage/AETHER.droplet"
    cp "$PROJECT_ROOT/docs/README-TESTING.md" "$tmp_stage/README-TESTING.md"
    find "$tmp_stage" -name ".DS_Store" -delete

    validate_droplet_bundle "$tmp_stage/AETHER.droplet"

    python3 - "$tmp_stage" <<'PY'
import pathlib, sys

root = pathlib.Path(sys.argv[1])
entries = sorted(p.name for p in root.iterdir())
assert entries == ["AETHER.droplet", "README-TESTING.md"], f"Unexpected dist root entries: {entries}"

forbidden_names = {"CodeCatch", "CodeCatchCLI", "DroppyKit.framework", ".droppykit", ".build", ".swiftpm", ".git", ".DS_Store"}
for p in root.rglob("*"):
    if p.name in forbidden_names:
        raise SystemExit(f"Forbidden entry inside distribution stage: {p}")
PY

    rm -rf "$dist_dir"
    mv "$tmp_stage" "$dist_dir"
    echo "==> Clean distribution staged at: $dist_dir"
}

if [ "$ROLLBACK_FLAG" = true ]; then
    perform_rollback
    exit 0
fi

ACTIVE_BUNDLE="${PREBUILT_BUNDLE:-$DEFAULT_BUNDLE}"

if [ "$VALIDATE_ONLY" = true ]; then
    validate_droplet_bundle "$ACTIVE_BUNDLE"
    if [ -z "$PREBUILT_BUNDLE" ] && DROPPYKIT_CLI="$(resolve_droppykit_cli)"; then
        VALIDATE_ARGS=()
        [ "$NO_SUBMISSION_VALIDATE" = true ] && VALIDATE_ARGS+=(--no-submission)
        (cd "$DROPLET_PKG" && "$DROPPYKIT_CLI" validate --bundle "$ACTIVE_BUNDLE" "${VALIDATE_ARGS[@]+"${VALIDATE_ARGS[@]}"}")
    fi
    exit 0
fi

if [ -n "$PREBUILT_BUNDLE" ]; then
    echo "==> Using prebuilt droplet bundle: $PREBUILT_BUNDLE"
    validate_droplet_bundle "$ACTIVE_BUNDLE"
else
    if ! DROPPYKIT_CLI="$(resolve_droppykit_cli)"; then
        cat >&2 <<'EOF'
ERROR: Official DroppyKit CLI (`droppykit`) not found.
AETHER no longer compiles or links against unofficial stub declarations.

To build from source:
  1. Ensure Xcode 26+ is installed and active (`sudo xcode-select -s /Applications/Xcode.app`).
  2. Clone https://gitlab.com/droppyformac1/droppykit
  3. Set DROPPYKIT_DIR=/path/to/droppykit (or add <droppykit>/Scripts to PATH).
  4. Re-run ./scripts/build-droplet.sh

Or install a CI-built AETHER.droplet artifact with:
  ./scripts/build-droplet.sh --install --bundle /path/to/AETHER.droplet
EOF
        exit 1
    fi

    echo "==> Official DroppyKit CLI: $DROPPYKIT_CLI"
    "$DROPPYKIT_CLI" version

    if [ -x "$PROJECT_ROOT/scripts/prepare-droplet-icon.sh" ]; then
        "$PROJECT_ROOT/scripts/prepare-droplet-icon.sh"
    fi

    BUILD_ARGS=()
    if [ -n "$BUILD_ARCH" ]; then
        BUILD_ARGS+=(--arch "$BUILD_ARCH")
    fi
    VALIDATE_ARGS=()
    [ "$NO_SUBMISSION_VALIDATE" = true ] && VALIDATE_ARGS+=(--no-submission)

    echo "==> Building AETHER.droplet via official 'droppykit build'..."
    (cd "$DROPLET_PKG" && "$DROPPYKIT_CLI" build "${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}")

    if [ ! -d "$DEFAULT_BUNDLE/Contents/_CodeSignature" ]; then
        strip -x "$DEFAULT_BUNDLE/Contents/MacOS/AETHER"
        find "$DEFAULT_BUNDLE" -name ".DS_Store" -delete
    fi

    echo "==> Validating AETHER.droplet via official 'droppykit validate'..."
    (cd "$DROPLET_PKG" && "$DROPPYKIT_CLI" validate "${VALIDATE_ARGS[@]+"${VALIDATE_ARGS[@]}"}")

    validate_droplet_bundle "$DEFAULT_BUNDLE"
    cp "$PROJECT_ROOT/docs/README-TESTING.md" "$BUILD_DIR/README-TESTING.md"
    echo "==> Official build & validation succeeded at: $DEFAULT_BUNDLE"
fi

if [ -n "$STAGE_DIST_DIR" ]; then
    stage_clean_distribution "$ACTIVE_BUNDLE" "$STAGE_DIST_DIR"
    exit 0
fi

# Safe staged installation (never deletes previous version before new staging succeeds; zero preference weakening)
if [ "$INSTALL_FLAG" = true ]; then
    echo "==> Staging safe installation into $TARGET_DIR..."
    reject_traversal_or_symlink_target "$TARGET_DIR" "target install directory"
    mkdir -p "$TARGET_DIR"

    STAGE_BUNDLE="$TARGET_DIR/.AETHER.droplet.staging.$$"
    BACKUP_TMP="$TARGET_DIR/.AETHER.droplet.backup_tmp.$$"
    rm -rf "$STAGE_BUNDLE" "$BACKUP_TMP"

    cleanup_staging_on_exit() {
        rm -rf "$STAGE_BUNDLE" 2>/dev/null || true
    }
    trap cleanup_staging_on_exit EXIT

    if ! cp -R "$ACTIVE_BUNDLE" "$STAGE_BUNDLE"; then
        echo "ERROR: Failed while copying bundle to staging directory; existing installation untouched." >&2
        exit 1
    fi

    if ! validate_droplet_bundle "$STAGE_BUNDLE"; then
        echo "ERROR: Staged bundle failed post-copy validation; aborting install. Existing installation untouched." >&2
        exit 1
    fi

    if [ -L "$PREVIOUS_BACKUP" ]; then
        echo "ERROR: Existing backup path is a symlink ($PREVIOUS_BACKUP); refusing install." >&2
        exit 1
    fi

    HAD_EXISTING=false
    EXISTING_BUNDLE=""
    if EXISTING_BUNDLE="$(find_existing_case_insensitive_bundle "$TARGET_DIR")"; then
        if [ -L "$EXISTING_BUNDLE" ]; then
            echo "ERROR: Existing droplet entry is a symlink ($EXISTING_BUNDLE); refusing install." >&2
            exit 1
        fi
        HAD_EXISTING=true
        if ! mv "$EXISTING_BUNDLE" "$BACKUP_TMP"; then
            echo "ERROR: Unable to move existing installation aside; aborting install cleanly." >&2
            exit 1
        fi
    fi

    if [ "${AETHER_SIMULATE_INSTALL_SWAP_FAILURE:-}" = "1" ] || ! mv "$STAGE_BUNDLE" "$INSTALL_BUNDLE"; then
        echo "ERROR: Bundle activation swap failed! Executing automatic rollback..." >&2
        if [ "$HAD_EXISTING" = true ] && [ -e "$BACKUP_TMP" ]; then
            mv "$BACKUP_TMP" "${EXISTING_BUNDLE:-$INSTALL_BUNDLE}" && echo "==> Rollback succeeded: previous installation restored." >&2
        fi
        exit 1
    fi

    # Persist recoverable backup of previous working installation
    if [ "$HAD_EXISTING" = true ] && [ -e "$BACKUP_TMP" ]; then
        PREV_ROTATE="$TARGET_DIR/.AETHER.droplet.prev_rotate.$$"
        rm -rf "$PREV_ROTATE"
        if [ -e "$PREVIOUS_BACKUP" ]; then
            mv "$PREVIOUS_BACKUP" "$PREV_ROTATE" || true
        fi
        if mv "$BACKUP_TMP" "$PREVIOUS_BACKUP"; then
            rm -rf "$PREV_ROTATE"
            echo "==> Preserved recoverable previous installation at: $PREVIOUS_BACKUP"
        else
            if [ -e "$PREV_ROTATE" ] && [ ! -e "$PREVIOUS_BACKUP" ]; then
                mv "$PREV_ROTATE" "$PREVIOUS_BACKUP" || true
            fi
        fi
    fi

    echo "==> Installation complete at: $INSTALL_BUNDLE"
    echo "==> User preferences were NOT modified (no defaults written; global Droppy security approvals intact)."
    echo "==> Manual approval required: Open Droppy Settings -> Droplets to review capabilities ('hud', 'clipboard-write') and enable 'AETHER'."
    echo "==> To restore the previous version if needed, run: $0 --rollback"
fi
