import AetherCore
import CodeCatchCore
import Foundation

extension IncomingMessage {
    /// How much of an email is read: codes live in the text, not attachments.
    static let mailReadLimit = 262_144

    /// An email from a mail account, parsed from the start of its MIME source. `receiver` is set only
    /// when the provider's own API returned it, so its Authentication-Results can be trusted.
    init(mail raw: Data, receiver: MIME.Receiver? = nil, account: MailAccount, date: Date?, messageID: String?, webURL: URL? = nil) {
        let m = MIME.parse(raw.prefix(Self.mailReadLimit), receiver: receiver)
        self.init(
            text: m.text, subject: m.subject, senderName: m.fromName, senderID: m.fromAddress,
            sourceKey: account.id.uuidString, sourceLabel: account.label, date: date ?? Date(), isMail: true,
            links: m.links, messageID: messageID, senderVerified: m.senderVerified, internetMessageID: m.messageID, webURL: webURL)
    }
}

