import CodeCatchCore
import Foundation
import Testing

@testable import CodeCatch

@Suite struct AetherMailSourceTests {
    @Test func fixtureSourceStreamsMessagesAndFeedsOTPExtraction() async {
        let msg1 = IncomingMessage(
            text: "Your GitHub verification code is: 482913",
            subject: "GitHub Security Code",
            senderName: "GitHub",
            senderID: "support@github.com",
            sourceKey: "test-src",
            sourceLabel: "GitHub",
            date: Date(),
            isMail: true)

        let msg2 = IncomingMessage(
            text: "Sign in to your Slack workspace with code 718294.",
            subject: "Your Slack confirmation code",
            senderName: "Slack",
            senderID: "no-reply@slack.com",
            sourceKey: "test-src",
            sourceLabel: "Slack",
            date: Date(),
            isMail: true)

        let source = FixtureMailSource(sourceKey: "test-src", sourceLabel: "Test Mail", messages: [msg1, msg2])
        var extractedCodes: [String] = []
        var statuses: [SourceStatus] = []

        let stream = source.messages()
        let consumerTask = Task {
            for await output in stream {
                switch output {
                case .message(let message):
                    if let detected = CodeExtractor.detect(in: message.fullText) {
                        extractedCodes.append(detected.code)
                    }
                case .status(let status):
                    statuses.append(status)
                case .event:
                    break
                }
            }
        }

        // Give consumer a moment to process the in-memory stream
        try? await Task.sleep(for: .milliseconds(50))
        await source.stop()
        await consumerTask.value

        #expect(extractedCodes == ["482913", "718294"])
        #expect(statuses.contains(.connecting))
        #expect(statuses.contains(.live))
        #expect(statuses.contains(.off))
    }

    @Test func dynamicDeliveryStreamsIncomingMessage() async {
        let source = FixtureMailSource(sourceKey: "dynamic-src", sourceLabel: "Dynamic Mail", messages: [])
        var receivedCodes: [String] = []

        let stream = source.messages()
        let consumer = Task {
            for await output in stream {
                if case .message(let message) = output {
                    if let detected = CodeExtractor.detect(in: message.fullText) {
                        receivedCodes.append(detected.code)
                    }
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(20))

        let msg = IncomingMessage(
            text: "Your Stripe verification code is 994821. It will expire in 10 minutes.",
            subject: "Verification Code",
            senderName: "Stripe",
            senderID: "notifications@stripe.com",
            sourceKey: "dynamic-src",
            sourceLabel: "Dynamic Mail",
            date: Date(),
            isMail: true)

        source.deliver(msg)

        try? await Task.sleep(for: .milliseconds(50))
        await source.stop()
        await consumer.value

        #expect(receivedCodes == ["994821"])
    }

    @Test func cancellingConsumerTaskStopsStreamGracefully() async {
        let source = FixtureMailSource(sourceKey: "cancel-src", sourceLabel: "Cancel Mail", messages: [])
        let stream = source.messages()

        let consumer = Task {
            for await _ in stream {
                if Task.isCancelled { break }
            }
        }

        try? await Task.sleep(for: .milliseconds(20))
        consumer.cancel()
        await source.stop()
        await consumer.value

        #expect(consumer.isCancelled)
    }
}
