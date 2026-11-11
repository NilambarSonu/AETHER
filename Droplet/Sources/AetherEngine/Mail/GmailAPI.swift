// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation

public struct GmailAPI: MailAPI {
    public let auth: MailAPIAuth

    public init(auth: MailAPIAuth) { self.auth = auth }
    public init(account: MailAccount, secrets: AetherSecretStore = .keychain) {
        self.init(auth: .saved(.google, tokenKey: account.refreshTokenKey, secrets: secrets))
    }

    public func emailAddress() async throws -> String {
        guard let email = try await get("profile")["emailAddress"] as? String else { throw MailAPIError.http(200, "no address") }
        return email
    }

    public func cursor() async throws -> String {
        try await get("profile")["historyId"].map { "\($0)" } ?? ""
    }

    public func inbox(since date: Date, limit: Int) async throws -> [String] {
        let json = try await get("messages", ["q": "in:inbox after:\(Int(date.timeIntervalSince1970))", "maxResults": "\(limit)"])
        return ((json["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }.reversed()
    }

    public func added(since historyID: String) async throws -> (ids: [String], cursor: String) {
        var ids: [String] = []
        var latest = historyID
        var page: String?
        repeat {
            var query = ["startHistoryId": historyID, "historyTypes": "messageAdded", "labelId": "INBOX"]
            query["pageToken"] = page
            let json: [String: Any]
            do { json = try await get("history", query) } catch MailAPIError.gone { throw MailAPIError.cursorExpired }
            for record in (json["history"] as? [[String: Any]]) ?? [] {
                for added in (record["messagesAdded"] as? [[String: Any]]) ?? [] {
                    if let id = (added["message"] as? [String: Any])?["id"] as? String, !ids.contains(id) { ids.append(id) }
                }
            }
            latest = json["historyId"].map { "\($0)" } ?? latest
            page = json["nextPageToken"] as? String
        } while page != nil
        return (ids, latest)
    }

    public func message(_ id: String, account: MailAccount) async throws -> IncomingMessage? {
        let json: [String: Any]
        do { json = try await get("messages/\(id)", ["format": "raw"]) } catch MailAPIError.gone { return nil }
        guard let raw = (json["raw"] as? String).flatMap(Data.init(base64URL:)) else { return nil }
        let received = (json["internalDate"] as? String).flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
        return IncomingMessage(
            mail: raw,
            receiver: .gmail,
            account: account,
            date: received,
            messageID: "gmail:\(id)",
            webURL: Self.webURL(id, account: account)
        )
    }

    public static func webURL(_ id: String, account: MailAccount) -> URL? {
        var url = URLComponents(string: "https://mail.google.com/mail/")!
        url.queryItems = [URLQueryItem(name: "authuser", value: account.user)]
        url.fragment = "all/\(id)"
        return url.url
    }

    private func get(_ path: String, _ query: [String: String] = [:]) async throws -> [String: Any] {
        var url = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/" + path)!
        if !query.isEmpty { url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        let data = try await auth.send(URLRequest(url: url.url!, timeoutInterval: 60), provider: "Google")
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

extension Data {
    fileprivate init?(base64URL: String) {
        var text = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        text += String(repeating: "=", count: (4 - text.count % 4) % 4)
        self.init(base64Encoded: text)
    }
}
