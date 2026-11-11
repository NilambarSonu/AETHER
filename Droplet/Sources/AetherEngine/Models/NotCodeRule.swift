// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import CryptoKit
import Foundation

public struct NotCodeRule: Codable, Equatable, Identifiable, Sendable {
    public let key: String
    public let sender: String
    public let added: Date
    public var id: String { key }

    public init(key: String, sender: String, added: Date) {
        self.key = key
        self.sender = sender
        self.added = added
    }
}

public extension CodeItem {
    static func notCodeKey(for detection: CodeExtractor.Detection, from message: IncomingMessage) -> String {
        let shape = detection.context.replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        let sender =
            message.isMail
            ? ServiceIdentity.registrable(String(message.senderID.split(separator: "@").last ?? ""))
            : message.senderID.lowercased()
        return SHA256.hash(data: Data((sender + "\n" + shape).utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
