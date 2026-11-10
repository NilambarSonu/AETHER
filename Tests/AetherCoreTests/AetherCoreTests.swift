import AetherCore
import CodeCatchCore
import Foundation
import Testing

private final class ThreadSafeMessageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [IncomingMessage] = []
    func append(_ msg: IncomingMessage) { lock.withLock { messages.append(msg) } }
    var all: [IncomingMessage] { lock.withLock { messages } }
    var count: Int { lock.withLock { messages.count } }
}

@Suite struct AetherCoreTests {
    private func makeMessage(id: String, text: String, sourceKey: String = "test-source") -> IncomingMessage {
        IncomingMessage(
            text: text,
            subject: "Security Code",
            senderName: "Aether Auth",
            senderID: "auth@example.com",
            sourceKey: sourceKey,
            sourceLabel: "Aether Auth",
            date: Date(),
            isMail: true,
            messageID: id
        )
    }

    // MARK: - 1. AetherSourceCoordinator Core Lifecycle

    @Test func coordinatorDeliversMessagesFromActiveSource() async {
        let collector = ThreadSafeMessageCollector()
        let coordinator = AetherSourceCoordinator(onDeliver: { msg in
            collector.append(msg)
        })

        let fixtureSource = FixtureMailSource(
            sourceKey: "src-1",
            sourceLabel: "Source 1",
            messages: [
                makeMessage(id: "msg-1", text: "Code: 112233", sourceKey: "src-1"),
                makeMessage(id: "msg-2", text: "Code: 445566", sourceKey: "src-1"),
            ]
        )

        await coordinator.register(fixtureSource)
        try? await Task.sleep(for: .milliseconds(50))
        await coordinator.stopAll()

        #expect(collector.count == 2)
        let texts = collector.all.map(\.text)
        #expect(texts.contains("Code: 112233"))
        #expect(texts.contains("Code: 445566"))
    }

    // MARK: - 2. Deduplication Behavior

    @Test func coordinatorSuppressesDuplicateMessageKeys() async {
        let collector = ThreadSafeMessageCollector()
        let coordinator = AetherSourceCoordinator(onDeliver: { msg in
            collector.append(msg)
        })

        let fixtureSource = FixtureMailSource(sourceKey: "dedupe-src", sourceLabel: "Dedupe", messages: [])
        await coordinator.register(fixtureSource)

        let message = makeMessage(id: "same-id", text: "Your code is 998877", sourceKey: "dedupe-src")

        // Deliver identical message multiple times
        fixtureSource.deliver(message)
        fixtureSource.deliver(message)
        fixtureSource.deliver(message)

        try? await Task.sleep(for: .milliseconds(50))
        await coordinator.stopAll()

        #expect(collector.count == 1)
        #expect(collector.all.first?.text == "Your code is 998877")
    }

    // MARK: - 3. Domain Model Behavior

    @Test func incomingMessageComputesCorrectFullTextAndDismissKey() {
        let msg = makeMessage(id: "key-123", text: "Verification: 123456", sourceKey: "mail-key")
        #expect(msg.fullText == "Security Code\nVerification: 123456")
        #expect(msg.dismissKey == "message:mail-key|key-123")
    }

    @Test func sourceHealthRecordsEventsCorrectly() {
        var health = SourceHealth()
        #expect(health.status == .off)

        let checkDate = Date()
        health.record(.checked(checkDate))
        #expect(health.lastChecked == checkDate)

        let retryDate = checkDate.addingTimeInterval(30)
        health.record(.retry(retryDate))
        #expect(health.retryAt == retryDate)
    }

    @Test func sourceStatusIdentifiesAttentionRequirements() {
        let diskAccess = SourceStatus.attention(SourceStatus.needsDiskAccess)
        #expect(diskAccess.needsDiskAccess == true)
        #expect(diskAccess.needsAttention == true)

        let live = SourceStatus.live
        #expect(live.needsAttention == false)
        #expect(live.summary == "Watching")
    }
}
