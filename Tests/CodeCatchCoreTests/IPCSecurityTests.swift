import Foundation
import Testing

@testable import CodeCatchCore

@Suite struct IPCSecurityTests {
    let myTeam = "ABCDEF1234"
    let attackerTeam = "EVIL999999"

    // MARK: - 1. Valid Same-Team Production Client/Server

    @Test func validSameTeamProductionClientAndServer() {
        let hostIdentity = CodeSignature.Identity(identifier: AgentWire.appIdentifier, team: myTeam)
        let cliIdentity = CodeSignature.Identity(identifier: AgentWire.cliIdentifier, team: myTeam)

        // CLI validating Host
        let cliCheck = IPCPeerValidator.validate(
            peer: hostIdentity, local: cliIdentity, role: .server, isDevelopmentBuild: false)
        #expect(cliCheck == .valid)

        // Host validating CLI
        let hostCheck = IPCPeerValidator.validate(
            peer: cliIdentity, local: hostIdentity, role: .client, isDevelopmentBuild: false)
        #expect(hostCheck == .valid)
    }

    // MARK: - 2. Different-Team Client

    @Test func differentTeamClientRejected() {
        let hostIdentity = CodeSignature.Identity(identifier: AgentWire.appIdentifier, team: myTeam)
        let rogueClient = CodeSignature.Identity(identifier: AgentWire.cliIdentifier, team: attackerTeam)

        let result = IPCPeerValidator.validate(
            peer: rogueClient, local: hostIdentity, role: .client, isDevelopmentBuild: false)
        #expect(result == .invalid(.teamMismatch(expected: myTeam, actual: attackerTeam)))
    }

    // MARK: - 3. Different-Team Server

    @Test func differentTeamServerRejected() {
        let cliIdentity = CodeSignature.Identity(identifier: AgentWire.cliIdentifier, team: myTeam)
        let rogueServer = CodeSignature.Identity(identifier: AgentWire.appIdentifier, team: attackerTeam)

        let result = IPCPeerValidator.validate(
            peer: rogueServer, local: cliIdentity, role: .server, isDevelopmentBuild: false)
        #expect(result == .invalid(.teamMismatch(expected: myTeam, actual: attackerTeam)))
    }

    // MARK: - 4. Missing Signing Identity

    @Test func missingSigningIdentitiesFailClosedInProduction() {
        let hostIdentity = CodeSignature.Identity(identifier: AgentWire.appIdentifier, team: myTeam)
        let cliIdentity = CodeSignature.Identity(identifier: AgentWire.cliIdentifier, team: myTeam)

        // Missing peer identity
        let missingPeer = IPCPeerValidator.validate(
            peer: nil, local: hostIdentity, role: .client, isDevelopmentBuild: false)
        #expect(missingPeer == .invalid(.peerIdentityMissing))

        // Missing local identity
        let missingLocal = IPCPeerValidator.validate(
            peer: cliIdentity, local: nil, role: .client, isDevelopmentBuild: false)
        #expect(missingLocal == .invalid(.localIdentityMissing))

        // Peer has no team
        let untrustedPeer = CodeSignature.Identity(identifier: AgentWire.cliIdentifier, team: nil)
        let peerMissingTeam = IPCPeerValidator.validate(
            peer: untrustedPeer, local: hostIdentity, role: .client, isDevelopmentBuild: false)
        #expect(peerMissingTeam == .invalid(.teamMissing(party: "peer")))

        // Local has no team
        let localMissingTeamId = CodeSignature.Identity(identifier: AgentWire.appIdentifier, team: nil)
        let localMissingTeam = IPCPeerValidator.validate(
            peer: cliIdentity, local: localMissingTeamId, role: .client, isDevelopmentBuild: false)
        #expect(localMissingTeam == .invalid(.localIdentityMissing))
    }

    // MARK: - 5. Unsigned / Ad-hoc Development Build

    @Test func unsignedAdHocDevelopmentBuildRequiresExplicitBypass() {
        // Without explicit bypass in development, unsigned peer is rejected
        let rejectedDev = IPCPeerValidator.validate(
            peer: nil, local: nil, role: .server,
            isDevelopmentBuild: true, developmentAllowUnsigned: false)
        #expect(rejectedDev == .invalid(.peerIdentityMissing))

        // With explicit bypass in development, unsigned peer is allowed
        let allowedDev = IPCPeerValidator.validate(
            peer: nil, local: nil, role: .server,
            isDevelopmentBuild: true, developmentAllowUnsigned: true)
        #expect(allowedDev == .valid)

        // In development, if identities are present but teams mismatch, still reject
        let devLocal = CodeSignature.Identity(identifier: AgentWire.cliIdentifier, team: myTeam)
        let devRogue = CodeSignature.Identity(identifier: AgentWire.appIdentifier, team: attackerTeam)
        let devTeamMismatch = IPCPeerValidator.validate(
            peer: devRogue, local: devLocal, role: .server,
            isDevelopmentBuild: true, developmentAllowUnsigned: false)
        #expect(devTeamMismatch == .invalid(.teamMismatch(expected: myTeam, actual: attackerTeam)))
    }

    // MARK: - 6. Bundle-Identifier Mismatch

    @Test func bundleIdentifierMismatchRejected() {
        let hostIdentity = CodeSignature.Identity(identifier: AgentWire.appIdentifier, team: myTeam)
        let fakeClient = CodeSignature.Identity(identifier: "com.random.unrelated.app", team: myTeam)

        let result = IPCPeerValidator.validate(
            peer: fakeClient, local: hostIdentity, role: .client, isDevelopmentBuild: false)
        #expect(result == .invalid(.identifierMismatch(expected: AgentWire.cliIdentifier, actual: "com.random.unrelated.app")))
    }

    // MARK: - 7. Production Build Rejecting Development Bypass Attempts

    @Test func productionBuildRejectsDevelopmentBypassAttempts() {
        // When isDevelopmentBuild is false, developmentAllowUnsigned MUST fail closed
        let result = IPCPeerValidator.validate(
            peer: nil, local: nil, role: .server,
            isDevelopmentBuild: false, developmentAllowUnsigned: true)
        #expect(result == .invalid(.developmentBypassRejectedInProduction))
    }
}
