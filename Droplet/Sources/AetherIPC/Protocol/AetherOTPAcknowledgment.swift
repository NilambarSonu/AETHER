import Foundation

/// Delivery and user-action lifecycle status reported back by the client.
public enum AetherAcknowledgmentStatus: String, Codable, Sendable {
    case received
    case displayed
    case copied
    case expired
    case rejected
}

/// Structured protocol error codes for rejected events.
public enum AetherProtocolErrorCode: String, Codable, Sendable {
    case unsupportedVersion
    case malformedPayload
    case expired
    case internalError
    case duplicateEvent
}

/// Versioned acknowledgment payload sent from Droplet back to AETHER Host.
public struct AetherOTPAcknowledgment: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let currentProtocolVersion: Int = 1

    public let protocolVersion: Int
    public let eventID: UUID
    public let status: AetherAcknowledgmentStatus
    public let timestamp: Date
    public let errorCode: AetherProtocolErrorCode?

    public init(
        protocolVersion: Int = currentProtocolVersion,
        eventID: UUID,
        status: AetherAcknowledgmentStatus,
        timestamp: Date = Date(),
        errorCode: AetherProtocolErrorCode? = nil
    ) throws {
        self.protocolVersion = protocolVersion
        self.eventID = eventID
        self.status = status
        self.timestamp = timestamp
        self.errorCode = errorCode

        try validate()
    }

    public func validate() throws {
        guard protocolVersion == Self.currentProtocolVersion else {
            throw AetherProtocolError.unsupportedProtocolVersion(protocolVersion)
        }
    }

    public var description: String {
        "AetherOTPAcknowledgment(id: \(eventID), status: \(status.rawValue), error: \(errorCode?.rawValue ?? "none"), ts: \(timestamp))"
    }

    public var debugDescription: String { description }
}
