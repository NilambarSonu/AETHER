import Foundation

/// Stateful incremental frame decoder for parsing incoming byte streams from sockets.
///
/// Features:
/// - Reassembles fragmented socket read chunks.
/// - Handles concatenated multiple frames.
/// - Validates header length BEFORE allocating or slicing body memory.
/// - Hard 4,096 byte maximum frame limit.
/// - Hard 16,384 byte maximum buffer guard against unbounded buffer expansion DoS.
/// - Replay/reset safety.
public final class AetherFrameDecoder: @unchecked Sendable {
    public static let maxPayloadSize: Int = 4_096
    public static let headerSize: Int = 4
    public static let maxInternalBufferSize: Int = 16_384

    private let lock = NSLock()
    private var buffer = Data()

    public init() {}

    /// Appends incoming raw bytes from a socket chunk to the internal buffer.
    public func append(_ data: Data) throws {
        try lock.withLock {
            guard buffer.count + data.count <= Self.maxInternalBufferSize else {
                throw AetherProtocolError.decoderBufferExceeded(buffer.count + data.count)
            }
            buffer.append(data)
        }
    }

    /// Resets the decoder buffer (e.g., after recovering from an error or on reconnect).
    public func reset() {
        lock.withLock {
            buffer.removeAll(keepingCapacity: false)
        }
    }

    /// Current number of buffered bytes.
    public var bufferedBytes: Int {
        lock.withLock { buffer.count }
    }

    /// Extracts the next complete payload data frame if available.
    ///
    /// Returns:
    /// - `Data` if a complete frame was decoded.
    /// - `nil` if more bytes are needed.
    /// Throws:
    /// - `AetherProtocolError.zeroLengthFrame`
    /// - `AetherProtocolError.oversizedFrame`
    public func nextFrame() throws -> Data? {
        try lock.withLock {
            guard buffer.count >= Self.headerSize else {
                return nil
            }

            // Read 4-byte header in network byte order (big-endian)
            let length: UInt32 = buffer.withUnsafeBytes { raw in
                raw.loadUnaligned(as: UInt32.self).bigEndian
            }
            let payloadLength = Int(length)

            // Validate length immediately before slicing buffer
            guard payloadLength > 0 else {
                buffer.removeFirst(Self.headerSize)
                throw AetherProtocolError.zeroLengthFrame
            }
            guard payloadLength <= Self.maxPayloadSize else {
                buffer.removeFirst(Self.headerSize)
                throw AetherProtocolError.oversizedFrame(payloadLength)
            }

            let totalFrameSize = Self.headerSize + payloadLength
            guard buffer.count >= totalFrameSize else {
                return nil  // Incomplete frame; wait for next chunk
            }

            // Extract frame payload
            let payloadData = buffer.subdata(in: Self.headerSize..<totalFrameSize)
            buffer.removeSubrange(0..<totalFrameSize)
            return payloadData
        }
    }

    /// Appends incoming raw bytes and drains all currently complete frames.
    public func appendAndDecode(_ data: Data) throws -> [Data] {
        try append(data)
        var frames: [Data] = []
        while let frame = try nextFrame() {
            frames.append(frame)
        }
        return frames
    }

    /// Incremental decoder for `AetherOTPPayload`.
    public func nextOTPPayload(at referenceDate: Date = Date()) throws -> AetherOTPPayload? {
        guard let data = try nextFrame() else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let payload = try decoder.decode(AetherOTPPayload.self, from: data)
            try payload.validate(at: referenceDate)
            return payload
        } catch let error as AetherProtocolError {
            throw error
        } catch {
            throw AetherProtocolError.malformedJSON(error.localizedDescription)
        }
    }

    /// Incremental decoder for `AetherOTPAcknowledgment`.
    public func nextAcknowledgment() throws -> AetherOTPAcknowledgment? {
        guard let data = try nextFrame() else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let ack = try decoder.decode(AetherOTPAcknowledgment.self, from: data)
            try ack.validate()
            return ack
        } catch let error as AetherProtocolError {
            throw error
        } catch {
            throw AetherProtocolError.malformedJSON(error.localizedDescription)
        }
    }
}
