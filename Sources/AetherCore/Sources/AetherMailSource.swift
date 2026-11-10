import CodeCatchCore
import Foundation

/// An output event or message produced by an AETHER message source.
public enum AetherSourceOutput: Sendable {
    case message(IncomingMessage)
    case status(SourceStatus)
    case event(SourceEvent)
}

/// Minimal, asynchronous abstraction for AETHER message sources.
public protocol AetherMailSource: Sendable {
    var sourceKey: String { get }
    var sourceLabel: String { get }

    /// Returns an asynchronous stream yielding incoming messages, status transitions, and health events.
    func messages() -> AsyncStream<AetherSourceOutput>

    /// Explicitly stops the source and releases underlying network or file resources.
    func stop() async
}

/// Reference implementation of `AetherMailSource` backed by an in-memory queue or fixture messages.
public final class FixtureMailSource: AetherMailSource, @unchecked Sendable {
    public let sourceKey: String
    public let sourceLabel: String
    private let queuedMessages: [IncomingMessage]
    private let lock = NSLock()
    private var continuation: AsyncStream<AetherSourceOutput>.Continuation?
    private var isRunning = false

    public init(sourceKey: String = UUID().uuidString, sourceLabel: String = "Fixture Mail", messages: [IncomingMessage] = []) {
        self.sourceKey = sourceKey
        self.sourceLabel = sourceLabel
        self.queuedMessages = messages
    }

    public func messages() -> AsyncStream<AetherSourceOutput> {
        AsyncStream { continuation in
            lock.withLock {
                self.continuation = continuation
                self.isRunning = true
            }

            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.isRunning = false
                    self?.continuation = nil
                }
            }

            continuation.yield(.status(.connecting))
            continuation.yield(.status(.live))

            for msg in queuedMessages {
                let stillRunning = lock.withLock { self.isRunning }
                guard stillRunning else { break }
                continuation.yield(.message(msg))
                continuation.yield(.event(.checked(Date())))
            }
        }
    }

    /// Dynamically injects a message into an active stream.
    public func deliver(_ message: IncomingMessage) {
        let cont: AsyncStream<AetherSourceOutput>.Continuation? = lock.withLock {
            guard isRunning else { return nil }
            return continuation
        }
        guard let cont else { return }
        cont.yield(.message(message))
        cont.yield(.event(.checked(Date())))
    }

    public func stop() async {
        let cont: AsyncStream<AetherSourceOutput>.Continuation? = lock.withLock {
            isRunning = false
            let c = continuation
            continuation = nil
            return c
        }
        cont?.yield(.status(.off))
        cont?.finish()
    }
}
