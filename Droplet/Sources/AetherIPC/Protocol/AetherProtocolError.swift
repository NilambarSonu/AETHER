import Foundation

/// Strongly typed protocol errors for AETHER IPC serialization and validation.
///
/// Security: Does NOT expose OTP values, email contents, or credentials in descriptions.
public enum AetherProtocolError: Error, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case unsupportedProtocolVersion(Int)
    case invalidEventID
    case emptyOTPCode
    case invalidOTPCharacters
    case invalidOTPLength(Int)
    case emptyServiceLabel
    case oversizedServiceLabel(Int)
    case invalidControlCharactersInLabel
    case invalidTimestamps
    case excessiveLifetime(TimeInterval)
    case expiredEvent(Date)
    case payloadExceedsSizeLimit(Int)
    case zeroLengthFrame
    case oversizedFrame(Int)
    case decoderBufferExceeded(Int)
    case malformedJSON(String)
    case invalidHeaderBytes

    public var description: String {
        switch self {
        case .unsupportedProtocolVersion(let v):
            return "Unsupported protocol version: \(v)"
        case .invalidEventID:
            return "Event ID is invalid"
        case .emptyOTPCode:
            return "OTP code is empty"
        case .invalidOTPCharacters:
            return "OTP code contains invalid characters (must be ASCII alphanumeric or hyphen)"
        case .invalidOTPLength(let len):
            return "OTP code length \(len) is out of bounds (allowed: 3...64 characters)"
        case .emptyServiceLabel:
            return "Service label is empty"
        case .oversizedServiceLabel(let len):
            return "Service label length \(len) exceeds maximum allowed (128 characters)"
        case .invalidControlCharactersInLabel:
            return "Service label contains forbidden control characters"
        case .invalidTimestamps:
            return "Invalid timestamps: createdAt must be before expiresAt"
        case .excessiveLifetime(let secs):
            return "Event lifetime \(Int(secs))s exceeds maximum allowed (1800s)"
        case .expiredEvent(let exp):
            return "Event has already expired at \(exp)"
        case .payloadExceedsSizeLimit(let sz):
            return "Payload size \(sz) bytes exceeds maximum frame size (4096 bytes)"
        case .zeroLengthFrame:
            return "Frame length cannot be zero"
        case .oversizedFrame(let sz):
            return "Declared frame size \(sz) bytes exceeds maximum allowed (4096 bytes)"
        case .decoderBufferExceeded(let sz):
            return "Decoder buffer size \(sz) bytes exceeded maximum buffer guard (16384 bytes)"
        case .malformedJSON(let msg):
            return "Malformed JSON payload: \(msg)"
        case .invalidHeaderBytes:
            return "Invalid frame header bytes"
        }
    }

    public var debugDescription: String { description }
}
