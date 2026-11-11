// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import CodeCatchCore
import Foundation

public struct OutlookAPI: MailAPI {
    private let send: @Sendable (URLRequest) async throws -> Data

    public init(auth: MailAPIAuth, send: (@Sendable (URLRequest) async throws -> Data)? = nil) {
        self.send = send ?? { try await auth.send($0, provider: "Microsoft") }
    }
    public init(account: MailAccount, secrets: AetherSecretStore = .keychain) {
        self.init(auth: .saved(.microsoft, tokenKey: account.refreshTokenKey, secrets: secrets))
    }

    public func emailAddress() async throws -> String {
        let me = try await json("me", ["$select": "mail,userPrincipalName"])
        guard let email = (me["mail"] as? String) ?? (me["userPrincipalName"] as? String) else { throw MailAPIError.http(200, "no address") }
        return email
    }

    public func cursor() async throws -> String {
        let newest = try await list(["$orderby": "receivedDateTime desc", "$top": "1"])
        return newest.first?.received ?? Self.timestamp(Date().addingTimeInterval(-60))
    }

    public func inbox(since date: Date, limit: Int) async throws -> [String] {
        try await list([
            "$filter": "receivedDateTime ge \(Self.timestamp(date))",
            "$orderby": "receivedDateTime desc",
            "$top": "\(limit)",
        ]).map(\.id).reversed()
    }

    public func added(since cursor: String) async throws -> (ids: [String], cursor: String) {
        let new = try await list(["$filter": "receivedDateTime ge \(cursor)", "$orderby": "receivedDateTime asc", "$top": "50"], allPages: true)
        return (new.map(\.id), new.last?.received ?? cursor)
    }

    public func message(_ id: String, account: MailAccount) async throws -> IncomingMessage? {
        let info: [String: Any]
        let raw: Data
        do {
            info = try await json("me/messages/\(id)", ["$select": "receivedDateTime,webLink"])
            raw = try await get("me/messages/\(id)/$value")
        } catch MailAPIError.gone { return nil }
        let received = (info["receivedDateTime"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
        return IncomingMessage(
            mail: raw,
            receiver: .microsoft,
            account: account,
            date: received,
            messageID: "outlook:\(id)",
            webURL: (info["webLink"] as? String).flatMap(URL.init(string:))
        )
    }

    private func list(_ query: [String: String], allPages: Bool = false) async throws -> [(id: String, received: String)] {
        var page = try await json("me/mailFolders/inbox/messages", query.merging(["$select": "id,receivedDateTime"]) { a, _ in a })
        var messages: [(id: String, received: String)] = []
        var visited = Set<URL>()
        while true {
            try Task.checkCancellation()
            guard let values = page["value"] as? [[String: Any]] else { throw MailAPIError.http(200, "invalid mailbox page") }
            for value in values {
                guard let id = value["id"] as? String, let received = value["receivedDateTime"] as? String else {
                    throw MailAPIError.http(200, "incomplete mailbox message")
                }
                messages.append((id, received))
            }
            guard allPages, let next = page["@odata.nextLink"] else { return messages }
            guard let link = next as? String, let url = URL(string: link),
                url.scheme == "https", url.host?.lowercased() == "graph.microsoft.com",
                url.port == nil || url.port == 443, url.user == nil, url.password == nil, url.fragment == nil,
                visited.insert(url).inserted
            else {
                throw MailAPIError.http(200, "invalid or cyclic mailbox pagination")
            }
            let data = try await send(URLRequest(url: url, timeoutInterval: 60))
            guard let nextPage = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MailAPIError.http(200, "invalid mailbox page")
            }
            page = nextPage
        }
    }

    private func json(_ path: String, _ query: [String: String]) async throws -> [String: Any] {
        let data = try await get(path, query)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func get(_ path: String, _ query: [String: String] = [:]) async throws -> Data {
        var url = URLComponents(string: "https://graph.microsoft.com/v1.0/" + path)!
        if !query.isEmpty { url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        return try await send(URLRequest(url: url.url!, timeoutInterval: 60))
    }

    private static func timestamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
