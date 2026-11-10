import Foundation

/// Strongly-typed, redacted error representations for AETHER IPC transport failures.
public enum AetherTransportError: Error, Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    case socketPathTooLong(Int)
    case parentDirectoryInsecure(String)
    case parentDirectoryIsSymlink
    case parentDirectoryNotOwnedByUser
    case anotherHostInstanceRunning
    case socketBindFailed(Int32)
    case socketListenFailed(Int32)
    case peerAuthenticationFailed(String)
    case peerAuditTokenMissing
    case peerIdentityMismatch(expected: String, actual: String)
    case peerTeamMismatch(expected: String, actual: String)
    case unsignedPeerRejected
    case handshakeTimedOut
    case handshakeTokenMismatch
    case handshakeMalformed(String)
    case handshakeProtocolVersionMismatch(UInt32)
    case noActiveClientSession
    case clientDisconnected
    case clientAlreadyConnected
    case writeFailed(Int32)
    case serverStopped
    case tokenFileCreationFailed
    case lockAcquisitionFailed(Int32)
    case socketConnectFailed(Int32)
    case tokenFileNotFound(String)
    case tokenFileInsecure(String)
    case clientStopped
    case peerUIDMismatch(expected: uid_t, actual: uid_t)

    public var description: String {
        switch self {
        case .socketPathTooLong(let length):
            return "Socket path exceeds Darwin sun_path limit of 103 bytes (actual: \(length) bytes)"
        case .parentDirectoryInsecure(let msg):
            return "Parent directory permissions insecure: \(msg)"
        case .parentDirectoryIsSymlink:
            return "Parent directory is a symlink (rejected for security)"
        case .parentDirectoryNotOwnedByUser:
            return "Parent directory is not owned by current user"
        case .anotherHostInstanceRunning:
            return "Another AETHER host instance holds the socket lock"
        case .socketBindFailed(let code):
            return "Socket bind() failed with errno \(code)"
        case .socketListenFailed(let code):
            return "Socket listen() failed with errno \(code)"
        case .peerAuthenticationFailed(let reason):
            return "Peer authentication failed: \(reason)"
        case .peerAuditTokenMissing:
            return "Darwin kernel audit token could not be obtained from socket"
        case .peerIdentityMismatch(let expected, let actual):
            return "Peer bundle identifier mismatch (expected '\(expected)', got '\(actual)')"
        case .peerTeamMismatch(let expected, let actual):
            return "Peer Team ID mismatch (expected '\(expected)', got '\(actual)')"
        case .unsignedPeerRejected:
            return "Unsigned or invalidly signed peer rejected"
        case .handshakeTimedOut:
            return "Client handshake timed out before receiving valid session token"
        case .handshakeTokenMismatch:
            return "Client session token mismatch (authentication rejected)"
        case .handshakeMalformed(let details):
            return "Malformed handshake frame: \(details)"
        case .handshakeProtocolVersionMismatch(let version):
            return "Handshake protocol version mismatch (received \(version), expected 1)"
        case .noActiveClientSession:
            return "No authenticated Droppy client session is currently connected"
        case .clientDisconnected:
            return "Client session disconnected"
        case .clientAlreadyConnected:
            return "Another client connection arrived while an active session exists"
        case .writeFailed(let code):
            return "Socket write failed with errno \(code)"
        case .serverStopped:
            return "Transport server has been stopped"
        case .tokenFileCreationFailed:
            return "Failed to securely create ephemeral session token file"
        case .lockAcquisitionFailed(let code):
            return "Failed to acquire exclusive lock on socket lock file (errno \(code))"
        case .socketConnectFailed(let code):
            return "Socket connect() failed with errno \(code)"
        case .tokenFileNotFound(let path):
            return "Session token file not found at path: \(path)"
        case .tokenFileInsecure(let msg):
            return "Session token file insecure: \(msg)"
        case .clientStopped:
            return "IPC client transport has been stopped"
        case .peerUIDMismatch(let expected, let actual):
            return "Peer process UID mismatch (expected \(expected), actual \(actual))"
        }
    }

    public var debugDescription: String { description }
}
