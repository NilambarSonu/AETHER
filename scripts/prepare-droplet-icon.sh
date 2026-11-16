#!/bin/bash
# Generates AETHER's liquid glass continuous squircle icon and compiles
# both Droplet/.droppykit/AETHER.icon and Droplet/.droppykit/AETHER.icns
# ensuring transparent corners outside the squircle and pixel-perfect
# border radius matching the Settings header icon across all surfaces.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

swift "$PROJECT_ROOT/scripts/generate-aether-icon.swift"
