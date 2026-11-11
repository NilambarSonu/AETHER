#!/bin/bash
# Generates Droplet/.droppykit/AETHER.icon directly from Droplet/Assets/aether.png
# using DroppyKit's placeholder-compatible single-layer Icon Composer schema so
# both `actool` and `droppykit lint --strict` render AETHER's artwork cleanly.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_PNG="$PROJECT_ROOT/Droplet/Assets/aether.png"
ICON_DIR="$PROJECT_ROOT/Droplet/.droppykit/AETHER.icon"
ASSETS_OUT="$ICON_DIR/Assets"

if [ ! -f "$ASSET_PNG" ]; then
    echo "WARNING: $ASSET_PNG not found; skipping custom icon preparation." >&2
    exit 0
fi

rm -rf "$ICON_DIR"
mkdir -p "$ASSETS_OUT"

# Compact 256x256 PNG (~23 KB) renders sharply inside Finder/Droppy squircles without inflating bundle size.
sips -z 256 256 "$ASSET_PNG" --out "$ASSETS_OUT/mark.png" >/dev/null

cat > "$ICON_DIR/icon.json" <<'EOF'
{
  "fill-specializations" : [
    {
      "value" : {
        "linear-gradient" : [
          "display-p3:1.00000,0.95294,0.97255,1.00000",
          "display-p3:0.92941,0.91373,1.00000,1.00000"
        ]
      }
    },
    {
      "appearance" : "dark",
      "value" : {
        "linear-gradient" : [
          "display-p3:0.17255,0.14510,0.22745,1.00000",
          "display-p3:0.08627,0.09020,0.13333,1.00000"
        ]
      }
    }
  ],
  "groups" : [
    {
      "layers" : [
        {
          "hidden" : false,
          "image-name" : "mark.png",
          "name" : "placeholder",
          "position" : {
            "scale" : 0.96,
            "translation-in-points" : [ 0, 0 ]
          }
        }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.45 },
      "translucency" : { "enabled" : true, "value" : 0.45 }
    }
  ],
  "supported-platforms" : {
    "circles" : [ "watchOS" ],
    "squares" : "shared"
  }
}
EOF
echo "==> Prepared $ICON_DIR from $ASSET_PNG"
