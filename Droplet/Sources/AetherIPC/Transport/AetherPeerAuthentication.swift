import Darwin
import Foundation
import Security

/// Verified identity of a connected IPC peer process.
public struct AetherPeerIdentity: Equatable, Sendable, CustomStringConvertible {
    public let identifier: String
    public let team: String?
    public let pid: pid_t

    public init(identifier: String, team: String?, pid: pid_t) {
        self.identifier = identifier
        self.team = team
        self.pid = pid
    }

    public var description: String {
        "AetherPeerIdentity(id: \(identifier), team: \(team ?? "nil"), pid: \(pid))"
    }
}

/// Abstraction for validating the identity of an accepted socket connection.
public protocol AetherPeerAuthenticating: Sendable {
    func authenticatePeer(fileDescriptor: Int32) throws -> AetherPeerIdentity
}

/// Production peer validator for Droppy application process connections.
///
/// Obtains the peer's Darwin kernel audit token via `LOCAL_PEERTOKEN`, resolves the
/// code signature via Security.framework, and enforces that:
/// 1. The code signature chains to Apple Generic anchor.
/// 2. The bundle identifier matches `expectedIdentifier` (default: `"iordv.Droppy"`).
/// 3. The Developer ID Team matches `expectedTeamID` (default: `"NARHG44L48"`).
///
/// In production configurations, unsigned, ad-hoc, or mismatched peers FAIL CLOSED.
public struct AetherDroppyPeerValidator: AetherPeerAuthenticating {
    public static let defaultExpectedIdentifier = "iordv.Droppy"
    public static let defaultExpectedTeamID = "NARHG44L48"

    public let expectedIdentifier: String
    public let expectedTeamID: String

    #if DEBUG
        public var developmentAllowUnsigned: Bool
        public var developmentMockIdentity: AetherPeerIdentity?

        public init(
            expectedIdentifier: String = defaultExpectedIdentifier,
            expectedTeamID: String = defaultExpectedTeamID,
            developmentAllowUnsigned: Bool = false
        ) {
            self.expectedIdentifier = expectedIdentifier
            self.expectedTeamID = expectedTeamID
            self.developmentAllowUnsigned = developmentAllowUnsigned
            self.developmentMockIdentity = nil
        }
    #else
        public init(
            expectedIdentifier: String = defaultExpectedIdentifier,
            expectedTeamID: String = defaultExpectedTeamID
        ) {
            self.expectedIdentifier = expectedIdentifier
            self.expectedTeamID = expectedTeamID
        }
    #endif

    public func authenticatePeer(fileDescriptor fd: Int32) throws -> AetherPeerIdentity {
        #if DEBUG
            if let mock = developmentMockIdentity {
                return mock
            }
        #endif

        // 1. Query Darwin kernel for audit token
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else {
            #if DEBUG
                if developmentAllowUnsigned {
                    var pid: pid_t = 0
                    var pidLen = socklen_t(MemoryLayout<pid_t>.size)
                    _ = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidLen)
                    return AetherPeerIdentity(identifier: expectedIdentifier, team: expectedTeamID, pid: pid)
                }
            #endif
            throw AetherTransportError.peerAuditTokenMissing
        }

        // Extract PID from audit token
        var pid: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        _ = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidLen)

        // 2. Resolve SecCode from audit token data
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        var secCode: SecCode?
        let attributes = [kSecGuestAttributeAudit: tokenData as CFData] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &secCode) == errSecSuccess,
            let secCode
        else {
            #if DEBUG
                if developmentAllowUnsigned {
                    return AetherPeerIdentity(identifier: expectedIdentifier, team: expectedTeamID, pid: pid)
                }
            #endif
            throw AetherTransportError.unsignedPeerRejected
        }

        // 3. Compile Security Requirement
        var requirement: SecRequirement?
        let reqString = "identifier \"\(expectedIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamID)\"" as CFString
        guard SecRequirementCreateWithString(reqString, [], &requirement) == errSecSuccess,
            let requirement
        else {
            throw AetherTransportError.peerAuthenticationFailed("SecRequirement compilation failed")
        }

        // 4. Validate Code Validity Against Requirement
        let validityStatus = SecCodeCheckValidity(secCode, SecCSFlags(rawValue: 0), requirement)
        guard validityStatus == errSecSuccess else {
            // Read signing info to provide specific diagnostics
            var staticCode: SecStaticCode?
            if SecCodeCopyStaticCode(secCode, [], &staticCode) == errSecSuccess, let staticCode {
                var infoDict: CFDictionary?
                if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoDict) == errSecSuccess,
                    let dict = infoDict as? [String: Any]
                {
                    let actualID = dict[kSecCodeInfoIdentifier as String] as? String ?? "unknown"
                    let actualTeam = dict[kSecCodeInfoTeamIdentifier as String] as? String ?? "none"
                    if actualID != expectedIdentifier {
                        throw AetherTransportError.peerIdentityMismatch(expected: expectedIdentifier, actual: actualID)
                    }
                    if actualTeam != expectedTeamID {
                        throw AetherTransportError.peerTeamMismatch(expected: expectedTeamID, actual: actualTeam)
                    }
                }
            }
            throw AetherTransportError.peerAuthenticationFailed("Validity check returned status \(validityStatus)")
        }

        return AetherPeerIdentity(identifier: expectedIdentifier, team: expectedTeamID, pid: pid)
    }
}

