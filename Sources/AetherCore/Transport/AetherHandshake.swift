import Darwin
import Foundation
import Security

/// Versioned, bounded handshake message transmitted by the client immediately after connection.
public struct AetherHandshakeFrame: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let currentProtocolVersion: UInt32 = 1

    public let protocolVersion: UInt32
    public let sessionToken: String
    public let clientIdentifier: String

    public init(
        protocolVersion: UInt32 = currentProtocolVersion,
        sessionToken: String,
        clientIdentifier: String
    ) {
        self.protocolVersion = protocolVersion
        self.sessionToken = sessionToken
        self.clientIdentifier = clientIdentifier
    }

    public var description: String {
        "AetherHandshakeFrame(v: \(protocolVersion), client: \(clientIdentifier), token: [REDACTED \(sessionToken.count) chars])"
    }

    public var debugDescription: String { description }
}

/// Constant-time comparison utility to prevent timing analysis attacks on session tokens.
public enum AetherSecurityUtils {
    public static func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        guard aBytes.count == bBytes.count else { return false }
        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        return result == 0
    }
}

/// Manages generation, secure filesystem writing, and cleanup of ephemeral session tokens.
///
/// ## Threat Model & POSIX DAC Guarantees
/// Standard POSIX file permissions (0600) and directory permissions (0700) isolate
/// different operating system user accounts. On macOS, any process running under the
/// SAME user account (UID) has kernel permission to read files owned by that user.
///
/// Therefore, the ephemeral session token provides:
/// 1. Defense against blind port scans and opportunistic local probes that do not know the path.
/// 2. Session desynchronization and replay defense across host restarts (the token is freshly
///    generated on every server startup, invalidating any stale client state).
/// 3. Cross-droplet collision defense (prevents unrelated Droppy droplets from accidentally
///    connecting to the AETHER IPC socket).
///
/// The session token does NOT provide isolation against malicious processes running under
/// the same UID that specifically target AETHER. Authoritative peer authentication against
/// same-user adversaries is provided strictly by Darwin kernel audit token inspection
/// (`LOCAL_PEERTOKEN`) and code-signature verification (`SecCodeCheckValidity`).
public final class AetherSessionTokenManager: @unchecked Sendable {
    public let tokenPath: String
    private(set) public var currentToken: String?
    private(set) public var boundInode: ino_t?
    private(set) public var boundDev: dev_t?
    private let lock = NSLock()

    public init(tokenPath: String? = nil) {
        if let tokenPath {
            self.tokenPath = tokenPath
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.tokenPath = appSupport.appendingPathComponent("Aether/session.token").path
        }
    }

    /// Generates 256 bits of cryptographically secure randomness, writes it to a 0600 file, and returns the token.
    public func generateAndPersistToken() throws -> String {
        lock.lock()
        defer { lock.unlock() }

        var randomBytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes) == errSecSuccess else {
            throw AetherTransportError.tokenFileCreationFailed
        }
        let tokenHex = randomBytes.map { String(format: "%02x", $0) }.joined()

        let parentDir = (tokenPath as NSString).deletingLastPathComponent
        try AetherSocketEndpoint.validateAndCreateParentDirectory(parentDir)

        // Open with O_NOFOLLOW to reject symlinks; mode 0600
        let fd = open(tokenPath, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            throw AetherTransportError.tokenFileCreationFailed
        }
        defer { close(fd) }

        // Verify inode is a regular file owned by current user
        var st = stat()
        guard fstat(fd, &st) == 0,
            (st.st_mode & S_IFMT) == S_IFREG,
            st.st_uid == getuid()
        else {
            unlink(tokenPath)
            throw AetherTransportError.tokenFileCreationFailed
        }

        let data = Data(tokenHex.utf8)
        let written = data.withUnsafeBytes { raw in
            write(fd, raw.baseAddress!, raw.count)
        }
        guard written == data.count else {
            unlink(tokenPath)
            throw AetherTransportError.tokenFileCreationFailed
        }

        fchmod(fd, 0o600)
        self.boundInode = st.st_ino
        self.boundDev = st.st_dev
        self.currentToken = tokenHex
        return tokenHex
    }

    /// Safely cleans up the session token file from disk, verifying inode identity before unlinking.
    public func cleanup() {
        lock.lock()
        defer { lock.unlock() }
        if let boundInode, let boundDev {
            var checkStat = stat()
            if lstat(tokenPath, &checkStat) == 0 {
                if checkStat.st_ino == boundInode && checkStat.st_dev == boundDev {
                    unlink(tokenPath)
                }
            }
            self.boundInode = nil
            self.boundDev = nil
        } else {
            unlink(tokenPath)
        }
        currentToken = nil
    }
}
