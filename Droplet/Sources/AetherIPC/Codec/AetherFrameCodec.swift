import Foundation

/// Pure encoder for length-prefixed binary frames carrying AETHER IPC payloads.
///
/// Format:
/// - 4 bytes: UInt32 payload length in network byte order (Big Endian).
/// - N bytes: UTF-8 encoded JSON representation of the payload (1 <= N <= 4096).
public enum AetherFrameCodec {
    public static let maxPayloadSize: Int = 4_096
    public static let headerSize: Int = 4

    /// Encodes an Encodable model into a 4-byte big-endian length-prefixed binary frame.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = try encoder.encode(value)

        guard payload.count > 0 else {
            throw AetherProtocolError.zeroLengthFrame
        }
        guard payload.count <= maxPayloadSize else {
            throw AetherProtocolError.payloadExceedsSizeLimit(payload.count)
        }

        var frame = Data()
        frame.reserveCapacity(headerSize + payload.count)
        var lengthBigEndian = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &lengthBigEndian) { bytes in
            frame.append(contentsOf: bytes)
        }
        frame.append(payload)
        return frame
    }

    /// Convenience decoder for complete, standalone single-frame buffers.
    public static func decodeSingleFrame<T: Decodable>(_ data: Data) throws -> T {
        guard data.count >= headerSize else {
            throw AetherProtocolError.invalidHeaderBytes
        }

        let declaredLength: UInt32 = data.withUnsafeBytes { raw in
            raw.loadUnaligned(as: UInt32.self).bigEndian
        }
        let payloadLength = Int(declaredLength)

        guard payloadLength > 0 else {
            throw AetherProtocolError.zeroLengthFrame
        }
        guard payloadLength <= maxPayloadSize else {
            throw AetherProtocolError.oversizedFrame(payloadLength)
        }
        guard data.count == headerSize + payloadLength else {
            throw AetherProtocolError.invalidHeaderBytes
        }

        let payloadData = data.subdata(in: headerSize..<data.count)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: payloadData)
        } catch {
            throw AetherProtocolError.malformedJSON(error.localizedDescription)
        }
    }
}