/// Production peer validator for verifying the AETHER host process (CodeCatch) from the Droppy client.
///
/// Obtains the server's Darwin kernel audit token via `LOCAL_PEERTOKEN`, resolves the
/// code signature via Security.framework, and enforces that:
/// 1. The server process runs under the same UID as the client (`getuid()`).
/// 2. The code signature chains to Apple Generic anchor (or matches in development).
/// 3. The bundle identifier matches `expectedIdentifier` (default: `"com.uros.codecatch"`).
/// 4. If `expectedTeamID` is specified, verifies Developer ID Team matches.
public struct AetherHostPeerValidator: AetherPeerAuthenticating {
    public static let defaultExpectedIdentifier = "com.uros.codecatch"

    public let expectedIdentifier: String
    public let expectedTeamID: String?

    #if DEBUG
        public var developmentAllowUnsigned: Bool
        public var developmentMockIdentity: AetherPeerIdentity?

        public init(
            expectedIdentifier: String = defaultExpectedIdentifier,
            expectedTeamID: String? = nil,
            developmentAllowUnsigned: Bool = false
        ) {
            self.expectedIdentifier = expectedIdentifier
            self.expectedTeamID = expectedTeamID
            self.developmentAllowUnsigned = developmentAllowUnsigned
            self.developmentMockIdentity = nil
        }
    #else
        public init(
            expectedIdentifier: String = defaultExpectedIdentifier,
            expectedTeamID: String? = nil
        ) {
            self.expectedIdentifier = expectedIdentifier
            self.expectedTeamID = expectedTeamID
        }
    #endif

    public func authenticatePeer(fileDescriptor fd: Int32) throws -> AetherPeerIdentity {
        #if DEBUG
            if let mock = developmentMockIdentity {
                return mock
            }
        #endif

        // 1. Query Darwin kernel for audit token
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else {
            #if DEBUG
                if developmentAllowUnsigned {
                    var pid: pid_t = 0
                    var pidLen = socklen_t(MemoryLayout<pid_t>.size)
                    _ = getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidLen)
                    return AetherPeerIdentity(identifier: expectedIdentifier, team: expectedTeamID, pid: pid)
                }
            #endif
            throw AetherTransportError.peerAuditTokenMissing
        }

        // Verify UID matches current user
        let peerUID = token.val.1  // euid in Darwin audit_token_t
        let currentUID = getuid()
        guard peerUID == currentUID else {
            throw AetherTransportError.peerUIDMismatch(expected: currentUID, actual: peerUID)
        }

        // Extract PID
        let pid = pid_t(token.val.5)  // pid in Darwin audit_token_t

        // 2. Resolve SecCode from audit token data
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        var secCode: SecCode?
        let attributes = [kSecGuestAttributeAudit: tokenData as CFData] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &secCode) == errSecSuccess,
            let secCode
        else {
            #if DEBUG
                if developmentAllowUnsigned {
                    return AetherPeerIdentity(identifier: expectedIdentifier, team: expectedTeamID, pid: pid)
                }
            #endif
            throw AetherTransportError.unsignedPeerRejected
        }

        // 3. Compile Security Requirement
        var requirement: SecRequirement?
        let reqString: CFString
        if let expectedTeamID {
            reqString = "identifier \"\(expectedIdentifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamID)\"" as CFString
        } else {
            reqString = "identifier \"\(expectedIdentifier)\"" as CFString
        }
        guard SecRequirementCreateWithString(reqString, [], &requirement) == errSecSuccess,
            let requirement
        else {
            throw AetherTransportError.peerAuthenticationFailed("SecRequirement compilation failed")
        }

        // 4. Validate Code Validity Against Requirement
        let validityStatus = SecCodeCheckValidity(secCode, SecCSFlags(rawValue: 0), requirement)
        guard validityStatus == errSecSuccess else {
            var staticCode: SecStaticCode?
            if SecCodeCopyStaticCode(secCode, [], &staticCode) == errSecSuccess, let staticCode {
                var infoDict: CFDictionary?
                if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoDict) == errSecSuccess,
                    let dict = infoDict as? [String: Any]
                {
                    let actualID = dict[kSecCodeInfoIdentifier as String] as? String ?? "unknown"
                    if actualID != expectedIdentifier {
                        throw AetherTransportError.peerIdentityMismatch(expected: expectedIdentifier, actual: actualID)
                    }
                    if let expectedTeamID {
                        let actualTeam = dict[kSecCodeInfoTeamIdentifier as String] as? String ?? "none"
                        if actualTeam != expectedTeamID {
                            throw AetherTransportError.peerTeamMismatch(expected: expectedTeamID, actual: actualTeam)
                        }
                    }
                }
            }
            throw AetherTransportError.peerAuthenticationFailed("Validity check returned status \(validityStatus)")
        }

        return AetherPeerIdentity(identifier: expectedIdentifier, team: expectedTeamID, pid: pid)
    }
}
