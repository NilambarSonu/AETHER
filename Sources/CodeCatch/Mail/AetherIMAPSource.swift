import CodeCatchCore
import Foundation

/// Concrete asynchronous IMAP provider conforming to `AetherMailSource`.
///
/// Coordinates `MailWatcher` and `IMAPConnection`, translating IMAP
/// lifecycle events and incoming emails into a structured `AsyncStream<AetherSourceOutput>`.
final class AetherIMAPSource: AetherMailSource, @unchecked Sendable {
    let account: MailAccount
    let lookback: TimeInterval
    let retryDelay: TimeInterval
    private let connectionFactory: (@Sendable () -> any MailConnection)?

    public var sourceKey: String { account.id.uuidString }
    public var sourceLabel: String { account.label }

    private let lock = NSLock()
    private var activeTask: Task<Void, Never>?
    private var streamContinuation: AsyncStream<AetherSourceOutput>.Continuation?
    private var isStopped = false

    init(
        account: MailAccount,
        lookback: TimeInterval = 7 * 86400,
        retryDelay: TimeInterval = 5,
        connection: (@Sendable () -> any MailConnection)? = nil
    ) {
        self.account = account
        self.lookback = lookback
        self.retryDelay = retryDelay
        self.connectionFactory = connection
    }

    deinit {
        activeTask?.cancel()
    }

    func messages() -> AsyncStream<AetherSourceOutput> {
        AsyncStream { continuation in
            lock.withLock {
                self.streamContinuation = continuation
                self.isStopped = false
            }

            continuation.onTermination = { [weak self] _ in
                self?.handleTermination()
            }

            let task = Task { [weak self, account, lookback, retryDelay, connectionFactory] in
                await MailWatcher.watch(
                    account,
                    from: nil,
                    status: { status in
                        continuation.yield(.status(status))
                    },
                    deliver: { msg in
                        continuation.yield(.message(msg))
                    },
                    event: { ev in
                        continuation.yield(.event(ev))
                    },
                    lookback: lookback,
                    connection: connectionFactory,
                    retryDelay: retryDelay
                )
                self?.handleTermination()
            }

            lock.withLock {
                self.activeTask = task
            }
        }
    }

    func stop() async {
        let (task, continuation) = lock.withLock { () -> (Task<Void, Never>?, AsyncStream<AetherSourceOutput>.Continuation?) in
            guard !isStopped else { return (nil, nil) }
            isStopped = true
            let t = activeTask
            let c = streamContinuation
            activeTask = nil
            streamContinuation = nil
            return (t, c)
        }

        task?.cancel()
        _ = await task?.value
        continuation?.yield(.status(.off))
        continuation?.finish()
    }

    private func handleTermination() {
        let (task, continuation) = lock.withLock { () -> (Task<Void, Never>?, AsyncStream<AetherSourceOutput>.Continuation?) in
            guard !isStopped else { return (nil, nil) }
            isStopped = true
            let t = activeTask
            let c = streamContinuation
            activeTask = nil
            streamContinuation = nil
            return (t, c)
        }
        task?.cancel()
        continuation?.finish()
    }
}

