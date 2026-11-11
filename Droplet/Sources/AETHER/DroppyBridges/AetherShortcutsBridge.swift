// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import AppKit
import DroppyKit

/// Registers global shortcuts through Droppy's `host.shortcuts` service (`global-shortcuts`).
@MainActor
final class AetherShortcutsBridge {
    static let copyLatestID = "copy-latest"
    static let openShelfID = "open-codes"

    private var host: DropletHost?

    /// Default `⌃⌥⌘C` built with AppKit modifier flags per DroppyKit specification.
    static let defaultCopyShortcut = DropletKeyboardShortcut(
        keyCode: 8,
        modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
    )

    /// Default `⌃⌥⌘F` built with AppKit modifier flags per DroppyKit specification.
    static let defaultOpenShortcut = DropletKeyboardShortcut(
        keyCode: 3,
        modifiers: NSEvent.ModifierFlags([.control, .option, .command]).rawValue
    )

    func sync(host: DropletHost, model: AetherAppModel) {
        self.host = host
        guard model.isOn(AetherPrefs.hotkeys) else {
            host.shortcuts.unregister(id: Self.copyLatestID)
            host.shortcuts.unregister(id: Self.openShelfID)
            return
        }
        host.shortcuts.register(
            id: Self.copyLatestID,
            title: "Copy latest verification code",
            defaultShortcut: Self.defaultCopyShortcut
        ) { [weak model] in
            model?.copyLatest(userInitiated: true)
        }
        host.shortcuts.register(
            id: Self.openShelfID,
            title: "Show verification codes in Droppy",
            defaultShortcut: Self.defaultOpenShortcut
        ) { [weak self] in
            _ = self?.host?.shelf.open(revealing: AetherDroplet.widgetID)
        }
    }

    func stop() {
        host?.shortcuts.unregister(id: Self.copyLatestID)
        host?.shortcuts.unregister(id: Self.openShelfID)
        host = nil
    }
}
