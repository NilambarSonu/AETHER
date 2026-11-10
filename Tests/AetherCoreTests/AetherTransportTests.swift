import AetherCore
import Darwin
import Foundation
import Testing

@Suite(.serialized) struct AetherTransportTests {

    // Helper to create an isolated temporary directory for test sockets and tokens
    private func makeTestDirectory() throws -> String {
        let unique = UUID().uuidString.prefix(8)
        let dir = "/tmp/ae-\(unique)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }

    // Helper mock peer authenticator for deterministic tests
    struct MockPeerValidator: AetherPeerAuthenticating {
        var identity: AetherPeerIdentity?
        var shouldThrow: Error?

        func authenticatePeer(fileDescriptor: Int32) throws -> AetherPeerIdentity {
            if let shouldThrow {
                throw shouldThrow
            }
            return identity ?? AetherPeerIdentity(identifier: "iordv.Droppy", team: "NARHG44L48", pid: getpid())
        }
    }

    // Helper client socket connect
    private func connectClient(to socketPath: String) -> Int32? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            return nil
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let res = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard res == 0 else {
            Darwin.close(fd)
            return nil
        }
        return fd
    }

    // MARK: - 1. Socket Lifecycle Tests

    @Test func serverStartAndStopCleansFilesystem() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )

        try await server.start()
        #expect(await server.isRunning == true)
        #expect(FileManager.default.fileExists(atPath: socketPath) == true)
        #expect(FileManager.default.fileExists(atPath: tokenPath) == true)
        #expect(FileManager.default.fileExists(atPath: socketPath + ".lock") == true)

        await server.stop()
        #expect(await server.isRunning == false)
        #expect(FileManager.default.fileExists(atPath: socketPath) == false)
        #expect(FileManager.default.fileExists(atPath: tokenPath) == false)
        #expect(FileManager.default.fileExists(atPath: socketPath + ".lock") == false)
    }

    @Test func tokenManagerInodeVerificationPreventsSwappedUnlink() throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let tokenPath = (testDir as NSString).appendingPathComponent("session.token")
        let tokenManager = AetherSessionTokenManager(tokenPath: tokenPath)

        _ = try tokenManager.generateAndPersistToken()
        #expect(FileManager.default.fileExists(atPath: tokenPath) == true)
        let originalInode = tokenManager.boundInode
        #expect(originalInode != nil)

        // Replace the file at tokenPath with a different file (different inode)
        // Simulate an adversary swapping the token file
        unlink(tokenPath)
        let swappedFD = open(tokenPath, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        Darwin.write(swappedFD, "SWAPPED", 7)
        Darwin.close(swappedFD)

        var swappedStat = stat()
        #expect(lstat(tokenPath, &swappedStat) == 0)
        #expect(swappedStat.st_ino != originalInode)

        // Cleanup should notice the swapped inode and refuse to unlink it
        tokenManager.cleanup()
        #expect(FileManager.default.fileExists(atPath: tokenPath) == true)

        // Clean up swapped file manually
        unlink(tokenPath)
    }

    @Test func duplicateServerStartOnSamePathFailsWithLockError() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        let server1 = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )
        try await server1.start()

        let server2 = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )

        do {
            try await server2.start()
            #expect(Bool(false), "Second server start should have failed with lock error")
        } catch let error as AetherTransportError {
            #expect(error == .anotherHostInstanceRunning)
        }

        await server1.stop()
    }

    @Test func staleSocketIsUnlinkedWhenLockIsAcquired() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("stale.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("stale.token")

        // Create a dead/stale socket using bind
        let staleFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        _ = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(staleFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        Darwin.close(staleFD)  // Socket is closed but file remains on disk

        #expect(FileManager.default.fileExists(atPath: socketPath) == true)

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )
        try await server.start()
        #expect(await server.isRunning == true)
        await server.stop()
    }

    @Test func nonSocketFileAtSocketPathIsRejected() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("not_a_socket.txt")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        // Create a regular file at the socket path
        FileManager.default.createFile(atPath: socketPath, contents: Data("adversary".utf8))

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )

        do {
            try await server.start()
            #expect(Bool(false), "Server should not overwrite a regular file")
        } catch let error as AetherTransportError {
            if case .parentDirectoryInsecure = error {
                #expect(true)
            } else {
                #expect(Bool(false), "Expected parentDirectoryInsecure error")
            }
        }
    }

    @Test func symlinkedParentDirectoryIsRejected() throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let realDir = (testDir as NSString).appendingPathComponent("real_dir")
        let symlinkDir = (testDir as NSString).appendingPathComponent("symlink_dir")
        try FileManager.default.createDirectory(atPath: realDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(atPath: symlinkDir, withDestinationPath: realDir)

        #expect(throws: AetherTransportError.parentDirectoryIsSymlink) {
            try AetherSocketEndpoint.validateAndCreateParentDirectory(symlinkDir)
        }
    }

    // MARK: - 2. Handshake & Ephemeral Token Tests

    @Test func constantTimeComparisonWorksCorrectly() {
        let token1 = "abcdef1234567890abcdef1234567890"
        let token2 = "abcdef1234567890abcdef1234567890"
        let token3 = "abcdef1234567890abcdef1234567891"
        let shortToken = "abcdef"

        #expect(AetherSecurityUtils.constantTimeCompare(token1, token2) == true)
        #expect(AetherSecurityUtils.constantTimeCompare(token1, token3) == false)
        #expect(AetherSecurityUtils.constantTimeCompare(token1, shortToken) == false)
    }

    @Test func validHandshakeCompletesSessionAdoption() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )
        try await server.start()

        // Read token generated by server
        let tokenStr = try String(contentsOfFile: tokenPath, encoding: .utf8)
        let clientFD = try #require(connectClient(to: socketPath))
        defer { Darwin.close(clientFD) }

        // Send valid handshake frame
        let handshake = AetherHandshakeFrame(sessionToken: tokenStr, clientIdentifier: "iordv.Droppy")
        let frame = try AetherFrameCodec.encode(handshake)
        _ = frame.withUnsafeBytes { raw in
            Darwin.write(clientFD, raw.baseAddress!, raw.count)
        }

        // Wait briefly for server to adopt session
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await server.isClientConnected == true)

        await server.stop()
    }

    @Test func invalidSessionTokenSeverConnection() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )
        try await server.start()

        let clientFD = try #require(connectClient(to: socketPath))
        defer { Darwin.close(clientFD) }

        // Send invalid handshake frame
        let handshake = AetherHandshakeFrame(sessionToken: "WRONG_TOKEN", clientIdentifier: "iordv.Droppy")
        let frame = try AetherFrameCodec.encode(handshake)
        _ = frame.withUnsafeBytes { raw in
            Darwin.write(clientFD, raw.baseAddress!, raw.count)
        }

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await server.isClientConnected == false)

        await server.stop()
    }

    @Test func delayedHandshakeTimesOut() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator(),
            handshakeTimeout: 0.1  // Short timeout for test
        )
        try await server.start()

        let clientFD = try #require(connectClient(to: socketPath))
        defer { Darwin.close(clientFD) }

        // Wait past handshake timeout without sending anything
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(await server.isClientConnected == false)

        await server.stop()
    }

    // MARK: - 3. Peer Authentication Tests

    @Test func peerAuthenticationFailureDropsConnection() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        let failingValidator = MockPeerValidator(
            shouldThrow: AetherTransportError.peerIdentityMismatch(expected: "iordv.Droppy", actual: "evil.app")
        )

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: failingValidator
        )
        try await server.start()

        let clientFD = try #require(connectClient(to: socketPath))
        defer { Darwin.close(clientFD) }

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await server.isClientConnected == false)

        await server.stop()
    }

    @Test func realDroppyPeerValidatorRejectsUnauthorizedProcess() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        // Fail-closed production validator enforcing Droppy bundle ID and Team ID
        let realValidator = AetherDroppyPeerValidator(developmentAllowUnsigned: false)

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: realValidator
        )
        try await server.start()

        // Connect client (the test process, which is not signed as iordv.Droppy)
        let clientFD = try #require(connectClient(to: socketPath))
        defer { Darwin.close(clientFD) }

        // Give server time to validate peer token and drop unauthorized socket
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await server.isClientConnected == false)

        await server.stop()
    }

    // MARK: - 4. Protocol Broadcast & Replay Protection Tests

    @Test func broadcastDeliversPayloadToActiveClient() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )
        try await server.start()

        let tokenStr = try String(contentsOfFile: tokenPath, encoding: .utf8)
        let clientFD = try #require(connectClient(to: socketPath))
        defer { Darwin.close(clientFD) }

        let handshake = AetherHandshakeFrame(sessionToken: tokenStr, clientIdentifier: "iordv.Droppy")
        let frame = try AetherFrameCodec.encode(handshake)
        _ = frame.withUnsafeBytes { Darwin.write(clientFD, $0.baseAddress!, $0.count) }

        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await server.isClientConnected == true)

        let payload = try AetherOTPPayload(
            source: .messages,
            serviceLabel: "GitHub",
            otpCode: "482913"
        )

        let result = try await server.broadcast(payload: payload)
        #expect(result == .delivered)

        // Read payload on client end
        var clientBuf = [UInt8](repeating: 0, count: 1024)
        let n = Darwin.read(clientFD, &clientBuf, clientBuf.count)
        #expect(n > 4)

        let receivedData = Data(clientBuf[0..<n])
        let decodedPayload: AetherOTPPayload = try AetherFrameCodec.decodeSingleFrame(receivedData)
        #expect(decodedPayload.otpCode == "482913")
        #expect(decodedPayload.serviceLabel == "GitHub")

        await server.stop()
    }

    @Test func broadcastRejectsDuplicateAndExpiredEvents() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )
        try await server.start()

        let tokenStr = try String(contentsOfFile: tokenPath, encoding: .utf8)
        let clientFD = try #require(connectClient(to: socketPath))
        defer { Darwin.close(clientFD) }

        let handshake = AetherHandshakeFrame(sessionToken: tokenStr, clientIdentifier: "iordv.Droppy")
        let frame = try AetherFrameCodec.encode(handshake)
        _ = frame.withUnsafeBytes { Darwin.write(clientFD, $0.baseAddress!, $0.count) }
        try await Task.sleep(nanoseconds: 100_000_000)

        let payload = try AetherOTPPayload(
            source: .appleMail,
            serviceLabel: "Google",
            otpCode: "998877"
        )

        let res1 = try await server.broadcast(payload: payload)
        #expect(res1 == .delivered)

        // Second broadcast with same eventID must be caught by replay cache
        let res2 = try await server.broadcast(payload: payload)
        #expect(res2 == .duplicate)

        await server.stop()
    }

    @Test func replayCacheBoundedCapacityAndEviction() {
        let cache = AetherReplayCache()
        let now = Date()

        // 1. Add 256 unique entries
        var ids: [UUID] = []
        for _ in 0..<256 {
            let id = UUID()
            ids.append(id)
            let isReplay = cache.isReplayOrRecord(eventID: id, expiresAt: now.addingTimeInterval(300), now: now)
            #expect(isReplay == false)
        }
        #expect(cache.count == 256)

        // 2. All 256 should now be considered replays
        for id in ids {
            #expect(cache.isReplayOrRecord(eventID: id, expiresAt: now.addingTimeInterval(300), now: now) == true)
        }

        // 3. Adding 257th entry should evict oldest (ids[0])
        let newID = UUID()
        let isReplay257 = cache.isReplayOrRecord(eventID: newID, expiresAt: now.addingTimeInterval(300), now: now)
        #expect(isReplay257 == false)
        #expect(cache.count == 256)

        // 4. ids[0] was evicted, so it should be accepted as fresh again
        #expect(cache.isReplayOrRecord(eventID: ids[0], expiresAt: now.addingTimeInterval(300), now: now) == false)
    }

    // MARK: - 5. Concurrency & Reconnection Tests

    @Test func secondClientConnectionCleanlyReplacesFirst() async throws {
        let testDir = try makeTestDirectory()
        defer { try? FileManager.default.removeItem(atPath: testDir) }

        let socketPath = (testDir as NSString).appendingPathComponent("test.sock")
        let tokenPath = (testDir as NSString).appendingPathComponent("test.token")

        let server = AetherIPCTransportServer(
            socketPath: socketPath,
            tokenPath: tokenPath,
            peerValidator: MockPeerValidator()
        )
        try await server.start()

        let tokenStr = try String(contentsOfFile: tokenPath, encoding: .utf8)

        // Client 1 connects
        let client1FD = try #require(connectClient(to: socketPath))
        defer { Darwin.close(client1FD) }
        let h1 = try AetherFrameCodec.encode(AetherHandshakeFrame(sessionToken: tokenStr, clientIdentifier: "Droppy1"))
        _ = h1.withUnsafeBytes { Darwin.write(client1FD, $0.baseAddress!, $0.count) }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(await server.isClientConnected == true)

        // Client 2 connects (e.g. Droppy restart)
        let client2FD = try #require(connectClient(to: socketPath))
        defer { Darwin.close(client2FD) }
        let h2 = try AetherFrameCodec.encode(AetherHandshakeFrame(sessionToken: tokenStr, clientIdentifier: "Droppy2"))
        _ = h2.withUnsafeBytes { Darwin.write(client2FD, $0.baseAddress!, $0.count) }
        try await Task.sleep(nanoseconds: 100_000_000)

        // Server still has active client connected
        #expect(await server.isClientConnected == true)

        // Broadcasting delivers to Client 2
        let payload = try AetherOTPPayload(source: .gmail, serviceLabel: "Bank", otpCode: "123456")
        let res = try await server.broadcast(payload: payload)
        #expect(res == .delivered)

        var buf = [UInt8](repeating: 0, count: 1024)
        let n = Darwin.read(client2FD, &buf, buf.count)
        #expect(n > 0)

        await server.stop()
    }
}
