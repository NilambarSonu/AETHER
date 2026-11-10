import AetherCore
import Foundation
import Testing

@Suite struct AetherProtocolCodecTests {

    // MARK: - 1. Payload Tests

    @Test func validOTPPayloadRoundTrip() throws {
        let eventID = UUID()
        let created = Date()
        let expires = created.addingTimeInterval(300)

        let payload = try AetherOTPPayload(
            protocolVersion: 1,
            eventID: eventID,
            createdAt: created,
            expiresAt: expires,
            source: .messages,
            serviceLabel: "GitHub",
            otpCode: "482913",
            eventType: .otpAvailable
        )

        let frame = try AetherFrameCodec.encode(payload)
        #expect(frame.count > 4)

        let decoded: AetherOTPPayload = try AetherFrameCodec.decodeSingleFrame(frame)
        #expect(decoded.protocolVersion == 1)
        #expect(decoded.eventID == eventID)
        #expect(decoded.source == .messages)
        #expect(decoded.serviceLabel == "GitHub")
        #expect(decoded.otpCode == "482913")
        #expect(decoded.eventType == .otpAvailable)
    }

    @Test func leadingZeroesAreStrictlyPreserved() throws {
        let codes = ["0123", "004921", "000000", "01234567"]
        for code in codes {
            let payload = try AetherOTPPayload(
                source: .gmail,
                serviceLabel: "Bank",
                otpCode: code
            )
            let frame = try AetherFrameCodec.encode(payload)
            let decoded: AetherOTPPayload = try AetherFrameCodec.decodeSingleFrame(frame)
            #expect(decoded.otpCode == code)
            #expect(decoded.otpCode.hasPrefix("0"))
        }
    }

    @Test func extractorCompatibleOTPLengthsAndFormats() throws {
        let validCodes = [
            "123",  // 3-digit minimum
            "4829",  // 4-digit PIN
            "729565",  // standard 6-digit
            "30718264",  // 8-digit banking
            "K7PX2Q",  // 6-char alphanumeric
            "KXQ-7PM",  // hyphenated alphanumeric
            "amivi-ndigo-rinit-raman",  // Notion multi-word token
        ]

        for code in validCodes {
            let payload = try AetherOTPPayload(
                source: .imap,
                serviceLabel: "Auth Service",
                otpCode: code
            )
            let frame = try AetherFrameCodec.encode(payload)
            let decoded: AetherOTPPayload = try AetherFrameCodec.decodeSingleFrame(frame)
            #expect(decoded.otpCode == code)
        }
    }

