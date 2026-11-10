import Darwin
import Foundation

/// Connection state of the Droppy IPC client transport.
public enum AetherClientConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(AetherPeerIdentity)
}

/// Client-side Unix Domain Socket transport for the AETHER Droppy droplet.
///
/// Manages:
/// - Secure token loading and POSIX DAC validation.
/// - Unix domain socket connection to the AETHER host.
/// - Kernel audit token validation of the host server.
/// - Bounded handshake negotiation.
/// - Non-blocking frame decoding for inbound OTP payloads.
/// - Outbound acknowledgment serialization and transmission.
/// - Automatic reconnection with backoff.
public actor AetherIPCClientTransport {
    public let socketPath: String
    public let tokenPath: String
    public let clientIdentifier: String
    public let serverValidator: any AetherPeerAuthenticating

    private var socketFD: Int32 = -1
    private var isStopped: Bool = false
    private(set) public var state: AetherClientConnectionState = .disconnected

    private var readTask: Task<Void, Never>?
    private var autoReconnectTask: Task<Void, Never>?
    private let decoder = AetherFrameDecoder()

    private let payloadContinuation: AsyncStream<AetherOTPPayload>.Continuation
    public nonisolated let payloads: AsyncStream<AetherOTPPayload>

    public init(
        socketPath: String? = nil,
        tokenPath: String? = nil,
        clientIdentifier: String = "iordv.Droppy",
        serverValidator: (any AetherPeerAuthenticating)? = nil
    ) {
        if let socketPath {
            self.socketPath = socketPath
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.socketPath = appSupport.appendingPathComponent("Aether/droplet.sock").path
        }

        if let tokenPath {
            self.tokenPath = tokenPath
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.tokenPath = appSupport.appendingPathComponent("Aether/session.token").path
        }

        self.clientIdentifier = clientIdentifier
        self.serverValidator = serverValidator ?? AetherHostPeerValidator()

        var continuation: AsyncStream<AetherOTPPayload>.Continuation!
        self.payloads = AsyncStream { continuation = $0 }
        self.payloadContinuation = continuation
    }

    /// Whether the client transport is currently connected to an authenticated host.
    public var isConnected: Bool {
        if case .connected = state {
            return true
        }
        return false
    }

    /// Reads and validates the ephemeral session token file using POSIX DAC checks.
    public static func readSessionToken(from path: String) throws -> String {
        let parentDir = (path as NSString).deletingLastPathComponent
        var dirStat = stat()
        guard lstat(parentDir, &dirStat) == 0 else {
            throw AetherTransportError.tokenFileNotFound(path)
        }
        guard (dirStat.st_mode & S_IFMT) == S_IFDIR else {
            if (dirStat.st_mode & S_IFMT) == S_IFLNK {
                throw AetherTransportError.parentDirectoryIsSymlink
            }
            throw AetherTransportError.parentDirectoryInsecure("Parent is not a directory")
        }
        guard dirStat.st_uid == getuid() else {
            throw AetherTransportError.parentDirectoryNotOwnedByUser
        }

        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            throw AetherTransportError.tokenFileNotFound(path)
        }
        defer { close(fd) }

        var fileStat = stat()
        guard fstat(fd, &fileStat) == 0 else {
            throw AetherTransportError.tokenFileInsecure("Cannot fstat token file")
        }
        guard (fileStat.st_mode & S_IFMT) == S_IFREG else {
            throw AetherTransportError.tokenFileInsecure("Token path is not a regular file")
        }
        guard fileStat.st_uid == getuid() else {
            throw AetherTransportError.tokenFileInsecure("Token file not owned by current user")
        }
        // Group and other must have zero permissions (0600 mode)
        guard (fileStat.st_mode & 0o077) == 0 else {
            throw AetherTransportError.tokenFileInsecure("Token file permissions are looser than 0600 (mode: \(String(fileStat.st_mode, radix: 8)))")
        }

        var buffer = [UInt8](repeating: 0, count: 256)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else {
            throw AetherTransportError.tokenFileInsecure("Token file is empty")
        }
        guard let token = String(bytes: buffer[0..<bytesRead], encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty
        else {
            throw AetherTransportError.tokenFileInsecure("Token file contains invalid string")
        }
        return token
    }

    /// Establishes connection to the host server, validates peer signature, and negotiates handshake.
    public func connect() async throws {
        guard !isStopped else {
            throw AetherTransportError.clientStopped
        }
        if isConnected {
            return
        }

        state = .connecting

        // 1. Read ephemeral session token
        let token = try Self.readSessionToken(from: tokenPath)

        // 2. Validate socket path length
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count <= AetherSocketEndpoint.maxPathLength else {
            state = .disconnected
            throw AetherTransportError.socketPathTooLong(pathBytes.count)
        }

        // 3. Create AF_UNIX SOCK_STREAM socket
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            state = .disconnected
            throw AetherTransportError.socketConnectFailed(errno)
        }

        // Disable SIGPIPE
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        // 4. Connect to socket address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
            raw[pathBytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            let err = errno
            Darwin.close(fd)
            state = .disconnected
            throw AetherTransportError.socketConnectFailed(err)
        }

        // 5. Authenticate server peer
        let peerIdentity: AetherPeerIdentity
        do {
            peerIdentity = try serverValidator.authenticatePeer(fileDescriptor: fd)
        } catch {
            Darwin.close(fd)
            state = .disconnected
            throw error
        }

        // 6. Set socket non-blocking for event loop
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        self.socketFD = fd

        // 7. Send handshake frame
        let handshake = AetherHandshakeFrame(
            protocolVersion: AetherHandshakeFrame.currentProtocolVersion,
            sessionToken: token,
            clientIdentifier: clientIdentifier
        )
        let handshakeData = try AetherFrameCodec.encode(handshake)
        do {
            try await writeRaw(handshakeData)
        } catch {
            Darwin.close(fd)
            self.socketFD = -1
            state = .disconnected
            throw error
        }

        state = .connected(peerIdentity)
        startReading()
    }

    /// Transmits an acknowledgment frame back to the host.
    public func sendAcknowledgment(_ ack: AetherOTPAcknowledgment) async throws {
        guard isConnected else {
            throw AetherTransportError.clientDisconnected
        }
        let frameData = try AetherFrameCodec.encode(ack)
        try await writeRaw(frameData)
    }

    /// Starts an automatic reconnection loop with specified retry interval.
    public func startAutoReconnect(retryInterval: TimeInterval = 1.0) {
        guard autoReconnectTask == nil else { return }

        autoReconnectTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let (connected, stopped) = await self.status
                if stopped { break }
                if !connected {
                    try? await self.connect()
                }
                try? await Task.sleep(for: .seconds(retryInterval))
            }
        }
    }

    private var status: (connected: Bool, stopped: Bool) {
        (isConnected, isStopped)
    }

    /// Disconnects the socket without terminating the client permanently.
    public func disconnect() {
        guard socketFD >= 0 else {
            state = .disconnected
            return
        }

        readTask?.cancel()
        readTask = nil

        let fd = socketFD
        socketFD = -1
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)

        decoder.reset()
        state = .disconnected
    }

    /// Permanently stops the client transport and closes streams.
    public func stop() {
        isStopped = true
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
        disconnect()
        payloadContinuation.finish()
    }

    // MARK: - Internal I/O

    private func writeRaw(_ data: Data) async throws {
        guard socketFD >= 0 else {
            throw AetherTransportError.clientDisconnected
        }

        var offset = 0
        let total = data.count
        while offset < total {
            let n = data.withUnsafeBytes { raw in
                Darwin.write(socketFD, raw.baseAddress! + offset, total - offset)
            }
            if n > 0 {
                offset += n
                continue
            }
            let err = errno
            guard n < 0 && (err == EINTR || err == EAGAIN || err == EWOULDBLOCK) else {
                throw AetherTransportError.writeFailed(err)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func startReading() {
        guard readTask == nil else { return }

        readTask = Task { [weak self] in
            guard let self else { return }
            await self.runReadLoop()
        }
    }

    private func runReadLoop() async {
        var buffer = [UInt8](repeating: 0, count: 1024)

        while !Task.isCancelled && socketFD >= 0 {
            let bytesRead = Darwin.read(socketFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let chunk = Data(buffer[0..<bytesRead])
                do {
                    let frames = try decoder.appendAndDecode(chunk)
                    for frameData in frames {
                        let jsonDecoder = JSONDecoder()
                        jsonDecoder.dateDecodingStrategy = .iso8601
                        if let payload = try? jsonDecoder.decode(AetherOTPPayload.self, from: frameData) {
                            if (try? payload.validate()) != nil {
                                payloadContinuation.yield(payload)
                            }
                        }
                    }
                } catch {
                    // Protocol error or buffer exhaustion, sever connection
                    break
                }
            } else if bytesRead == 0 {
                // Host disconnected (clean EOF)
                break
            } else {
                let err = errno
                if err == EINTR || err == EAGAIN || err == EWOULDBLOCK {
                    try? await Task.sleep(for: .milliseconds(20))
                    continue
                }
                // Read error
                break
            }
        }

        disconnect()
    }
}
