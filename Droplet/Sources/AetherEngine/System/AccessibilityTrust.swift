// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import ApplicationServices

public enum AccessibilityTrust {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    private static var asked = false

    public static func requestTrust(force: Bool = false) {
        guard force || !asked else { return }
        asked = true
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }
}
