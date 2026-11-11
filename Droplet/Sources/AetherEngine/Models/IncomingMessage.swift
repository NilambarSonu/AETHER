// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation

/// A message from any source, before code extraction.
public struct IncomingMessage: Sendable {
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
        webURL: URL? = nil
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
    }

    public init(mail raw: Data, receiver: MIME.Receiver? = nil, account: MailAccount, date: Date?, messageID: String?, webURL: URL? = nil) {
        let m = MIME.parse(raw.prefix(Self.mailReadLimit), receiver: receiver)
        self.init(
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
    }

    public var fullText: String { [subject, text].compactMap { $0 }.joined(separator: "\n") }
    public var dismissKey: String { "message:\(sourceKey)|\(messageID ?? "\(senderID.lowercased())|\(date.timeIntervalSince1970)")" }
    public var service: String { ServiceIdentity.name(senderName: senderName, senderAddress: senderID, isMail: isMail, text: fullText) }
}
