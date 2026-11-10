import CodeCatchCore
import Foundation
import Testing

@testable import CodeCatch

private final class MockLocalStore: LocalStore {
    let name = "MockStore"
    var position: Int64 = 0
    var watchDirectory: String?
    var messagesToReturn: [IncomingMessage] = []
    var openCount = 0
    var closeCount = 0

    init(watchDirectory: String? = nil) {
        self.watchDirectory = watchDirectory
    }

    func open(since: Date) -> String? {
        openCount += 1
        return nil
    }

    func newMessages() throws -> [IncomingMessage] {
        let msgs = messagesToReturn
        messagesToReturn.removeAll()
        position += Int64(msgs.count)
        return msgs
    }

    func close() {
        closeCount += 1
    }
}

@Suite struct FSEventWatcherTests {
    // MARK: - 1. FSEventWatcher Kernel Event Trigger

    @Test func fsEventWatcherTriggersOnDirectoryFileModification() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fsevent-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        final class ThreadSafeFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            func set() { lock.withLock { value = true } }
            func get() -> Bool { lock.withLock { value } }
        }

        let flag = ThreadSafeFlag()
        let queue = DispatchQueue(label: "fsevent-test-queue")
        let watcher = FSEventWatcher(paths: [tempDir.path], latency: 0.05, queue: queue) {
            flag.set()
        }

        #expect(watcher.start() == true)

        // Write a test file into the monitored directory
        let testFile = tempDir.appendingPathComponent("test.txt")
        try "hello".write(to: testFile, atomically: true, encoding: .utf8)

        // Allow kernel latency to deliver the event
        try? await Task.sleep(for: .milliseconds(150))
        watcher.stop()

        #expect(flag.get() == true)
    }

    // MARK: - 2. LocalWatcher Event-Driven Trigger

    @Test @MainActor func localWatcherTriggersDeliveryOnFSEvent() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("local-watcher-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = MockLocalStore(watchDirectory: tempDir.path)
        let watcher = LocalWatcher(store)

        var delivered: [IncomingMessage] = []
        watcher.start(
            lookback: 60,
            status: { _ in },
            deliver: { delivered.append($0) }
        )

        // Wait for initial poll
        try? await Task.sleep(for: .milliseconds(50))

        // Stage a new message in store and touch a file in the watch directory
        store.messagesToReturn = [
            IncomingMessage(
                text: "Your code is 554433",
                senderName: "SMS",
                senderID: "12345",
                sourceKey: "sms",
                sourceLabel: "SMS",
                date: Date(),
                isMail: false),
        ]

        let triggerFile = tempDir.appendingPathComponent("chat.db-wal")
        try "wal-data".write(to: triggerFile, atomically: true, encoding: .utf8)

        // FSEvents should detect the WAL file creation and poll immediately
        try? await Task.sleep(for: .milliseconds(200))
        watcher.stop()

        #expect(delivered.count == 1)
        #expect(delivered.first?.text.contains("554433") == true)
    }

    // MARK: - 3. LocalWatcher Fallback on Missing Directory

    @Test @MainActor func localWatcherFallsBackToPollingWhenDirectoryMissing() async throws {
        let missingPath = "/non/existent/path/\(UUID().uuidString)"
        let store = MockLocalStore(watchDirectory: missingPath)
        let watcher = LocalWatcher(store)

        var delivered: [IncomingMessage] = []
        watcher.start(
            lookback: 60,
            status: { _ in },
            deliver: { delivered.append($0) }
        )

        // Initial poll completes
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.openCount >= 1)
        watcher.stop()
    }
}
