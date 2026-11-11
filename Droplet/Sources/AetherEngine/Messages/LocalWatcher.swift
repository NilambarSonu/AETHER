// Modified for AETHER (November 2026). Copyright (C) 2026 Nilambar Behera.
// Licensed under the GNU General Public License, Version 3.0 (GPLv3).

import Foundation

public protocol LocalStore: AnyObject {
    var name: String { get }
    var position: Int64 { get }
    var readPosition: ReadPosition? { get }
    var watchDirectory: String? { get }
    var hasPendingBodies: Bool { get }
    func open(since: Date) -> String?
    func newMessages() throws -> [IncomingMessage]
    func close()
}

public extension LocalStore {
    var readPosition: ReadPosition? { nil }
    var watchDirectory: String? { nil }
    var hasPendingBodies: Bool { false }
}

/// Watches a local SQLite database using FSEvents where available, falling back to 1s polling.
public final class LocalWatcher {
    private let store: LocalStore
    private let queue = DispatchQueue(label: "app.getdroppy.droplet.aether.local-store")
    private var timer: DispatchSourceTimer?
    private var fsWatcher: FSEventWatcher?
    private var isOpen = false
    private var retryAt = Date.distantPast
    private var lastStatus: SourceStatus?
    private var stopped = false
    private var pendingRetryScheduled = false

    public init(_ store: LocalStore) { self.store = store }

    public func start(
        lookback: TimeInterval,
        status: @escaping @MainActor (SourceStatus) -> Void,
        deliver: @escaping @MainActor (IncomingMessage) -> Void,
        event: @escaping @MainActor (SourceEvent) -> Void = { _ in }
    ) {
        queue.async { [weak self] in
            self?.poll(lookback: lookback, status: status, deliver: deliver, event: event)
        }

        var fseventsActive = false
        if let dir = store.watchDirectory, FileManager.default.fileExists(atPath: dir) {
            let watcher = FSEventWatcher(paths: [dir], latency: 0.05, queue: queue) { [weak self] in
                self?.poll(lookback: lookback, status: status, deliver: deliver, event: event)
            }
            if watcher.start() {
                self.fsWatcher = watcher
                fseventsActive = true
            }
        }

        let t = DispatchSource.makeTimerSource(queue: queue)
        let interval: TimeInterval = fseventsActive ? 30.0 : 1.0
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in
            self?.poll(lookback: lookback, status: status, deliver: deliver, event: event)
        }
        t.resume()
        timer = t
    }

    public var position: Int64 { queue.sync { store.position } }

    public func stop() {
        timer?.cancel()
        timer = nil
        fsWatcher?.stop()
        fsWatcher = nil
        queue.async { [weak self, store] in
            self?.stopped = true
            store.close()
        }
    }

    private func poll(
        lookback: TimeInterval,
        status: @escaping @MainActor (SourceStatus) -> Void,
        deliver: @escaping @MainActor (IncomingMessage) -> Void,
        event: @escaping @MainActor (SourceEvent) -> Void
    ) {
        guard !stopped else { return }
        func report(_ s: SourceStatus) {
            guard !stopped, s != lastStatus else { return }
            lastStatus = s
            Task { @MainActor in status(s) }
        }
        func retry(_ s: SourceStatus) {
            store.close()
            isOpen = false
            retryAt = Date().addingTimeInterval(5)
            let retry = retryAt
            Task { @MainActor in event(.retry(retry)) }
            report(s)
        }
        if !isOpen {
            guard Date() >= retryAt else { return }
            if let problem = store.open(since: Date().addingTimeInterval(-lookback)) { return retry(.attention(problem)) }
            isOpen = true
            Task { @MainActor in event(.retry(nil)) }
        }
        do {
            let start = ContinuousClock.now
            let rawMessages = try store.newMessages()
            let messages = rawMessages.map { $0.withPrecomputedExtraction() }
            let elapsed = ContinuousClock.now - start
            let ms = Int((Double(elapsed.components.seconds) * 1_000.0) + (Double(elapsed.components.attoseconds) / 1e15))
            let checkedAt = Date()
            let read = store.readPosition
            report(.live)
            Task { @MainActor in
                event(.checked(checkedAt))
                event(.latencyMs(ms))
                if let newest = messages.map(\.date).max() { event(.message(newest)) }
                for message in messages { deliver(message) }
                if let read { event(.read(read)) }
            }
            if store.hasPendingBodies, !pendingRetryScheduled {
                pendingRetryScheduled = true
                queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.pendingRetryScheduled = false
                    self?.poll(lookback: lookback, status: status, deliver: deliver, event: event)
                }
            }
        } catch {
            retry(.failed("Can't read \(store.name)"))
        }
    }
}
