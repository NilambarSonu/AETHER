// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import Foundation

/// Opt-in key-by-key OTP auto-typing into focused external fields (supports split digit inputs).
public enum AutoTyper {
    private static let digitKeys: [Character: CGKeyCode] = [
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21,
        "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    ]

    public static let queue = DispatchQueue(label: "app.getdroppy.droplet.aether.key-typer", qos: .userInteractive)

    @MainActor
    public static func canType(isHostActive: Bool? = nil) -> Bool {
        AccessibilityTrust.isTrusted && !(isHostActive ?? NSApp.isActive)
    }

    public static func type(
        _ text: String,
        allowed: @escaping @MainActor () -> Bool,
        modifiersHeld: @escaping () -> Bool = {
            !CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        },
        press: @escaping (Character) -> Void = press
    ) {
        queue.async {
            for _ in 0..<50 where modifiersHeld() { usleep(20_000) }
            guard !modifiersHeld(), DispatchQueue.main.sync(execute: { MainActor.assumeIsolated(allowed) }) else { return }
            for ch in text {
                press(ch)
                usleep(15_000)
            }
        }
    }

    public static func press(_ ch: Character) {
        let source = CGEventSource(stateID: .hidSystemState)
        var units = Array(String(ch).utf16)
        for down in [true, false] {
            // droppykit-lint: allow synthetic-input: Opt-in user-enabled OTP auto-type into focused external inputs gated on Accessibility trust
            let e = CGEvent(keyboardEventSource: source, virtualKey: digitKeys[ch] ?? 0, keyDown: down)
            e?.flags = []
            e?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            // droppykit-lint: allow synthetic-input: Opt-in user-enabled OTP auto-type into focused external inputs gated on Accessibility trust
            e?.post(tap: .cghidEventTap)
        }
    }
}
