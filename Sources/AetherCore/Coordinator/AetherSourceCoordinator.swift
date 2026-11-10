import CodeCatchCore
import Foundation

/// Centralized coordinator managing the lifecycle of modern `AetherMailSource` providers.
///
/// Responsibilities:
/// - Concurrently consumes `AsyncStream` outputs from registered sources without blocking the `@MainActor`.
/// - Routes incoming messages to the ingestion pipeline.
/// - Performs sliding-window deduplication by message dismissKey.
/// - Tracks per-source status (`[String: SourceStatus]`) and isolates failures across sources.
/// - Coordinates graceful, concurrent shutdown during app quit or sleep.
public actor AetherSourceCoordinator {
    private var sources: [String: any AetherMailSource] = [:]
    private var consumerTasks: [String: Task<Void, Never>] = [:]
    public private(set) var statuses: [String: SourceStatus] = [:]

    /// Sliding window of recently ingested message keys to prevent duplicate pipeline ingestion.
    private var seenMessageKeys: Set<String> = []
    private var seenKeyHistory: [String] = []
    private let maxDeduplicationWindow = 500

    private let onDeliver: @Sendable (IncomingMessage) async -> Void
    private let onStatusChange: (@Sendable (String, SourceStatus) async -> Void)?

    public init(
        onDeliver: @escaping @Sendable (IncomingMessage) async -> Void,
        onStatusChange: (@Sendable (String, SourceStatus) async -> Void)? = nil
    ) {
        self.onDeliver = onDeliver
        self.onStatusChange = onStatusChange
    }

    deinit {
        for task in consumerTasks.values {
            task.cancel()
        }
    }

    /// Number of registered sources.
    public var count: Int { sources.count }

    /// Registers a source with the coordinator. If autoStart is true, starts consumption immediately.
    public func register(_ source: any AetherMailSource, autoStart: Bool = true) async {
        let key = source.sourceKey
        sources[key] = source
        statuses[key] = .connecting
        if autoStart {
            start(key)
        }
    }

    /// Starts consuming from a registered source.
    public func start(_ key: String) {
        guard let source = sources[key] else { return }
        consumerTasks[key]?.cancel()

        let stream = source.messages()
        consumerTasks[key] = Task { [weak self, key] in
            for await output in stream {
                guard !Task.isCancelled else { break }
                guard let self else { break }
                await self.handleOutput(output, from: key)
            }
        }
    }

    /// Stops a specific source by key.
    public func stop(_ key: String) async {
        consumerTasks.removeValue(forKey: key)?.cancel()
        if let source = sources[key] {
            await source.stop()
        }
        statuses[key] = .off
        await onStatusChange?(key, .off)
    }

    /// Unregisters and stops a source.
    public func unregister(_ key: String) async {
        await stop(key)
        sources.removeValue(forKey: key)
        statuses.removeValue(forKey: key)
    }

    /// Gracefully stops all active sources concurrently.
    public func stopAll() async {
        let activeSources = Array(sources.values)
        for task in consumerTasks.values {
            task.cancel()
        }
        consumerTasks.removeAll()

        await withTaskGroup(of: Void.self) { group in
            for source in activeSources {
                group.addTask {
                    await source.stop()
                }
            }
        }

        for key in sources.keys {
            statuses[key] = .off
        }
    }

    private func handleOutput(_ output: AetherSourceOutput, from sourceKey: String) async {
        switch output {
        case .message(let message):
            let dedupeKey = message.dismissKey
            guard !seenMessageKeys.contains(dedupeKey) else { return }

            seenMessageKeys.insert(dedupeKey)
            seenKeyHistory.append(dedupeKey)
            if seenKeyHistory.count > maxDeduplicationWindow {
                let evicted = seenKeyHistory.removeFirst()
                seenMessageKeys.remove(evicted)
            }

            await onDeliver(message)

        case .status(let status):
            statuses[sourceKey] = status
            await onStatusChange?(sourceKey, status)

        case .event:
            break
        }
    }
}
