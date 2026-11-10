#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_DIR="$PROJECT_ROOT/Droplet/.build"
MODULE_DIR="$BUILD_DIR/DroppyKitModule"
DROPLET_BUNDLE="$BUILD_DIR/Aether.droplet"

INSTALL_FLAG=false
for arg in "$@"; do
    if [ "$arg" = "--install" ]; then
        INSTALL_FLAG=true
    fi
done

echo "==> Building Aether.droplet for DroppyKit..."

mkdir -p "$BUILD_DIR"
mkdir -p "$MODULE_DIR"
mkdir -p "$DROPLET_BUNDLE/Contents/MacOS"
mkdir -p "$DROPLET_BUNDLE/Contents/Resources"

# 1. Resolve or assemble DroppyKit framework
if [ -n "${DROPPYKIT_FRAMEWORKS_DIR:-}" ] && [ -d "$DROPPYKIT_FRAMEWORKS_DIR/DroppyKit.framework" ]; then
    FRAMEWORKS_DIR="$DROPPYKIT_FRAMEWORKS_DIR"
    echo "==> Using DroppyKit framework from DROPPYKIT_FRAMEWORKS_DIR: $FRAMEWORKS_DIR"
elif [ "${SIMULATE_CLEAN_CI:-}" != "1" ] && [ -d "/Applications/Droppy.app/Contents/Frameworks/DroppyKit.framework" ]; then
    FRAMEWORKS_DIR="/Applications/Droppy.app/Contents/Frameworks"
    echo "==> Using installed DroppyKit framework from: $FRAMEWORKS_DIR"
else
    # CI or clean system without Droppy installed: assemble reproducible SDK framework skeleton
    echo "==> Droppy.app not detected. Assembling SDK framework skeleton for link resolution..."
    FRAMEWORKS_DIR="$BUILD_DIR/Frameworks"
    FRAMEWORK_A="$FRAMEWORKS_DIR/DroppyKit.framework/Versions/A"
    mkdir -p "$FRAMEWORK_A"
    xcrun swiftc -emit-library \
        -enable-library-evolution \
        -module-name DroppyKit \
        -o "$FRAMEWORK_A/DroppyKit" \
        -Xlinker -install_name -Xlinker "@rpath/DroppyKit.framework/Versions/A/DroppyKit" \
        "$PROJECT_ROOT/Droplet/DroppyKitInterface.swift" \
        -target arm64-apple-macos15.0
    ln -sfn A "$FRAMEWORKS_DIR/DroppyKit.framework/Versions/Current"
    ln -sfn Versions/Current/DroppyKit "$FRAMEWORKS_DIR/DroppyKit.framework/DroppyKit"
fi

# 2. Generate DroppyKit.swiftmodule from clean interface with library evolution enabled
echo "==> Generating DroppyKit.swiftmodule..."
xcrun swiftc -emit-module \
    -enable-library-evolution \
    -module-name DroppyKit \
    -o "$MODULE_DIR/DroppyKit.swiftmodule" \
    "$PROJECT_ROOT/Droplet/DroppyKitInterface.swift" \
    -target arm64-apple-macos15.0

# 3. Compile Aether droplet dynamic library
echo "==> Compiling Aether droplet Mach-O dynamic library..."
xcrun swiftc -emit-library \
    -enable-library-evolution \
    -module-name Aether \
    -o "$DROPLET_BUNDLE/Contents/MacOS/Aether" \
    -target arm64-apple-macos15.0 \
    -I "$MODULE_DIR" \
    -F "$FRAMEWORKS_DIR" \
    -framework DroppyKit \
    -Xlinker -install_name -Xlinker @rpath/Aether \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -Xlinker -rpath -Xlinker /usr/lib/swift \
    "$PROJECT_ROOT/Sources/AetherCore/Protocol/AetherOTPPayload.swift" \
    "$PROJECT_ROOT/Sources/AetherCore/Protocol/AetherOTPAcknowledgment.swift" \
    "$PROJECT_ROOT/Sources/AetherCore/Protocol/AetherProtocolError.swift" \
    "$PROJECT_ROOT/Sources/AetherCore/Codec/AetherFrameCodec.swift" \
    "$PROJECT_ROOT/Sources/AetherCore/Codec/AetherFrameDecoder.swift" \
    "$PROJECT_ROOT/Sources/AetherCore/Transport/AetherHandshake.swift" \
    "$PROJECT_ROOT/Sources/AetherCore/Transport/AetherSocketEndpoint.swift" \
    "$PROJECT_ROOT/Sources/AetherCore/Transport/AetherTransportError.swift" \
    "$PROJECT_ROOT/Sources/AetherCore/Transport/AetherPeerAuthentication.swift" \
    "$PROJECT_ROOT/Sources/AetherCore/Transport/AetherIPCClientTransport.swift" \
    "$PROJECT_ROOT/Droplet/Aether/Sources/AetherDroplet.swift"

# 4. Copy Bundle Resources
echo "==> Packaging bundle resources..."
cp "$PROJECT_ROOT/Droplet/Aether/Info.plist" "$DROPLET_BUNDLE/Contents/Info.plist"
cp "$PROJECT_ROOT/Droplet/Aether/droplet.json" "$DROPLET_BUNDLE/Contents/Resources/droplet.json"

# 5. Ad-hoc Codesign (Note: For local testing and CI verification; release distribution requires Developer ID)
echo "==> Codesigning Aether.droplet..."
codesign -s - -f --deep "$DROPLET_BUNDLE"

echo "==> Aether.droplet successfully built at $DROPLET_BUNDLE"

# 6. Install if requested
if [ "$INSTALL_FLAG" = true ]; then
    TARGET_DIR="$HOME/Library/Application Support/Droppy/Droplets/aether"
    echo "==> Installing to $TARGET_DIR..."
    mkdir -p "$TARGET_DIR"
    rm -rf "$TARGET_DIR/Aether.droplet"
    cp -R "$DROPLET_BUNDLE" "$TARGET_DIR/Aether.droplet"

    echo "==> Enabling droplet in Droppy preferences..."
    defaults write iordv.Droppy "droplet.aether.enabled" -bool true
    defaults write iordv.Droppy "droplet.approvals.askBeforeRunning" -bool false

    echo "==> Successfully installed and enabled Aether.droplet!"
fi
