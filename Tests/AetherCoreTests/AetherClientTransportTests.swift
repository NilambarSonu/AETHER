import AetherCore
import Darwin
import Foundation
import Testing

@Suite(.serialized) struct AetherClientTransportTests {

    private func makeTestDirectory() throws -> String {
        let unique = UUID().uuidString.prefix(8)
        let dir = "/tmp/ae-cli-\(unique)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    struct MockServerValidator: AetherPeerAuthenticating {
        var identity: AetherPeerIdentity?
        var shouldThrow: Error?

        func authenticatePeer(fileDescriptor: Int32) throws -> AetherPeerIdentity {
            if let shouldThrow {
                throw shouldThrow
            }
            return identity ?? AetherPeerIdentity(identifier: "com.uros.codecatch", team: nil, pid: getpid())
        }
    }

    struct MockDroppyValidator: AetherPeerAuthenticating {
        func authenticatePeer(fileDescriptor: Int32) throws -> AetherPeerIdentity {
            AetherPeerIdentity(identifier: "iordv.Droppy", team: "NARHG44L48", pid: getpid())
        }
    }

    private func waitForSessionAdoption(on server: AetherIPCTransportServer, timeout: TimeInterval = 1.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await server.isClientConnected {
                return true
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return await server.isClientConnected
    }

    // MARK: - 1. Token Security Validation

    @Test func tokenFileSecurityEnforces0600AndRejectsLoosePermissions() throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let tokenPath = (testDir as NSString).appendingPathComponent("session.token")

        // 1. Missing token throws tokenFileNotFound
        #expect(throws: AetherTransportError.self) {
            _ = try AetherIPCClientTransport.readSessionToken(from: tokenPath)
        }

        // 2. Token with 0644 permissions (group/other readable) must be rejected
        let looseFD = open(tokenPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #expect(looseFD >= 0)
        let tokenContent = "abcd1234abcd1234abcd1234abcd1234"
        _ = tokenContent.withCString { Darwin.write(looseFD, $0, strlen($0)) }
        Darwin.close(looseFD)

        #expect(throws: AetherTransportError.self) {
            _ = try AetherIPCClientTransport.readSessionToken(from: tokenPath)
        }

        // 3. Token with 0600 permissions succeeds
        chmod(tokenPath, 0o600)
        let readBack = try AetherIPCClientTransport.readSessionToken(from: tokenPath)
        #expect(readBack == tokenContent)
    }

    // MARK: - 2. End-to-End Client <-> Server Handshake & Adoption

    @Test func clientConnectsAndAdoptsSessionWithServer() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("droplet.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("session.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockDroppyValidator()
        )
        try await server.start()

        let client = AetherIPCClientTransport(
            socketPath: socketPath,
            tokenPath: tokenPath,
            clientIdentifier: "iordv.Droppy",
            serverValidator: MockServerValidator()
        )

        #expect(await client.isConnected == false)
        try await client.connect()

        #expect(await client.isConnected == true)
        #expect(await waitForSessionAdoption(on: server) == true)

        await client.stop()
        await server.stop()
    }

    // MARK: - 3. Server Broadcast -> Client Payload Stream

    @Test func serverBroadcastDeliversToClientPayloadStream() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("droplet.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("session.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockDroppyValidator()
        )
        try await server.start()

        let client = AetherIPCClientTransport(
            socketPath: socketPath,
            tokenPath: tokenPath,
            serverValidator: MockServerValidator()
        )
        try await client.connect()
        #expect(await waitForSessionAdoption(on: server) == true)

        let payload = try AetherOTPPayload(
            source: .gmail,
            serviceLabel: "GitHub",
            otpCode: "482731"
        )

        // Broadcast payload from host
        let result = try await server.broadcast(payload: payload)
        #expect(result == .delivered)

        // Consume payload on client
        var iterator = client.payloads.makeAsyncIterator()
        let received = try #require(await iterator.next())

        #expect(received.eventID == payload.eventID)
        #expect(received.serviceLabel == "GitHub")
        #expect(received.otpCode == "482731")

        await client.stop()
        await server.stop()
    }

    // MARK: - 4. Client Acknowledgment -> Server Acknowledgment Stream

    @Test func clientSendsAcknowledgmentReceivedByServer() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("droplet.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("session.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockDroppyValidator()
        )
        try await server.start()

        let client = AetherIPCClientTransport(
            socketPath: socketPath,
            tokenPath: tokenPath,
            serverValidator: MockServerValidator()
        )
        try await client.connect()
        #expect(await waitForSessionAdoption(on: server) == true)

        let eventID = UUID()
        let ack = try AetherOTPAcknowledgment(eventID: eventID, status: .copied)

        try await client.sendAcknowledgment(ack)

        var serverAcks = server.acknowledgments.makeAsyncIterator()
        let receivedAck = try #require(await serverAcks.next())

        #expect(receivedAck.eventID == eventID)
        #expect(receivedAck.status == .copied)

        await client.stop()
        await server.stop()
    }

    // MARK: - 5. Client Auto-Reconnection

    @Test func clientAutoReconnectsAfterServerRestart() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("droplet.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("session.token")

        var server: AetherIPCTransportServer? = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockDroppyValidator()
        )
        try await server?.start()

        let client = AetherIPCClientTransport(
            socketPath: socketPath,
            tokenPath: tokenPath,
            serverValidator: MockServerValidator()
        )
        try await client.connect()
        #expect(await client.isConnected == true)

        // Start auto-reconnect with 0.1s interval for test
        await client.startAutoReconnect(retryInterval: 0.1)

        // Stop host server (simulating restart)
        await server?.stop()
        server = nil

        // Give socket time to close and client to detect disconnect
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(await client.isConnected == false)

        // Start fresh host server instance with new token
        server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockDroppyValidator()
        )
        try await server?.start()

        // Wait for client auto-reconnect task to reconnect
        var reconnected = false
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 100_000_000)
            if await client.isConnected {
                reconnected = true
                break
            }
        }
        #expect(reconnected == true)

        await client.stop()
        await server?.stop()
    }
}
