// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation

public struct GmailAPI: MailAPI {
    public let auth: MailAPIAuth
    public let includeJunk: Bool

    private static let baseExcludedLabels: Set<String> = ["TRASH", "DRAFT"]

    public init(auth: MailAPIAuth, includeJunk: Bool = false) {
        self.auth = auth
        self.includeJunk = includeJunk
    }

    public init(account: MailAccount, secrets: AetherSecretStore = .keychain, includeJunk: Bool = false) {
        self.init(auth: .saved(.google, tokenKey: account.activeRefreshTokenKey(in: secrets), secrets: secrets), includeJunk: includeJunk)
    }

    private var excludedLabels: Set<String> {
        includeJunk ? Self.baseExcludedLabels : Self.baseExcludedLabels.union(["SPAM"])
    }

    public func emailAddress() async throws -> String {
        guard let email = try await get("profile")["emailAddress"] as? String else {
            throw MailAPIError.http(200, "no address")
        }
        return email
    }

    public func cursor() async throws -> String {
        try await get("profile")["historyId"].map { "\($0)" } ?? ""
    }

    public func inbox(since date: Date, limit: Int) async throws -> [String] {
        let cutoff = Int(max(0, date.timeIntervalSince1970 - 5))
        var query = [
            URLQueryItem(name: "q", value: includeJunk ? "after:\(cutoff) -in:trash -in:drafts" : "after:\(cutoff) -in:trash -in:spam -in:drafts"),
            URLQueryItem(name: "maxResults", value: "\(limit)"),
        ]
        if includeJunk {
            query.append(URLQueryItem(name: "includeSpamTrash", value: "true"))
        }
        let json = try await get("messages", queryItems: query)
        return ((json["messages"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }.reversed()
    }

    public func reconcileRecentIDs(since date: Date, limit: Int) async throws -> [String] {
        try await inbox(since: date, limit: limit)
    }

    /// Queries Gmail history across BOTH `messageAdded` and `labelAdded` without locking out
    /// Gmail category tabs (`CATEGORY_UPDATES`, `CATEGORY_PROMOTIONS`, etc.) or user filter labels,
    /// while skipping messages strictly marked Trash, Spam, or Draft.
    public func added(since historyID: String) async throws -> (ids: [String], cursor: String) {
        var ids: [String] = []
        var seenInBatch = Set<String>()
        var latest = historyID
        var page: String?
        repeat {
            var query = [
                URLQueryItem(name: "startHistoryId", value: historyID),
                URLQueryItem(name: "historyTypes", value: "messageAdded"),
                URLQueryItem(name: "historyTypes", value: "labelAdded"),
            ]
            if let page {
                query.append(URLQueryItem(name: "pageToken", value: page))
            }
            let json: [String: Any]
            do {
                json = try await get("history", queryItems: query)
            } catch MailAPIError.gone {
                throw MailAPIError.cursorExpired
            }
            for record in (json["history"] as? [[String: Any]]) ?? [] {
                for entry in (record["messagesAdded"] as? [[String: Any]]) ?? [] {
                    collectMessageID(from: entry["message"] as? [String: Any], into: &ids, seen: &seenInBatch)
                }
                for entry in (record["labelsAdded"] as? [[String: Any]]) ?? [] {
                    collectMessageID(from: entry["message"] as? [String: Any], into: &ids, seen: &seenInBatch)
                }
            }
            latest = json["historyId"].map { "\($0)" } ?? latest
            page = json["nextPageToken"] as? String
        } while page != nil
        return (ids, latest)
    }

    public func message(_ id: String, account: MailAccount) async throws -> IncomingMessage? {
        let json: [String: Any]
        do {
            json = try await get("messages/\(id)", queryItems: [URLQueryItem(name: "format", value: "raw")])
        } catch MailAPIError.gone {
            return nil
        }
        if let labels = json["labelIds"] as? [String], labels.contains(where: excludedLabels.contains) {
            return nil
        }
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

    private func collectMessageID(from message: [String: Any]?, into ids: inout [String], seen: inout Set<String>) {
        guard let message, let id = message["id"] as? String else { return }
        if let labels = message["labelIds"] as? [String], labels.contains(where: excludedLabels.contains) {
            return
        }
        if seen.insert(id).inserted {
            ids.append(id)
        }
    }

    private func get(_ path: String, queryItems: [URLQueryItem] = []) async throws -> [String: Any] {
        var url = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/" + path)!
        if !queryItems.isEmpty { url.queryItems = queryItems }
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
