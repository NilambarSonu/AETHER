// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation

/// A message from any source, before or after off-main-thread code/link extraction.
public struct IncomingMessage: Sendable {
    public struct PrecomputedExtraction: Sendable, Equatable {
        public let detection: CodeExtractor.Detection?
        public let linkURL: URL?
        public let linkResetsPassword: Bool
        public let hasActionLink: Bool
        public let validitySeconds: TimeInterval?

        public init(
            detection: CodeExtractor.Detection?,
            linkURL: URL?,
            linkResetsPassword: Bool,
            hasActionLink: Bool,
            validitySeconds: TimeInterval?
        ) {
            self.detection = detection
            self.linkURL = linkURL
            self.linkResetsPassword = linkResetsPassword
            self.hasActionLink = hasActionLink
            self.validitySeconds = validitySeconds
        }

        public static func compute(for message: IncomingMessage) -> PrecomputedExtraction {
            let full = message.fullText
            let detection = CodeExtractor.detect(in: full)
            let foundLink = message.isMail ? SignInLink.find(in: message.links, subject: message.subject ?? "") : nil
            return PrecomputedExtraction(
                detection: detection,
                linkURL: foundLink?.url,
                linkResetsPassword: foundLink?.kind == .passwordReset,
                hasActionLink: foundLink != nil,
                validitySeconds: CodeExtractor.validity(in: full)
            )
        }
    }

    public static let mailReadLimit = 262_144

    public var text: String
    public var subject: String?
    public var senderName: String
    public var senderID: String
    public var sourceKey: String
    public var sourceLabel: String
    public var date: Date
    public var isMail: Bool
    public var links: [MailLink]
    public var messageID: String?
    public var senderVerified: Bool?
    public var internetMessageID: String?
    public var webURL: URL?
    public var precomputed: PrecomputedExtraction? = nil

    public init(
        text: String,
        subject: String? = nil,
        senderName: String,
        senderID: String,
        sourceKey: String,
        sourceLabel: String,
        date: Date,
        isMail: Bool,
        links: [MailLink] = [],
        messageID: String? = nil,
        senderVerified: Bool? = nil,
        internetMessageID: String? = nil,
        webURL: URL? = nil,
        precomputed: PrecomputedExtraction? = nil
    ) {
        self.text = text
        self.subject = subject
        self.senderName = senderName
        self.senderID = senderID
        self.sourceKey = sourceKey
        self.sourceLabel = sourceLabel
        self.date = date
        self.isMail = isMail
        self.links = links
        self.messageID = messageID
        self.senderVerified = senderVerified
        self.internetMessageID = internetMessageID
        self.webURL = webURL
        self.precomputed = precomputed
    }

    public init(mail raw: Data, receiver: MIME.Receiver? = nil, account: MailAccount, date: Date?, messageID: String?, webURL: URL? = nil) {
        let m = MIME.parse(raw.prefix(Self.mailReadLimit), receiver: receiver)
        let msg = IncomingMessage(
            text: m.text,
            subject: m.subject,
            senderName: m.fromName,
            senderID: m.fromAddress,
            sourceKey: account.id.uuidString,
            sourceLabel: account.label,
            date: date ?? Date(),
            isMail: true,
            links: m.links,
            messageID: messageID,
            senderVerified: m.senderVerified,
            internetMessageID: m.messageID,
            webURL: webURL
        )
        self = msg
        self.precomputed = PrecomputedExtraction.compute(for: msg)
    }

    public func withPrecomputedExtraction() -> IncomingMessage {
        guard precomputed == nil else { return self }
        var copy = self
        copy.precomputed = PrecomputedExtraction.compute(for: self)
        return copy
    }

    public var fullText: String { [subject, text].compactMap { $0 }.joined(separator: "\n") }
    public var dismissKey: String { "message:\(sourceKey)|\(messageID ?? "\(senderID.lowercased())|\(date.timeIntervalSince1970)")" }
    public var service: String { ServiceIdentity.name(senderName: senderName, senderAddress: senderID, isMail: isMail, text: fullText) }
}
