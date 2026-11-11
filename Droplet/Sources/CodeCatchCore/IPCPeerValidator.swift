import Foundation

public enum IPCPeerRole: Sendable {
    /// Validating the server (executed by the CLI)
    case server
    /// Validating the client (executed by the Server)
    case client
}

public enum IPCPeerValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    case peerIdentityMissing
    case localIdentityMissing
    case identifierMismatch(expected: String, actual: String)
    case teamMissing(party: String)
    case teamMismatch(expected: String, actual: String)
    case unsignedPeerRejected
    case developmentBypassRejectedInProduction

    public var description: String {
        switch self {
        case .peerIdentityMissing:
            return "Peer code signature could not be verified."
        case .localIdentityMissing:
            return "Local process code signature or Team ID is missing."
        case .identifierMismatch(let expected, let actual):
            return "Identifier mismatch (expected '\(expected)', got '\(actual)')."
        case .teamMissing(let party):
            return "\(party.capitalized) code signature does not contain a Team ID."
        case .teamMismatch(let expected, let actual):
            return "Team ID mismatch (expected '\(expected)', got '\(actual)')."
        case .unsignedPeerRejected:
            return "Unsigned peer rejected in development mode."
        case .developmentBypassRejectedInProduction:
            return "Development bypass attempt rejected in production."
        }
    }
}

public enum IPCPeerValidationResult: Equatable, Sendable {
    case valid
    case invalid(IPCPeerValidationError)

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    public var error: IPCPeerValidationError? {
        if case .invalid(let err) = self { return err }
        return nil
    }
}

public struct IPCPeerValidator {
    /// Validates code-signing identities for IPC peers.
    ///
    /// In Production builds:
    /// - Both local and peer MUST have valid signatures chaining to Apple Generic.
    /// - Both MUST have valid, non-empty Team IDs.
    /// - Team IDs MUST match exactly.
    /// - Peer identifier MUST match expected role identifier (`appIdentifier` or `cliIdentifier`).
    /// - Any missing signature, team mismatch, or development bypass attempt FAILS CLOSED.
    ///
    /// In Development builds (`#if DEBUG`):
    /// - If both have teams, team match is enforced.
    /// - Unsigned/ad-hoc peers are ONLY permitted if `developmentAllowUnsigned` is explicitly enabled.
    public static func validate(
        peer: CodeSignature.Identity?,
        local: CodeSignature.Identity?,
        role: IPCPeerRole,
        isDevelopmentBuild: Bool = false,
        developmentAllowUnsigned: Bool = false
    ) -> IPCPeerValidationResult {
        let expectedPeerIdentifier = (role == .server) ? AgentWire.appIdentifier : AgentWire.cliIdentifier

        // 1. Production Policy: Strict mutual authentication: bundle ID + Team ID matching Apple Generic anchor.
        if !isDevelopmentBuild {
            // Reject any attempt to enable development bypass when isDevelopmentBuild is false
            if developmentAllowUnsigned {
                return .invalid(.developmentBypassRejectedInProduction)
            }
            guard let peer else {
                return .invalid(.peerIdentityMissing)
            }
            guard peer.identifier == expectedPeerIdentifier else {
                return .invalid(.identifierMismatch(expected: expectedPeerIdentifier, actual: peer.identifier))
            }
            guard let localTeam = local?.team, !localTeam.isEmpty else {
                return .invalid(.localIdentityMissing)
            }
            guard let peerTeam = peer.team, !peerTeam.isEmpty else {
                return .invalid(.teamMissing(party: "peer"))
            }
            guard peerTeam == localTeam else {
                return .invalid(.teamMismatch(expected: localTeam, actual: peerTeam))
            }
            return .valid
        }

        // 2. Development Mode (isDevelopmentBuild == true):
        #if DEBUG
        // If peer identity exists, verify identifier
        if let peer {
            guard peer.identifier == expectedPeerIdentifier else {
                return .invalid(.identifierMismatch(expected: expectedPeerIdentifier, actual: peer.identifier))
            }
            // If both local and peer have teams, enforce team match even in dev
            if let localTeam = local?.team, !localTeam.isEmpty,
               let peerTeam = peer.team, !peerTeam.isEmpty {
                guard peerTeam == localTeam else {
                    return .invalid(.teamMismatch(expected: localTeam, actual: peerTeam))
                }
                return .valid
            }
        }

        // If peer or local is unsigned/ad-hoc:
        if developmentAllowUnsigned {
            return .valid
        } else {
            if peer == nil {
                return .invalid(.peerIdentityMissing)
            }
            return .invalid(.unsignedPeerRejected)
        }
        #else
        // In release compilations, this branch can never be reached, but fail closed unconditionally.
        return .invalid(.developmentBypassRejectedInProduction)
        #endif
    }
}
