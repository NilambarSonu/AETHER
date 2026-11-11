// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import CryptoKit
import Foundation

public struct CodeItem: Identifiable, Equatable, Sendable {
    public enum Origin: Sendable, Equatable { case messages, mail, test, vault }
    public enum Kind: Sendable, Equatable {
        case code, signIn, passwordReset

        public var title: String {
            switch self {
            case .code: "Code"
            case .signIn: "Sign-in link"
            case .passwordReset: "Password reset"
            }
        }

        public var symbol: String {
            switch self {
            case .code: "number"
            case .signIn: "link"
            case .passwordReset: "lock.rotation"
            }
        }
    }

    public static let defaultValidity: TimeInterval = 600
    public static let linkValidity: TimeInterval = 1800
    public static let testSourceKey = "test"

    public var id = UUID()
    public let origin: Origin
    public var code: String
    public var link: URL?
    public let service: String
    public let sourceLabel: String
    public let sourceKey: String
    public let accountLabel: String
    public let sender: String
    public let preview: String
    public let snippet: String
    public let received: Date
    public let expires: Date
    public let domain: String?
    public let dismissKey: String
    public var used = false
    public var resetsPassword = false
    public var senderVerified: Bool? = nil
    public var internetMessageID: String? = nil
    public var webURL: URL? = nil
    public var notCodeKey: String? = nil

    public init(
        id: UUID = UUID(),
        origin: Origin,
        code: String,
        link: URL?,
        service: String,
        sourceLabel: String,
        sourceKey: String,
        accountLabel: String,
        sender: String,
        preview: String,
        snippet: String,
        received: Date,
        expires: Date,
        domain: String?,
        dismissKey: String,
        used: Bool = false,
        resetsPassword: Bool = false,
        senderVerified: Bool? = nil,
        internetMessageID: String? = nil,
        webURL: URL? = nil,
        notCodeKey: String? = nil
    ) {
        self.id = id
        self.origin = origin
        self.code = code
        self.link = link
        self.service = service
        self.sourceLabel = sourceLabel
        self.sourceKey = sourceKey
        self.accountLabel = accountLabel
        self.sender = sender
        self.preview = preview
        self.snippet = snippet
        self.received = received
        self.expires = expires
        self.domain = domain
        self.dismissKey = dismissKey
        self.used = used
        self.resetsPassword = resetsPassword
        self.senderVerified = senderVerified
        self.internetMessageID = internetMessageID
        self.webURL = webURL
        self.notCodeKey = notCodeKey
    }

    public var lifetime: TimeInterval { expires.timeIntervalSince(received) }
    public var countdown: TimeInterval { min(lifetime, 600) }
    public func showsCountdown(now: Date) -> Bool { expires.timeIntervalSince(now) <= countdown }
    public var isLink: Bool { code.isEmpty }
    public var kind: Kind { !isLink ? .code : resetsPassword ? .passwordReset : .signIn }
    public var linkSetting: String { resetsPassword ? AetherPrefs.resetLinks : AetherPrefs.signInLinks }
    public var destination: URL? { link.map(LinkWrapper.destination) }

    public var linkNotice: (text: String, warns: Bool)? {
        guard let host = destination?.host else { return nil }
        let target = ServiceIdentity.registrable(host)
        guard target != domain else { return nil }
        let check = "Open it only if you trust this site."
        guard let domain else { return ("AETHER can't verify who sent this message. \(check)", true) }
        return senderVerified == true
            ? ("This message is from \(domain) and links to \(target). The sender is verified.", false)
            : ("This message is from \(domain), but the link goes to \(target). \(check)", true)
    }

    public var copyValue: String { isLink ? link?.absoluteString ?? "" : code }

    public func isRecent(at date: Date) -> Bool {
        date.timeIntervalSince(received) < 600 && date < expires
    }

    public func shouldAnnounce(at date: Date) -> Bool {
        date.timeIntervalSince(received) < 180 && date < expires
    }
}

public extension CodeItem {
    init(_ message: IncomingMessage, code: String?, link: URL?, resetsPassword: Bool = false) {
        let body = message.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let service = message.service
        self.init(
            origin: message.sourceKey == Self.testSourceKey ? .test : message.isMail ? .mail : .messages,
            code: code ?? "",
            link: link,
            service: service,
            sourceLabel: message.sourceLabel,
            sourceKey: message.sourceKey,
            accountLabel: message.sourceLabel,
            sender: message.senderID,
            preview: String((message.subject.flatMap { $0.isEmpty ? nil : $0 } ?? body).prefix(160)),
            snippet: String(((message.subject.map { $0 + " — " } ?? "") + body).prefix(280)),
            received: message.date,
            expires: message.date.addingTimeInterval(
                CodeExtractor.validity(in: message.fullText)
                    ?? (code == nil ? Self.linkValidity : Self.defaultValidity)),
            domain: message.senderVerified == false
                ? nil
                : ServiceIdentity.domain(senderAddress: message.senderID, isMail: message.isMail, text: message.fullText, service: service),
            dismissKey: message.dismissKey,
            resetsPassword: resetsPassword,
            senderVerified: message.senderVerified,
            internetMessageID: message.internetMessageID,
            webURL: message.webURL
        )
    }

    init?(_ vault: VaultCode, at date: Date) {
        guard let totp = vault.totp else { return nil }
        let start = totp.periodStart(date)
        let context = vault.username ?? vault.domain ?? ""
        let digest = Array(SHA256.hash(data: Data(vault.id.utf8)).prefix(16))
        let stableID = digest.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
        self.init(
            id: UUID(uuidString: vault.id) ?? stableID,
            origin: .vault,
            code: totp.code(at: date),
            link: nil,
            service: vault.name,
            sourceLabel: "Bitwarden",
            sourceKey: vault.id,
            accountLabel: context,
            sender: "",
            preview: context,
            snippet: [vault.name, context].joined(separator: " — "),
            received: start,
            expires: start.addingTimeInterval(totp.period),
            domain: vault.domain,
            dismissKey: "vault:\(vault.id)"
        )
    }

    var origination: String {
        let from = sender.isEmpty || sender == service || sender.contains("@") ? nil : sender
        return [sourceLabel, from].compactMap { $0 }.joined(separator: " · ")
    }

    func remaining(now: Date) -> String {
        let s = Int(max(0, expires.timeIntervalSince(now)).rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    func age(now: Date) -> String {
        let s = now.timeIntervalSince(received)
        return s < 60 ? "now" : s < 3600 ? "\(Int(s / 60)) min" : received.formatted(date: .omitted, time: .shortened)
    }
}
