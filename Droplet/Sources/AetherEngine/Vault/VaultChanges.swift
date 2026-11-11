// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation

public struct VaultChanges: Sendable {
    public struct Entry: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let account: String

        public init(_ code: VaultCode) {
            id = code.id
            name = code.name
            account = code.username ?? code.domain ?? ""
        }
    }

    public let added: [Entry]
    public let changed: [Entry]
    public let removed: [Entry]
    public var isEmpty: Bool { added.isEmpty && changed.isEmpty && removed.isEmpty }

    public init(before: [VaultCode], after: [VaultCode]) {
        let old = before.reduce(into: [String: VaultCode]()) { $0[$1.id] = $1 }
        let new = after.reduce(into: [String: VaultCode]()) { $0[$1.id] = $1 }
        added = after.filter { old[$0.id] == nil }.map(Entry.init)
        changed = after.filter { old[$0.id] != nil && old[$0.id] != $0 }.map(Entry.init)
        removed = before.filter { new[$0.id] == nil }.map(Entry.init)
    }
}
