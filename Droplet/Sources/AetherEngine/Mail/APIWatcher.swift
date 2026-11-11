// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation

public protocol MailAPI: Sendable {
    func cursor() async throws -> String
    func inbox(since date: Date, limit: Int) async throws -> [String]
    func added(since cursor: String) async throws -> (ids: [String], cursor: String)
    func message(_ id: String, account: MailAccount) async throws -> IncomingMessage?
}

public enum MailAPIError: LocalizedError, Sendable {
    case cursorExpired, gone
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .cursorExpired: "The mailbox's change history expired"
        case .gone: "The message was deleted"
        case .http(let status, let message): "The mail service answered \(status): \(message)"
        }
    }
}

public enum APIWatcher {
    public static func api(for account: MailAccount, secrets: AetherSecretStore = .keychain) -> any MailAPI {
        account.isOutlook
            ? OutlookAPI(account: account, secrets: secrets)
            : GmailAPI(account: account, secrets: secrets)
    }

    public static func watch(
        _ account: MailAccount,
        from position: ReadPosition? = nil,
        secrets: AetherSecretStore = .keychain,
        status: @escaping @MainActor (SourceStatus) -> Void,
        deliver: @escaping @MainActor (IncomingMessage) -> Void,
        event: @escaping @MainActor (SourceEvent) -> Void = { _ in },
        lookback: TimeInterval = 7 * 86400,
        mailbox: (any MailAPI)? = nil,
        poll: TimeInterval = 10,
        retryDelay: TimeInterval = 5
    ) async {
        let mailbox = mailbox ?? api(for: account, secrets: secrets)
        var cursor: String? = if case .cursor(let saved) = position { saved } else { nil }
        var resuming = cursor != nil
        var seen = Set<String>()
        var backoff = retryDelay
        while !Task.isCancelled {
            do {
                await event(.retry(nil))
                await status(.connecting)

                func receive(_ ids: [String]) async throws {
                    var messages: [IncomingMessage] = []
                    for id in ids where !seen.contains(id) {
                        try Task.checkCancellation()
                        if let message = try await mailbox.message(id, account: account) { messages.append(message) }
                    }
                    try Task.checkCancellation()
                    if seen.count > 1000 { seen.removeAll() }
                    seen.formUnion(ids)
                    try await MailWatcher.hand(messages, event: event, deliver: deliver)
                }

                if cursor == nil {
                    let start = try await mailbox.cursor()
                    try await receive(try await mailbox.inbox(since: Date().addingTimeInterval(-lookback), limit: MailWatcher.backfill))
                    cursor = start
                    await event(.read(.cursor(start)))
                    resuming = false
                }
                try Task.checkCancellation()
                await status(.live)
                backoff = retryDelay
                while !Task.isCancelled {
                    let (added, next) = try await mailbox.added(since: cursor!)
                    let pending = (resuming ? added.suffix(MailWatcher.backfill) : added[...]).filter { !seen.contains($0) }
                    if pending.isEmpty { try await receive([]) }
                    for start in stride(from: 0, to: pending.count, by: 50) {
                        try await receive(Array(pending[start..<min(start + 50, pending.count)]))
                    }
                    resuming = false
                    cursor = next
                    await event(.read(.cursor(next)))
                    try await Task.sleep(for: .seconds(poll))
                }
            } catch MailAPIError.cursorExpired {
                cursor = nil
            } catch {
                if Task.isCancelled { break }
                let signInFailed = error is MailOAuth.Failure
                await MailWatcher.wait(
                    after: signInFailed ? SourceStatus.signInExpired : MailWatcher.describe(error),
                    signIn: signInFailed,
                    backoff: &backoff,
                    status: status,
                    event: event
                )
            }
        }
    }
}
