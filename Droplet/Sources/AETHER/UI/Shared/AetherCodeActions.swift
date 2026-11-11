// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import AetherEngine
import CodeCatchCore
import DroppyKit
import SwiftUI

/// Context menu actions for a verification code or sign-in link across Shelf Widget and Command Center.
struct AetherCodeContextMenu: View {
    let item: CodeItem
    @ObservedObject var model: AetherAppModel

    var body: some View {
        if model.isUnlocked {
            unlockedActions
        } else {
            Button("Unlock…") { model.unlocked {} }
        }
    }

    @ViewBuilder
    private var unlockedActions: some View {
        if item.link != nil {
            Button("Open Link") { model.open(item) }
            Button("Copy Link") { model.copyLink(item) }
        }
        if !item.isLink {
            Button("Copy Code") { model.copy(item, userInitiated: true) }
        }
        if item.origin == .vault {
            Button(model.search.isPinned(item) ? "Unpin Login" : "Pin Login") {
                model.search.togglePin(item)
            }
        }
        if item.origin != .vault {
            Button("Copy Message") {
                model.hooks.copyToClipboard(item.snippet, item.id)
            }
            Divider()
            if let source = model.source(of: item) {
                Button(source.title) { model.hooks.openURL(source.url) }
                Divider()
            }
            Button("Clear") { model.dismiss(item) }
            if !item.isLink, item.notCodeKey != nil {
                Button("Not a Code") { model.markNotCode(item) }
            }
            if !item.sender.isEmpty {
                Button("Ignore \(item.sender)") { model.ignore(item.sender) }
                if let domain = ServiceIdentity.ignorableDomain(of: item.sender) {
                    Button("Ignore All from \(domain)") { model.ignore(domain) }
                }
            }
        }
    }
}

@MainActor
extension AetherAppModel {
    func boolBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { self.defaults.bool(forKey: key) },
            set: { value in
                self.objectWillChange.send()
                self.defaults.set(value, forKey: key)
            }
        )
    }

    func intBinding(_ key: String) -> Binding<Int> {
        Binding(
            get: { self.defaults.integer(forKey: key) },
            set: { value in
                self.objectWillChange.send()
                self.defaults.set(value, forKey: key)
            }
        )
    }
}
