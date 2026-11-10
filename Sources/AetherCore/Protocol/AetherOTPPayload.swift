import Foundation

/// Originating provider source category.
public enum AetherSourceType: String, Codable, Sendable {
    case imap
    case appleMail
    case messages
    case gmail
    case outlook
    case other
}

/// Explicit event type for future extensibility.
public enum AetherEventType: String, Codable, Sendable {
    case otpAvailable
}

/// Versioned, minimal data contract carrying ephemeral verification code events to Droppy.
///
/// Security: Contains ONLY the bare minimum fields required for notch card presentation and copying.
/// No email bodies, subjects, sender addresses, credentials, or tokens are ever contained.
public struct AetherOTPPayload: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let currentProtocolVersion: Int = 1
    public static let maxServiceLabelLength: Int = 128
    public static let minOTPLength: Int = 3
    public static let maxOTPLength: Int = 64
    public static let maxLifetimeSeconds: TimeInterval = 1800  // 30 minutes

    public let protocolVersion: Int
    public let eventID: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public let source: AetherSourceType
    public let serviceLabel: String
    public let otpCode: String
    public let eventType: AetherEventType

    public init(
        protocolVersion: Int = currentProtocolVersion,
        eventID: UUID = UUID(),
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(300),
        source: AetherSourceType,
        serviceLabel: String,
        otpCode: String,
        eventType: AetherEventType = .otpAvailable
    ) throws {
        self.protocolVersion = protocolVersion
        self.eventID = eventID
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.source = source
        self.serviceLabel = serviceLabel
        self.otpCode = otpCode
        self.eventType = eventType

        try validate()
    }

    /// Validates protocol invariants and security bounds.
    public func validate(at referenceDate: Date = Date()) throws {
        guard protocolVersion == Self.currentProtocolVersion else {
            throw AetherProtocolError.unsupportedProtocolVersion(protocolVersion)
        }

        // Bounded service label
        let trimmedLabel = serviceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            throw AetherProtocolError.emptyServiceLabel
        }
        guard serviceLabel.count <= Self.maxServiceLabelLength else {
            throw AetherProtocolError.oversizedServiceLabel(serviceLabel.count)
        }
        guard
            !serviceLabel.contains(where: { char in
                guard let scalar = char.unicodeScalars.first else { return false }
                return (scalar.value < 0x20 && scalar.value != 0x09 && scalar.value != 0x0A && scalar.value != 0x0D)
                    || scalar.value == 0x7F
                    || (scalar.value >= 0x80 && scalar.value <= 0x9F)
            })
        else {
            throw AetherProtocolError.invalidControlCharactersInLabel
        }

        // Bounded OTP string
        guard !otpCode.isEmpty else {
            throw AetherProtocolError.emptyOTPCode
        }
        guard otpCode.count >= Self.minOTPLength && otpCode.count <= Self.maxOTPLength else {
            throw AetherProtocolError.invalidOTPLength(otpCode.count)
        }
        guard
            otpCode.allSatisfy({ char in
                char.isASCII && (char.isLetter || char.isNumber || char == "-")
            })
        else {
            throw AetherProtocolError.invalidOTPCharacters
        }

        // Timestamps
        guard expiresAt > createdAt else {
            throw AetherProtocolError.invalidTimestamps
        }
        let lifetime = expiresAt.timeIntervalSince(createdAt)
        guard lifetime <= Self.maxLifetimeSeconds else {
            throw AetherProtocolError.excessiveLifetime(lifetime)
        }
        guard referenceDate < expiresAt else {
            throw AetherProtocolError.expiredEvent(expiresAt)
        }
    }

    public var description: String {
        "AetherOTPPayload(id: \(eventID), source: \(source.rawValue), service: \(serviceLabel), code: [REDACTED \(otpCode.count) chars], expiresAt: \(expiresAt))"
    }

    public var debugDescription: String { description }
}
