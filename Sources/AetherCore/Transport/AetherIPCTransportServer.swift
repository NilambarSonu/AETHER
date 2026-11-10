import Darwin
import Foundation

/// Broadcast outcome for an individual OTP event.
public enum AetherBroadcastResult: Equatable, Sendable {
    case delivered
    case noClientConnected
    case expired
    case duplicate
}

/// Host-side Unix Domain Socket transport server.
///
/// Manages the socket lifecycle, exclusive filesystem locks, kernel audit token validation,
/// ephemeral session handshakes, bounded replay protection, and serialized frame delivery.
public actor AetherIPCTransportServer {
    public nonisolated let endpoint: AetherSocketEndpoint
    public nonisolated let tokenManager: AetherSessionTokenManager
    public nonisolated let replayCache: AetherReplayCache
    public let peerValidator: any AetherPeerAuthenticating
    public let handshakeTimeout: TimeInterval

    private(set) public var isRunning: Bool = false
    private var activeSession: AetherIPCClientSession?
    private var acceptTask: Task<Void, Never>?

    private let ackContinuation: AsyncStream<AetherOTPAcknowledgment>.Continuation
    public nonisolated let acknowledgments: AsyncStream<AetherOTPAcknowledgment>

    public init(
        socketPath: String? = nil,
        tokenPath: String? = nil,
        peerValidator: (any AetherPeerAuthenticating)? = nil,
        handshakeTimeout: TimeInterval = 2.0
    ) {
        self.endpoint = AetherSocketEndpoint(socketPath: socketPath)
        self.tokenManager = AetherSessionTokenManager(tokenPath: tokenPath)
        self.replayCache = AetherReplayCache()
        self.peerValidator = peerValidator ?? AetherDroppyPeerValidator()
        self.handshakeTimeout = handshakeTimeout

        var continuation: AsyncStream<AetherOTPAcknowledgment>.Continuation!
        self.acknowledgments = AsyncStream { continuation = $0 }
        self.ackContinuation = continuation
    }

    /// Starts the transport server: acquires exclusive lock, binds socket, writes session token, and starts accept loop.
    public func start() throws {
        guard !isRunning else { return }

        // 1. Bind and listen on socket
        let listeningFD = try endpoint.bindAndListen()

        // 2. Generate and persist ephemeral session token
        let token = try tokenManager.generateAndPersistToken()

        self.isRunning = true

        // 3. Launch accept loop task
        acceptTask = Task { [weak self, listeningFD, token] in
            guard let self else { return }
            await self.runAcceptLoop(listeningFD: listeningFD, expectedToken: token)
        }
    }

    /// Broadcasts an ephemeral OTP payload to the connected Droppy client.
    public func broadcast(payload: AetherOTPPayload) async throws -> AetherBroadcastResult {
        guard isRunning else {
            throw AetherTransportError.serverStopped
        }

        // 1. Validate expiration at actual broadcast boundary
        guard payload.expiresAt > Date() else {
            return .expired
        }

        // 2. Evaluate replay protection
        guard !replayCache.isReplayOrRecord(eventID: payload.eventID, expiresAt: payload.expiresAt) else {
            return .duplicate
        }

        // 3. Deliver to active client session if connected
        guard let session = activeSession else {
            return .noClientConnected
        }

        let frameData = try AetherFrameCodec.encode(payload)
        do {
            try await session.writeFrame(frameData)
            return .delivered
        } catch {
            // Disconnected or write error, drop session
            await session.close()
            activeSession = nil
            return .noClientConnected
        }
    }

    /// Stops the server, closes client sessions, unlinks sockets and tokens, and cancels background tasks.
    public func stop() async {
        guard isRunning else { return }
        isRunning = false

        acceptTask?.cancel()
        acceptTask = nil

        if let session = activeSession {
            await session.close()
            activeSession = nil
        }

        endpoint.closeAndCleanup()
        tokenManager.cleanup()
        replayCache.reset()
    }

    /// Returns `true` if a verified Droppy client is currently connected.
    public var isClientConnected: Bool {
        activeSession != nil
    }

    // MARK: - Private Accept & Handshake Loop

    private func runAcceptLoop(listeningFD: Int32, expectedToken: String) async {
        while !Task.isCancelled && isRunning {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listeningFD, $0, &clientLen)
                }
            }

            if clientFD < 0 {
                let err = errno
                if err == EINTR || err == EAGAIN || err == EWOULDBLOCK {
                    try? await Task.sleep(for: .milliseconds(20))
                    continue
                }
                break
            }

            // Set client socket non-blocking
            let flags = fcntl(clientFD, F_GETFL, 0)
            _ = fcntl(clientFD, F_SETFL, flags | O_NONBLOCK)

            // Handle incoming client connection
            await handleIncomingClient(clientFD: clientFD, expectedToken: expectedToken)
        }
    }

    private func handleIncomingClient(clientFD: Int32, expectedToken: String) async {
        // 1. Authenticate peer process via Darwin audit token
        let peerIdentity: AetherPeerIdentity
        do {
            peerIdentity = try peerValidator.authenticatePeer(fileDescriptor: clientFD)
        } catch {
            Darwin.close(clientFD)
            return
        }

        // 2. Perform handshake validation within strict deadline
        do {
            try await verifyHandshake(clientFD: clientFD, expectedToken: expectedToken)
        } catch {
            Darwin.close(clientFD)
            return
        }

        // 3. Adopt verified client session (cleanly severing any previous connection)
        if let previous = activeSession {
            await previous.close()
        }

        let newSession = AetherIPCClientSession(socketFD: clientFD, peerIdentity: peerIdentity)
        self.activeSession = newSession
        await newSession.startReading()

        // Forward acknowledgments to server stream
        Task { [weak self, newSession] in
            for await ack in newSession.acknowledgments {
                guard let self else { break }
                await self.forwardAck(ack)
            }
        }
    }

    private func verifyHandshake(clientFD: Int32, expectedToken: String) async throws {
        let deadline = ContinuousClock().now + .seconds(handshakeTimeout)
        let decoder = AetherFrameDecoder()
        var buffer = [UInt8](repeating: 0, count: 512)

        while ContinuousClock().now < deadline {
            let bytesRead = Darwin.read(clientFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let frames = try decoder.appendAndDecode(Data(buffer[0..<bytesRead]))
                if let firstFrame = frames.first {
                    let jsonDecoder = JSONDecoder()
                    guard let handshake = try? jsonDecoder.decode(AetherHandshakeFrame.self, from: firstFrame) else {
                        throw AetherTransportError.handshakeMalformed("Cannot decode AetherHandshakeFrame")
                    }

                    guard handshake.protocolVersion == AetherHandshakeFrame.currentProtocolVersion else {
                        throw AetherTransportError.handshakeProtocolVersionMismatch(handshake.protocolVersion)
                    }

                    guard AetherSecurityUtils.constantTimeCompare(handshake.sessionToken, expectedToken) else {
                        throw AetherTransportError.handshakeTokenMismatch
                    }

                    return
                }
            } else if bytesRead == 0 {
                throw AetherTransportError.clientDisconnected
            } else {
                let err = errno
                if err == EINTR || err == EAGAIN || err == EWOULDBLOCK {
                    try await Task.sleep(for: .milliseconds(10))
                    continue
                }
                throw AetherTransportError.clientDisconnected
            }
        }

        throw AetherTransportError.handshakeTimedOut
    }

    private func forwardAck(_ ack: AetherOTPAcknowledgment) {
        ackContinuation.yield(ack)
    }

    deinit {
        endpoint.closeAndCleanup()
        tokenManager.cleanup()
    }
}
