// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation

public protocol MailAPI: Sendable {
    func cursor() async throws -> String
    func inbox(since date: Date, limit: Int) async throws -> [String]
    func added(since cursor: String) async throws -> (ids: [String], cursor: String)
    func message(_ id: String, account: MailAccount) async throws -> IncomingMessage?
    func reconcileRecentIDs(since date: Date, limit: Int) async throws -> [String]
}

public extension MailAPI {
    func reconcileRecentIDs(since date: Date, limit: Int) async throws -> [String] {
        try await inbox(since: date, limit: limit)
    }
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

/// Bounded FIFO deduplication cache that evicts oldest entries cleanly without losing recent IDs.
struct SeenIDBuffer: Sendable {
    private let capacity: Int
    private var order: [String] = []
    private var set: Set<String> = []

    init(capacity: Int = 2_000) {
        self.capacity = max(1, capacity)
    }

    func contains(_ id: String) -> Bool {
        set.contains(id)
    }

    mutating func insert<S: Sequence>(_ ids: S) where S.Element == String {
        for id in ids {
            if set.insert(id).inserted {
                order.append(id)
            }
        }
        if order.count > capacity {
            let overflow = order.count - capacity
            for evicted in order.prefix(overflow) {
                set.remove(evicted)
            }
            order.removeFirst(overflow)
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
        poll: TimeInterval = 5.0,
        burstPoll: TimeInterval = 2.5,
        retryDelay: TimeInterval = 5.0,
        wakeSignal: PollWakeSignal? = nil
    ) async {
        let mailbox = mailbox ?? api(for: account, secrets: secrets)
        var cursor: String? = if case .cursor(let saved) = position { saved } else { nil }
        var resuming = cursor != nil
        var seen = SeenIDBuffer(capacity: 2_000)
        var backoff = retryDelay
        var burstUntil = Date().addingTimeInterval(45)
        var pollCount = 0

        while !Task.isCancelled {
            do {
                await event(.retry(nil))
                await status(.connecting)

                func fetchConcurrent(_ ids: [String]) async throws -> [IncomingMessage] {
                    guard !ids.isEmpty else { return [] }
                    let maxConcurrency = 4
                    var indexedResults: [Int: IncomingMessage] = [:]
                    try await withThrowingTaskGroup(of: (Int, IncomingMessage?).self) { group in
                        var nextIndex = 0
                        let initialCount = min(maxConcurrency, ids.count)
                        for _ in 0..<initialCount {
                            let idx = nextIndex
                            nextIndex += 1
                            let messageID = ids[idx]
                            group.addTask {
                                (idx, try await mailbox.message(messageID, account: account))
                            }
                        }
                        while let (idx, message) = try await group.next() {
                            if let message {
                                indexedResults[idx] = message
                            }
                            if nextIndex < ids.count {
                                let upcoming = nextIndex
                                nextIndex += 1
                                let upcomingID = ids[upcoming]
                                group.addTask {
                                    (upcoming, try await mailbox.message(upcomingID, account: account))
                                }
                            }
                        }
                    }
                    return (0..<ids.count).compactMap { indexedResults[$0] }
                }

                func receive(_ ids: [String]) async throws {
                    let unseen = ids.filter { !seen.contains($0) }
                    let messages = try await fetchConcurrent(unseen)
                    try Task.checkCancellation()
                    seen.insert(unseen)
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
                    pollCount += 1
                    let (added, next) = try await mailbox.added(since: cursor!)
                    let pending = (resuming ? added.suffix(MailWatcher.backfill) : added[...]).filter { !seen.contains($0) }
                    for start in stride(from: 0, to: pending.count, by: 50) {
                        try await receive(Array(pending[start..<min(start + 50, pending.count)]))
                    }

                    // Periodic recent-message reconciliation catches messages delayed by filters or category moves
                    // that history cursors occasionally skip, avoiding "visible in Gmail app, missing in AETHER".
                    var reconciledAny = !pending.isEmpty
                    if pollCount % 4 == 1 || Date() < burstUntil {
                        let recentIDs = (try? await mailbox.reconcileRecentIDs(
                            since: Date().addingTimeInterval(-3600),
                            limit: 25
                        )) ?? []
                        let missed = recentIDs.filter { !seen.contains($0) }
                        if !missed.isEmpty {
                            reconciledAny = true
                            for start in stride(from: 0, to: missed.count, by: 50) {
                                try await receive(Array(missed[start..<min(start + 50, missed.count)]))
                            }
                        }
                    }
                    if !reconciledAny {
                        try await receive([])
                    }

                    resuming = false
                    cursor = next
                    await event(.read(.cursor(next)))

                    let interval = Date() < burstUntil ? min(burstPoll, poll) : poll
                    if let wakeSignal, let wokenUntil = await wakeSignal.sleep(for: interval) {
                        burstUntil = max(burstUntil, wokenUntil)
                        pollCount = 0
                    } else if wakeSignal == nil {
                        try? await Task.sleep(for: .seconds(interval))
                    }
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
                burstUntil = Date().addingTimeInterval(30)
            }
        }
    }
}

public final class PollWakeSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Date?, Never>?
    private var pendingWakeUntil: Date?

    public init() {}

    public func wake(burstSeconds: TimeInterval = 45) {
        let target = Date().addingTimeInterval(burstSeconds)
        let cont: CheckedContinuation<Date?, Never>? = lock.withLock {
            if let continuation {
                self.continuation = nil
                return continuation
            }
            if let existing = pendingWakeUntil {
                pendingWakeUntil = max(existing, target)
            } else {
                pendingWakeUntil = target
            }
            return nil
        }
        cont?.resume(returning: target)
    }

    public func sleep(for duration: TimeInterval) async -> Date? {
        if let queued = lock.withLock({ () -> Date? in
            let hit = pendingWakeUntil
            pendingWakeUntil = nil
            return hit
        }) {
            return queued
        }

        return await withTaskGroup(of: Date?.self) { group in
            group.addTask {
                try? await Task.sleep(for: .seconds(duration))
                return nil
            }
            group.addTask {
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (cont: CheckedContinuation<Date?, Never>) in
                        let immediate: Date? = self.lock.withLock {
                            if let queued = self.pendingWakeUntil {
                                self.pendingWakeUntil = nil
                                return queued
                            }
                            self.continuation = cont
                            return nil
                        }
                        if let immediate {
                            cont.resume(returning: immediate)
                        }
                    }
                } onCancel: {
                    let pending: CheckedContinuation<Date?, Never>? = self.lock.withLock {
                        let c = self.continuation
                        self.continuation = nil
                        return c
                    }
                    pending?.resume(returning: nil)
                }
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
