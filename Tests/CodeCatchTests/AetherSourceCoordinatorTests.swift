import CodeCatchCore
import Foundation
import Testing

@testable import CodeCatch

private final class MessageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [IncomingMessage] = []
    func append(_ msg: IncomingMessage) { lock.withLock { messages.append(msg) } }
    var all: [IncomingMessage] { lock.withLock { messages } }
    var count: Int { lock.withLock { messages.count } }
}

@Suite struct AetherSourceCoordinatorTests {
    private func makeMessage(id: String, text: String, sourceKey: String = "src-1") -> IncomingMessage {
        IncomingMessage(
            text: text,
            subject: "Verification",
            senderName: "Service",
            senderID: "noreply@service.com",
            sourceKey: sourceKey,
            sourceLabel: "Service",
            date: Date(),
            isMail: true,
            messageID: id)
    }

    // MARK: - 1. Multiple Active Sources

    @Test func multipleSourcesDeliverConcurrently() async {
        let collector = MessageCollector()
        let coordinator = AetherSourceCoordinator(
            onDeliver: { msg in
                collector.append(msg)
            })

        let src1 = FixtureMailSource(sourceKey: "src-1", sourceLabel: "Source 1", messages: [
            makeMessage(id: "msg-1", text: "Code: 111111", sourceKey: "src-1"),
        ])
        let src2 = FixtureMailSource(sourceKey: "src-2", sourceLabel: "Source 2", messages: [
            makeMessage(id: "msg-2", text: "Code: 222222", sourceKey: "src-2"),
        ])

        await coordinator.register(src1)
        await coordinator.register(src2)

        try? await Task.sleep(for: .milliseconds(50))
        await coordinator.stopAll()

        #expect(collector.count == 2)
        let texts = collector.all.map(\.text)
        #expect(texts.contains("Code: 111111"))
        #expect(texts.contains("Code: 222222"))
    }

    // MARK: - 2. Source Failure Isolation

    @Test func failureInOneSourceLeavesOtherSourceLive() async {
        let collector = MessageCollector()
        let coordinator = AetherSourceCoordinator(
            onDeliver: { collector.append($0) })

        let healthySrc = FixtureMailSource(sourceKey: "healthy", sourceLabel: "Healthy", messages: [
            makeMessage(id: "h-1", text: "Code: 333333", sourceKey: "healthy"),
        ])
        // Custom failing source that emits an error status
        let failingSrc = FixtureMailSource(sourceKey: "failing", sourceLabel: "Failing", messages: [])

        await coordinator.register(healthySrc)
        await coordinator.register(failingSrc)

        // Simulate failure in failing source
        failingSrc.deliver(makeMessage(id: "f-err", text: "trigger", sourceKey: "failing"))
        await failingSrc.stop()

        try? await Task.sleep(for: .milliseconds(50))

        let statuses = await coordinator.statuses
        #expect(statuses["failing"] == .off)

        // Healthy source delivers another message after the other failed
        healthySrc.deliver(makeMessage(id: "h-2", text: "Code: 444444", sourceKey: "healthy"))
        try? await Task.sleep(for: .milliseconds(50))

        await coordinator.stopAll()

        let healthyCodes = collector.all.filter { $0.sourceKey == "healthy" }
        #expect(healthyCodes.count == 2)
    }

    // MARK: - 3. Duplicate Message Suppression

    @Test func duplicateMessagesAreSuppressed() async {
        let collector = MessageCollector()
        let coordinator = AetherSourceCoordinator(
            onDeliver: { collector.append($0) })

        let src = FixtureMailSource(sourceKey: "dedupe-src", sourceLabel: "Dedupe", messages: [])
        await coordinator.register(src)

        let msg = makeMessage(id: "same-id", text: "Code: 555555", sourceKey: "dedupe-src")

        // Deliver the exact same message twice
        src.deliver(msg)
        src.deliver(msg)

        try? await Task.sleep(for: .milliseconds(50))
        await coordinator.stopAll()

        #expect(collector.count == 1)
        #expect(collector.all.first?.text == "Code: 555555")
    }

    // MARK: - 4. Source Unregistration & Cancellation

    @Test func unregisterStopsConsumption() async {
        let collector = MessageCollector()
        let coordinator = AetherSourceCoordinator(
            onDeliver: { collector.append($0) })

        let src = FixtureMailSource(sourceKey: "unreg-src", sourceLabel: "Unreg", messages: [])
        await coordinator.register(src)

        src.deliver(makeMessage(id: "before", text: "Before", sourceKey: "unreg-src"))
        try? await Task.sleep(for: .milliseconds(30))

        await coordinator.unregister("unreg-src")

        src.deliver(makeMessage(id: "after", text: "After", sourceKey: "unreg-src"))
        try? await Task.sleep(for: .milliseconds(30))

        #expect(collector.count == 1)
        #expect(collector.all.first?.text == "Before")
        let count = await coordinator.count
        #expect(count == 0)
    }

    // MARK: - 5. Repeated StopAll Idempotency

    @Test func repeatedStopAllIsSafeAndIdempotent() async {
        let coordinator = AetherSourceCoordinator(onDeliver: { _ in })
        let src = FixtureMailSource(sourceKey: "idem-src", sourceLabel: "Idem", messages: [])
        await coordinator.register(src)

        // Consecutive stop calls
        await coordinator.stopAll()
        await coordinator.stopAll()
        await coordinator.stopAll()

        let statuses = await coordinator.statuses
        #expect(statuses["idem-src"] == .off)
    }
}
