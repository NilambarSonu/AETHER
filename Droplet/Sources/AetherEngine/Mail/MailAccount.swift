// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation

public struct MailAccount: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var label: String
    public var host: String
    public var port = 993
    public var user: String
    public var enabled = true
    public var signedIn: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, label, host, port, user, enabled
        case signedIn = "googleSignIn"
    }

    public init(
        id: UUID = UUID(),
        label: String,
        host: String,
        port: Int = 993,
        user: String,
        enabled: Bool = true,
        signedIn: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.host = host
        self.port = port
        self.user = user
        self.enabled = enabled
        self.signedIn = signedIn
    }

    public var secretKey: String { "\(user.lowercased())@\(host.lowercased())" }
    public var refreshTokenKey: String { secretKey + "#google" }
    public var usesSignIn: Bool { signedIn == true }
    public var isGmail: Bool { [Self.gmailHost, "imap.googlemail.com"].contains(host.lowercased()) }
    public var isOutlook: Bool { [Self.outlookHost, "imap-mail.outlook.com"].contains(host.lowercased()) }
    public var provider: MailOAuth? { isGmail ? .google : isOutlook ? .microsoft : nil }
    public var iconDomain: String { isGmail ? "gmail.com" : isOutlook ? "outlook.com" : ServiceIdentity.registrable(host) }

    public func password(in secrets: AetherSecretStore = .keychain) -> String? {
        secrets.get(secretKey)
    }

    public func hasCredential(in secrets: AetherSecretStore = .keychain) -> Bool {
        usesSignIn ? secrets.get(refreshTokenKey) != nil : secrets.get(secretKey) != nil
    }

    public static let gmailHost = "imap.gmail.com"
    public static let outlookHost = "outlook.office365.com"
    public static let appPasswordHelp = URL(string: "https://support.google.com/accounts/answer/185833")!

    public static func guess(for user: String) -> MailAccount {
        let domain = user.split(separator: "@").last.map(String.init)?.lowercased() ?? ""
        let gmail = ["gmail.com", "googlemail.com"].contains(domain)
        let outlook = ["outlook.com", "hotmail.com", "live.com", "msn.com"].contains(domain)
        return MailAccount(
            label: gmail ? "Gmail" : outlook ? "Outlook" : (domain.split(separator: ".").first.map { $0.capitalized } ?? domain),
            host: gmail ? gmailHost : outlook ? outlookHost : "imap.\(domain)",
            user: user
        )
    }

    private static let storeKey = "mailAccounts"

    public static func load(from defaults: UserDefaults) -> [MailAccount] {
        guard let data = defaults.data(forKey: storeKey),
            let accounts = try? JSONDecoder().decode([MailAccount].self, from: data)
        else { return [] }
        return accounts
    }

    public static func save(_ accounts: [MailAccount], in defaults: UserDefaults) {
        defaults.set(try? JSONEncoder().encode(accounts), forKey: storeKey)
    }
}
