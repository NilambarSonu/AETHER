import CodeCatchCore
import Foundation
import Testing

@testable import CodeCatch

private actor MockIMAPConnection: MailConnection {
    let capabilities: Set<String> = ["IDLE"]
    var shouldFailAuth: Bool
    var shouldDisconnect: Bool
    var openedCount = 0
    var closedCount = 0

    init(shouldFailAuth: Bool = false, shouldDisconnect: Bool = false) {
        self.shouldFailAuth = shouldFailAuth
        self.shouldDisconnect = shouldDisconnect
    }

    func openInbox(_ account: MailAccount) async throws -> [IMAPConnection.Response] {
        openedCount += 1
        if shouldFailAuth {
            throw IMAPError.noPassword
        }
        if shouldDisconnect && openedCount == 1 {
            throw IMAPError.closed
        }
        return [
            .init(text: "* OK [UIDNEXT 100]", literals: []),
            .init(text: "* OK [UIDVALIDITY 1]", literals: []),
        ]
    }

    func search(_ criteria: String) async throws -> [Int] {
        if criteria.hasPrefix("SINCE") {
            return [99]
        }
        return []
    }

    func fetch(_ uids: [Int], account: MailAccount) async throws -> [IncomingMessage] {
        return uids.map { uid in
            IncomingMessage(
                text: "Your security code is 482913",
                subject: "Code",
                senderName: "Service",
                senderID: "service@example.com",
                sourceKey: account.id.uuidString,
                sourceLabel: account.label,
                date: Date(),
                isMail: true,
                messageID: "\(uid)")
        }
    }

    func idle(renewAfter: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(60))
    }

    func command(_ cmd: String, timeout: TimeInterval) async throws -> [IMAPConnection.Response] {
        return [.init(text: "* OK", literals: [])]
    }

    func close() async {
        closedCount += 1
    }
}

@Suite struct AetherIMAPSourceTests {
    private func makeAccount() -> MailAccount {
        MailAccount(
            id: UUID(), label: "Test Account", host: "imap.example.com", port: 993,
            user: "user@example.com")
    }

    // MARK: - 1. Successful Connection & Message Delivery

    @Test @MainActor func successfulConnectionStreamsMessage() async {
        let account = makeAccount()
        let mock = MockIMAPConnection()
        let source = AetherIMAPSource(account: account, retryDelay: 0, connection: { mock })

        var receivedMessages: [IncomingMessage] = []
        var statuses: [SourceStatus] = []

        let stream = source.messages()
        let consumer = Task {
            for await output in stream {
                switch output {
                case .message(let msg):
                    receivedMessages.append(msg)
                case .status(let status):
                    statuses.append(status)
                    if status == .live {
                        return
                    }
                case .event:
                    break
                }
            }
        }

        await consumer.value
        await source.stop()

        #expect(receivedMessages.count == 1)
        #expect(receivedMessages.first?.text.contains("482913") == true)
        #expect(statuses.contains(.connecting))
        #expect(statuses.contains(.live))
    }

    // MARK: - 2. Authentication Failure Propagation

    @Test @MainActor func authenticationFailureReportsStatus() async {
        let account = makeAccount()
        let mock = MockIMAPConnection(shouldFailAuth: true)
        let source = AetherIMAPSource(account: account, retryDelay: 0, connection: { mock })

        var reportedStatuses: [SourceStatus] = []
        let stream = source.messages()

        let consumer = Task {
            for await output in stream {
                if case .status(let s) = output {
                    reportedStatuses.append(s)
                    if s.needsSignIn {
                        return
                    }
                }
            }
        }

        await consumer.value
        await source.stop()

        #expect(reportedStatuses.contains(where: { $0.needsSignIn }))
    }

    // MARK: - 3. Connection Loss & Reconnection

    @Test @MainActor func connectionLossTriggersReconnect() async {
        let account = makeAccount()
        let mock = MockIMAPConnection(shouldDisconnect: true)
        let source = AetherIMAPSource(account: account, retryDelay: 0.01, connection: { mock })

        var statuses: [SourceStatus] = []
        let stream = source.messages()

        let consumer = Task {
            for await output in stream {
                if case .status(let s) = output {
                    statuses.append(s)
                    if s == .live {
                        return
                    }
                }
            }
        }

        await consumer.value
        await source.stop()

        let openCount = await mock.openedCount
        #expect(openCount >= 2)
        #expect(statuses.contains(.live))
    }

    // MARK: - 4. Explicit Stop & Idempotency

    @Test @MainActor func explicitStopIsIdempotent() async {
        let account = makeAccount()
        let mock = MockIMAPConnection()
        let source = AetherIMAPSource(account: account, retryDelay: 0, connection: { mock })

        let stream = source.messages()
        let consumer = Task {
            for await _ in stream {}
        }

        try? await Task.sleep(for: .milliseconds(30))
        await source.stop()
        await source.stop()
        await source.stop()
        await consumer.value

        let closed = await mock.closedCount
        #expect(closed >= 1)
    }

    // MARK: - 5. Consumer Cancellation

    @Test @MainActor func consumerCancellationTerminatesGracefully() async {
        let account = makeAccount()
        let mock = MockIMAPConnection()
        let source = AetherIMAPSource(account: account, retryDelay: 0, connection: { mock })

        let stream = source.messages()
        let consumer = Task {
            for await _ in stream {
                if Task.isCancelled { break }
            }
        }

        try? await Task.sleep(for: .milliseconds(30))
        consumer.cancel()
        await source.stop()
        await consumer.value

        #expect(consumer.isCancelled)
    }
}
