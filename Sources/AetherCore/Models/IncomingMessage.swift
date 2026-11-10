import CodeCatchCore
import Foundation

/// A message from any source, before code extraction.
public struct IncomingMessage: Sendable {
    public var text: String
    public var subject: String?
    public var senderName: String
    public var senderID: String
    public var sourceKey: String
    public var sourceLabel: String
    public var date: Date
    public var isMail: Bool
    public var links: [MailLink]
    /// Source identifier only; never a code or a sign-in token.
    public var messageID: String?
    /// The mail server's verdict on the From domain; nil when it left none.
    public var senderVerified: Bool?
    /// The Message-ID header, for opening the email in Mail.
    public var internetMessageID: String?
    /// The email's own page at its provider (Gmail, Outlook on the web).
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

    /// Subject and body: what codes and service names are read from.
    public var fullText: String { [subject, text].compactMap { $0 }.joined(separator: "\n") }
    public var dismissKey: String { "message:\(sourceKey)|\(messageID ?? "\(senderID.lowercased())|\(date.timeIntervalSince1970)")" }
    public var service: String { ServiceIdentity.name(senderName: senderName, senderAddress: senderID, isMail: isMail, text: fullText) }
}
