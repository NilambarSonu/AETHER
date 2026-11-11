// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AppKit
import Foundation

/// Copies sensitive OTP codes, links, and recovery selections using host-only concealed
/// pasteboard types so Universal Clipboard and clipboard managers ignore them.
@MainActor
public final class AetherClipboard {
    private let defaults: UserDefaults
    private var copied: (id: UUID?, change: Int)?
    private var clearWorkItem: DispatchWorkItem?
    private let clearDelay: TimeInterval

    public init(defaults: UserDefaults, clearDelay: TimeInterval = 90) {
        self.defaults = defaults
        self.clearDelay = clearDelay
    }

    public func copy(_ text: String, id: UUID? = nil, pasteboard pb: NSPasteboard = .general) {
        clearWorkItem?.cancel()
        clearWorkItem = nil
        pb.prepareForNewContents(with: .currentHostOnly)
        pb.setString(text, forType: .string)
        pb.setString("", forType: .init("org.nspasteboard.ConcealedType"))
        pb.setString("", forType: .init("org.nspasteboard.TransientType"))
        let change = pb.changeCount
        copied = (id, change)
        guard defaults.bool(forKey: AetherPrefs.clearClipboard) else { return }
        let work = DispatchWorkItem { [weak self, weak pb] in
            guard let self, let pb, pb.changeCount == change else { return }
            pb.clearContents()
            self.clearWorkItem = nil
        }
        clearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay, execute: work)
    }

    public func clearIfOurs(ids: Set<UUID>? = nil, pasteboard pb: NSPasteboard = .general) {
        if let ids, copied?.id.map(ids.contains) != true { return }
        if copied?.change == pb.changeCount {
            clearWorkItem?.cancel()
            clearWorkItem = nil
            pb.clearContents()
        }
    }

    public func clearIfHolds(_ item: CodeItem, pasteboard pb: NSPasteboard = .general) {
        if holds(item, pasteboard: pb) {
            clearWorkItem?.cancel()
            clearWorkItem = nil
            pb.clearContents()
        }
    }

    public func holds(_ id: UUID, pasteboard pb: NSPasteboard = .general) -> Bool {
        copied?.id == id && copied?.change == pb.changeCount
    }

    public func holds(_ item: CodeItem, pasteboard pb: NSPasteboard = .general) -> Bool {
        holds(item.id, pasteboard: pb) && pb.string(forType: .string) == item.copyValue
    }

    public func stop() {
        clearWorkItem?.cancel()
        clearWorkItem = nil
    }
}
