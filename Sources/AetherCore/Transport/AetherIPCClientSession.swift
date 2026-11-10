import Darwin
import Foundation

/// Actor managing an individual accepted and authenticated Droppy client session.
///
/// Encapsulates the socket file descriptor, serializes outbound frame writes,
/// incrementally parses inbound frames via `AetherFrameDecoder`, and emits
/// verified `AetherOTPAcknowledgment` instances to consumers.
public actor AetherIPCClientSession {
    public let socketFD: Int32
    public let peerIdentity: AetherPeerIdentity
    private let decoder = AetherFrameDecoder()
    private var isClosed = false

    private let ackContinuation: AsyncStream<AetherOTPAcknowledgment>.Continuation
    public nonisolated let acknowledgments: AsyncStream<AetherOTPAcknowledgment>
    private var readTask: Task<Void, Never>?

    public init(socketFD: Int32, peerIdentity: AetherPeerIdentity) {
        self.socketFD = socketFD
        self.peerIdentity = peerIdentity

        var continuation: AsyncStream<AetherOTPAcknowledgment>.Continuation!
        self.acknowledgments = AsyncStream { continuation = $0 }
        self.ackContinuation = continuation

        // Disable SIGPIPE on socket
        var on: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Starts the asynchronous read loop to parse incoming frames.
    public func startReading() {
        guard readTask == nil else { return }

        readTask = Task { [weak self] in
            guard let self else { return }
            await self.runReadLoop()
        }
    }

    /// Serialized outbound frame transmission.
    public func writeFrame(_ data: Data) async throws {
        guard !isClosed else {
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

            // Yield cooperatively on non-blocking backpressure without blocking the cooperative thread pool
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Closes the client session and terminates all read/write operations.
    public func close() {
        guard !isClosed else { return }
        isClosed = true

        readTask?.cancel()
        readTask = nil

        Darwin.close(socketFD)
        ackContinuation.finish()
    }

    private func runReadLoop() async {
        var buffer = [UInt8](repeating: 0, count: 1024)

        while !Task.isCancelled && !isClosed {
            let bytesRead = Darwin.read(socketFD, &buffer, buffer.count)
            if bytesRead > 0 {
                let chunk = Data(buffer[0..<bytesRead])
                do {
                    let frames = try decoder.appendAndDecode(chunk)
                    for frameData in frames {
                        let jsonDecoder = JSONDecoder()
                        jsonDecoder.dateDecodingStrategy = .iso8601
                        if let ack = try? jsonDecoder.decode(AetherOTPAcknowledgment.self, from: frameData) {
                            ackContinuation.yield(ack)
                        }
                    }
                } catch {
                    // Protocol error or buffer exhaustion, sever connection
                    break
                }
            } else if bytesRead == 0 {
                // EOF - client disconnected cleanly
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

        close()
    }

    deinit {
        if !isClosed {
            Darwin.close(socketFD)
            ackContinuation.finish()
        }
    }
}
