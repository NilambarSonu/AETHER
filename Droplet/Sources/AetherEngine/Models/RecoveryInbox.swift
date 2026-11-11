// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Combine
import Foundation

@MainActor
public final class RecoveryInbox: ObservableObject {
    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let message: IncomingMessage
        public let truncated: Bool

        public init(id: UUID, message: IncomingMessage, truncated: Bool) {
            self.id = id
            self.message = message
            self.truncated = truncated
        }
    }

    public static let lifetime: TimeInterval = 30 * 60
    @Published public private(set) var entries: [Entry] = []
    public var onRemove: (Set<UUID>) -> Void = { _ in }

    public init() {}

    public func record(_ message: IncomingMessage, at date: Date = Date()) {
        prune(at: date)
        guard message.isMail, (0..<Self.lifetime).contains(date.timeIntervalSince(message.date)) else { return }
        var bounded = message
        bounded.text = String(message.text.prefix(16_000))
        bounded.subject = message.subject.map { String($0.prefix(1_000)) }
        bounded.links = []
        guard CodeExtractor.hasCodeContext(in: bounded.fullText) else { return }
        let id = entries.first { $0.message.dismissKey == message.dismissKey }?.id ?? UUID()
        entries.removeAll { $0.id == id }
        entries.append(Entry(id: id, message: bounded, truncated: bounded.text != message.text || bounded.subject != message.subject))
        entries.sort { $0.message.date > $1.message.date }
        let overflow = Set(entries.dropFirst(20).map(\.id))
        remove { overflow.contains($0.id) }
    }

    public func prune(at date: Date = Date()) {
        remove { !(0..<Self.lifetime).contains(date.timeIntervalSince($0.message.date)) }
    }

    public func removeAll() { remove { _ in true } }
    public func remove(ignored entry: String) { remove { ServiceIdentity.ignores(entry, sender: $0.message.senderID) } }
    public func remove(messageKey: String) { remove { $0.message.dismissKey == messageKey } }
    public func retainSources(_ keys: Set<String>) { remove { !keys.contains($0.message.sourceKey) } }

    private func remove(where predicate: (Entry) -> Bool) {
        let ids = Set(entries.filter(predicate).map(\.id))
        guard !ids.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        onRemove(ids)
    }
}
