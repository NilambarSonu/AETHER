// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

// Not named main.swift so Swift @main works cleanly.

import AETHER
import DroppyKit
import DroppyKitHarness

@main
struct AETHERHarness: DropletHarnessApp {
    static func makeDroplet() -> any Droplet {
        AetherDroplet()
    }
}