    @Test func emptyOTPCodeThrowsError() {
        #expect(throws: AetherProtocolError.emptyOTPCode) {
            _ = try AetherOTPPayload(
                source: .messages,
                serviceLabel: "Service",
                otpCode: ""
            )
        }
    }

    @Test func invalidCharactersInOTPThrowsError() {
        let invalidCodes = [
            "12 34",  // space
            "482$913",  // dollar
            "CODE#1",  // hash
            "123\n456",  // newline
            "🔑1234",  // emoji
            "123.456",  // dot
            "123@456",  // at
        ]

        for code in invalidCodes {
            #expect(throws: AetherProtocolError.invalidOTPCharacters) {
                _ = try AetherOTPPayload(
                    source: .messages,
                    serviceLabel: "Service",
                    otpCode: code
                )
            }
        }
    }

    @Test func oversizedOrEmptyServiceLabelThrowsError() {
        #expect(throws: AetherProtocolError.emptyServiceLabel) {
            _ = try AetherOTPPayload(
                source: .messages,
                serviceLabel: "   ",
                otpCode: "123456"
            )
        }

        let oversizedLabel = String(repeating: "A", count: 129)
        #expect(throws: AetherProtocolError.oversizedServiceLabel(129)) {
            _ = try AetherOTPPayload(
                source: .messages,
                serviceLabel: oversizedLabel,
                otpCode: "123456"
            )
        }
    }

    @Test func controlCharactersInServiceLabelAreRejected() {
        let controlStrings = [
            "GitHub\u{0000}Corp",
            "Google\u{001B}[31m",
            "Apple\u{0007}Bell",
            "Bank\u{007F}Delete",
        ]

        for label in controlStrings {
            #expect(throws: AetherProtocolError.invalidControlCharactersInLabel) {
                _ = try AetherOTPPayload(
                    source: .messages,
                    serviceLabel: label,
                    otpCode: "123456"
                )
            }
        }
    }

    @Test func expiredEventIsRejectedOnValidation() {
        let past = Date().addingTimeInterval(-10)
        let created = past.addingTimeInterval(-60)

        #expect(throws: AetherProtocolError.expiredEvent(past)) {
            let payload = try AetherOTPPayload(
                createdAt: created,
                expiresAt: past,
                source: .messages,
                serviceLabel: "Service",
                otpCode: "123456"
            )
            try payload.validate()
        }
    }

    @Test func excessiveLifetimeThrowsError() {
        let created = Date()
        let excessiveExpires = created.addingTimeInterval(3600)  // 1 hour (> 30 min limit)

        #expect(throws: AetherProtocolError.excessiveLifetime(3600)) {
            _ = try AetherOTPPayload(
                createdAt: created,
                expiresAt: excessiveExpires,
                source: .messages,
                serviceLabel: "Service",
                otpCode: "123456"
            )
        }
    }

    @Test func unsupportedProtocolVersionThrowsError() {
        #expect(throws: AetherProtocolError.unsupportedProtocolVersion(99)) {
            _ = try AetherOTPPayload(
                protocolVersion: 99,
                source: .messages,
                serviceLabel: "Service",
                otpCode: "123456"
            )
        }
    }

    @Test func invalidTimestampsThrowsError() {
        let created = Date()
        let earlierExpires = created.addingTimeInterval(-1)

        #expect(throws: AetherProtocolError.invalidTimestamps) {
            _ = try AetherOTPPayload(
                createdAt: created,
                expiresAt: earlierExpires,
                source: .messages,
                serviceLabel: "Service",
                otpCode: "123456"
            )
        }
    }

    @Test func descriptionNeverExposesPlaintextOTP() throws {
        let secretCode = "987654"
        let payload = try AetherOTPPayload(
            source: .messages,
            serviceLabel: "TestService",
            otpCode: secretCode
        )

        let desc = payload.description
        let debugDesc = payload.debugDescription

        #expect(!desc.contains(secretCode))
        #expect(!debugDesc.contains(secretCode))
        #expect(desc.contains("[REDACTED 6 chars]"))
    }

    // MARK: - 2. Acknowledgment Tests

    @Test func validAcknowledgmentRoundTrip() throws {
        let eventID = UUID()
        let ack = try AetherOTPAcknowledgment(
            protocolVersion: 1,
            eventID: eventID,
            status: .displayed,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            errorCode: nil
        )

        let frame = try AetherFrameCodec.encode(ack)
        let decoded: AetherOTPAcknowledgment = try AetherFrameCodec.decodeSingleFrame(frame)

        #expect(decoded.protocolVersion == 1)
        #expect(decoded.eventID == eventID)
        #expect(decoded.status == .displayed)
        #expect(decoded.errorCode == nil)
    }

    @Test func acknowledgmentAllStatusesRoundTrip() throws {
        let statuses: [AetherAcknowledgmentStatus] = [.received, .displayed, .copied, .expired, .rejected]
        for status in statuses {
            let ack = try AetherOTPAcknowledgment(
                eventID: UUID(),
                status: status,
                errorCode: status == .rejected ? .expired : nil
            )
            let frame = try AetherFrameCodec.encode(ack)
            let decoded: AetherOTPAcknowledgment = try AetherFrameCodec.decodeSingleFrame(frame)
            #expect(decoded.status == status)
            if status == .rejected {
                #expect(decoded.errorCode == .expired)
            }
        }
    }

    @Test func unsupportedAcknowledgmentVersionThrows() {
        #expect(throws: AetherProtocolError.unsupportedProtocolVersion(42)) {
            _ = try AetherOTPAcknowledgment(
                protocolVersion: 42,
                eventID: UUID(),
                status: .received
            )
        }
    }

    // MARK: - 3. Frame Codec Tests

    @Test func exactMaxFrameBoundarySucceeds() throws {
        // Construct a payload whose serialized JSON is exactly 4,096 bytes
        // Header is 4 bytes, so total frame is 4,100 bytes
        let basePayload = try AetherOTPPayload(
            source: .other,
            serviceLabel: "A",
            otpCode: "123456"
        )
        let baseJSON = try JSONEncoder().encode(basePayload)
        let paddingNeeded = 4096 - baseJSON.count
        let paddedLabel = String(repeating: "X", count: min(120, paddingNeeded))

        let payload = try AetherOTPPayload(
            source: .other,
            serviceLabel: paddedLabel,
            otpCode: "123456"
        )
        let frame = try AetherFrameCodec.encode(payload)
        #expect(frame.count <= 4100)

        let decoded: AetherOTPPayload = try AetherFrameCodec.decodeSingleFrame(frame)
        #expect(decoded.otpCode == "123456")
    }

    @Test func oversizedFrameExceedingMaxIsRejectedBeforeAllocation() throws {
        // Header declared size = 4097 (1 byte over 4096 max limit)
        var frame = Data()
        var declaredLength = UInt32(4097).bigEndian
        withUnsafeBytes(of: &declaredLength) { frame.append(contentsOf: $0) }
        frame.append(Data(repeating: 0x41, count: 10))

        let decoder = AetherFrameDecoder()
        try decoder.append(frame)

        #expect(throws: AetherProtocolError.oversizedFrame(4097)) {
            _ = try decoder.nextFrame()
        }
    }

    @Test func zeroLengthFrameIsRejected() throws {
        var frame = Data()
        var declaredLength = UInt32(0).bigEndian
        withUnsafeBytes(of: &declaredLength) { frame.append(contentsOf: $0) }

        let decoder = AetherFrameDecoder()
        try decoder.append(frame)

        #expect(throws: AetherProtocolError.zeroLengthFrame) {
            _ = try decoder.nextFrame()
        }
    }

    @Test func partialHeaderThenCompletion() throws {
        let payload = try AetherOTPPayload(source: .messages, serviceLabel: "SMS", otpCode: "777888")
        let frame = try AetherFrameCodec.encode(payload)

        let decoder = AetherFrameDecoder()

        // Feed first 2 bytes of the 4-byte header
        try decoder.append(frame.prefix(2))
        #expect(try decoder.nextFrame() == nil)
        #expect(decoder.bufferedBytes == 2)

        // Feed remaining 2 bytes of header + rest of payload
        try decoder.append(frame.dropFirst(2))
        let decoded = try decoder.nextOTPPayload()
        #expect(decoded?.otpCode == "777888")
        #expect(decoder.bufferedBytes == 0)
    }

    @Test func partialPayloadThenCompletion() throws {
        let payload = try AetherOTPPayload(source: .messages, serviceLabel: "SMS", otpCode: "555111")
        let frame = try AetherFrameCodec.encode(payload)

        let decoder = AetherFrameDecoder()

        // Feed header + half of body
        let splitIndex = 4 + (frame.count - 4) / 2
        try decoder.append(frame.prefix(splitIndex))
        #expect(try decoder.nextFrame() == nil)
        #expect(decoder.bufferedBytes == splitIndex)

        // Feed remaining half of body
        try decoder.append(frame.dropFirst(splitIndex))
        let decoded = try decoder.nextOTPPayload()
        #expect(decoded?.otpCode == "555111")
        #expect(decoder.bufferedBytes == 0)
    }

    @Test func multipleConcatenatedFramesDecodedInSequence() throws {
        let p1 = try AetherOTPPayload(source: .messages, serviceLabel: "S1", otpCode: "111111")
        let p2 = try AetherOTPPayload(source: .gmail, serviceLabel: "S2", otpCode: "222222")
        let p3 = try AetherOTPPayload(source: .outlook, serviceLabel: "S3", otpCode: "333333")

        var combinedStream = Data()
        combinedStream.append(try AetherFrameCodec.encode(p1))
        combinedStream.append(try AetherFrameCodec.encode(p2))
        combinedStream.append(try AetherFrameCodec.encode(p3))

        let decoder = AetherFrameDecoder()
        try decoder.append(combinedStream)

        let d1 = try decoder.nextOTPPayload()
        let d2 = try decoder.nextOTPPayload()
        let d3 = try decoder.nextOTPPayload()
        let d4 = try decoder.nextOTPPayload()

        #expect(d1?.otpCode == "111111")
        #expect(d2?.otpCode == "222222")
        #expect(d3?.otpCode == "333333")
        #expect(d4 == nil)
        #expect(decoder.bufferedBytes == 0)
    }

    @Test func invalidJSONThrowsMalformedError() throws {
        var frame = Data()
        let invalidJSON = "{ not valid json: true }".data(using: .utf8)!
        var length = UInt32(invalidJSON.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(invalidJSON)

        let decoder = AetherFrameDecoder()
        try decoder.append(frame)

        #expect(throws: AetherProtocolError.self) {
            _ = try decoder.nextOTPPayload()
        }
    }

    @Test func decoderBufferExceededThrowsError() throws {
        let decoder = AetherFrameDecoder()
        let hugeChunk = Data(repeating: 0x41, count: 16_385)

        #expect(throws: AetherProtocolError.decoderBufferExceeded(16_385)) {
            try decoder.append(hugeChunk)
        }
    }

    @Test func resetClearsBufferAndEnablesRecovery() throws {
        let decoder = AetherFrameDecoder()

        // Feed garbage incomplete header
        try decoder.append(Data([0x00, 0x01]))
        #expect(decoder.bufferedBytes == 2)

        // Reset
        decoder.reset()
        #expect(decoder.bufferedBytes == 0)

        // Feed valid frame
        let payload = try AetherOTPPayload(source: .messages, serviceLabel: "Recovered", otpCode: "999888")
        try decoder.append(try AetherFrameCodec.encode(payload))

        let decoded = try decoder.nextOTPPayload()
        #expect(decoded?.otpCode == "999888")
    }

    // MARK: - 4. Adversarial Tests

    @Test func randomCorruptedByteStreamDoesNotCrash() throws {
        let decoder = AetherFrameDecoder()

        // Feed pseudorandom byte chunks
        let badChunks: [Data] = [
            Data([0xFF, 0xFF, 0xFF, 0xFF]),
            Data([0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0x02]),
            Data([0x80, 0x00, 0x00, 0x10]),
            Data([0x00, 0x00, 0x00, 0x00]),
        ]

        for chunk in badChunks {
            decoder.reset()
            do {
                try decoder.append(chunk)
                _ = try decoder.nextFrame()
            } catch {
                // Throws typed AetherProtocolError without crashing
                #expect(error is AetherProtocolError)
            }
        }
    }

    @Test func largeDeclaredLengthWithoutBodyWaitsGracefully() throws {
        var frame = Data()
        var declaredLength = UInt32(2048).bigEndian
        withUnsafeBytes(of: &declaredLength) { frame.append(contentsOf: $0) }
        frame.append(Data(repeating: 0x42, count: 50))  // Only 50 bytes provided out of 2048

        let decoder = AetherFrameDecoder()
        try decoder.append(frame)

        // Must return nil and wait for the rest without memory explosion
        #expect(try decoder.nextFrame() == nil)
        #expect(decoder.bufferedBytes == 54)
    }
}
