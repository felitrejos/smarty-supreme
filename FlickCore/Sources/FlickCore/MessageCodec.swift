import Foundation

public enum MessageCodec {
    public static let protocolVersion: UInt8 = 1

    private enum TypeCode: UInt8 {
        case hello = 1
        case helloAck
        case calibrated
        case pointer
        case swing
        case ready
        case ping
        case pong
        case haptic
        case gameState
        case bye
    }

    public static func encode(_ packet: Packet) -> Data {
        var writer = ByteWriter()
        writer.append(protocolVersion)
        writer.append(typeCode(of: packet.message).rawValue)
        writer.append(packet.sequence)
        writer.append(packet.sentAt)
        writePayload(of: packet.message, into: &writer)
        return writer.data
    }

    public static func decode(_ data: Data) throws(MessageDecodingError) -> Packet {
        var reader = ByteReader(data)
        let version = try reader.byte()
        guard version == protocolVersion else { throw .otherVersion(version) }
        let rawType = try reader.byte()
        let sequence = try reader.uint32()
        let sentAt = try reader.uint64()
        guard let type = TypeCode(rawValue: rawType) else { throw .unknownType(rawType) }
        let message = try readPayload(of: type, from: &reader)
        guard reader.isAtEnd else { throw .invalidPayload }
        return Packet(sequence: sequence, sentAt: sentAt, message: message)
    }

    private static func typeCode(of message: Message) -> TypeCode {
        switch message {
        case .hello: .hello
        case .helloAck: .helloAck
        case .calibrated: .calibrated
        case .pointer: .pointer
        case .swing: .swing
        case .ready: .ready
        case .ping: .ping
        case .pong: .pong
        case .haptic: .haptic
        case .gameState: .gameState
        case .bye: .bye
        }
    }

    private static func writePayload(of message: Message, into writer: inout ByteWriter) {
        switch message {
        case .hello(let name), .helloAck(let name):
            writer.append(name)
        case .calibrated(let sensitivity):
            writer.append(UInt8(sensitivity.rangeDegrees))
        case .pointer(let position):
            writer.append(position)
        case .swing(let swing):
            writer.append(swing.peakAt)
            writer.append(swing.strength)
            writer.append(swing.direction.x)
            writer.append(swing.direction.y)
            writer.append(swing.direction.z)
        case .ready(let isReady):
            writer.append(UInt8(isReady ? 1 : 0))
        case .ping:
            break
        case .pong(let pingSentAt, let receivedAt):
            writer.append(pingSentAt)
            writer.append(receivedAt)
        case .haptic(let kind):
            writer.append(kind.rawValue)
        case .gameState(let state):
            writer.append(state.phase.rawValue)
            writer.append(state.scoreA)
            writer.append(state.scoreB)
            writer.append(state.side.rawValue)
            writer.append(state.serving.rawValue)
        case .bye(let reason):
            writer.append(reason.rawValue)
        }
    }

    private static func readPayload(of type: TypeCode, from reader: inout ByteReader) throws(MessageDecodingError) -> Message {
        switch type {
        case .hello:
            return .hello(name: try reader.string())
        case .helloAck:
            return .helloAck(name: try reader.string())
        case .calibrated:
            let degrees = try reader.byte()
            guard let sensitivity = Sensitivity.allCases.first(where: { UInt8($0.rangeDegrees) == degrees }) else {
                throw .invalidPayload
            }
            return .calibrated(sensitivity)
        case .pointer:
            return .pointer(position: try reader.unitFloat())
        case .swing:
            let peakAt = try reader.uint64()
            let strength = try reader.unitFloat()
            let direction = SIMD3(try reader.finiteFloat(), try reader.finiteFloat(), try reader.finiteFloat())
            return .swing(SwingMessage(peakAt: peakAt, strength: strength, direction: direction))
        case .ready:
            switch try reader.byte() {
            case 0: return .ready(false)
            case 1: return .ready(true)
            default: throw .invalidPayload
            }
        case .ping:
            return .ping
        case .pong:
            return .pong(pingSentAt: try reader.uint64(), receivedAt: try reader.uint64())
        case .haptic:
            return .haptic(try reader.enumeration(HapticKind.self))
        case .gameState:
            return .gameState(GameStateUpdate(
                phase: try reader.enumeration(GamePhase.self),
                scoreA: try reader.byte(),
                scoreB: try reader.byte(),
                side: try reader.enumeration(Side.self),
                serving: try reader.enumeration(Side.self)
            ))
        case .bye:
            return .bye(try reader.enumeration(ByeReason.self))
        }
    }
}

private struct ByteWriter {
    private(set) var data = Data()

    mutating func append(_ value: UInt8) {
        data.append(value)
    }

    mutating func append(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func append(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func append(_ value: Float) {
        append(value.bitPattern)
    }

    mutating func append(_ value: String) {
        let bytes = Array(value.utf8)
        precondition(bytes.count <= Int(UInt8.max), "Names are limited to 255 bytes")
        append(UInt8(bytes.count))
        data.append(contentsOf: bytes)
    }
}

private struct ByteReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    var isAtEnd: Bool {
        offset == bytes.count
    }

    mutating func byte() throws(MessageDecodingError) -> UInt8 {
        let slice = try take(1)
        return slice[slice.startIndex]
    }

    mutating func uint32() throws(MessageDecodingError) -> UInt32 {
        try take(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func uint64() throws(MessageDecodingError) -> UInt64 {
        try take(8).reversed().reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func finiteFloat() throws(MessageDecodingError) -> Float {
        let value = Float(bitPattern: try uint32())
        guard value.isFinite else { throw .invalidPayload }
        return value
    }

    mutating func unitFloat() throws(MessageDecodingError) -> Float {
        let value = try finiteFloat()
        guard (0...1).contains(value) else { throw .invalidPayload }
        return value
    }

    mutating func string() throws(MessageDecodingError) -> String {
        let length = Int(try byte())
        guard let text = String(validating: try take(length), as: UTF8.self) else { throw .invalidPayload }
        return text
    }

    mutating func enumeration<Value: RawRepresentable<UInt8>>(_ type: Value.Type) throws(MessageDecodingError) -> Value {
        guard let value = Value(rawValue: try byte()) else { throw .invalidPayload }
        return value
    }

    private mutating func take(_ count: Int) throws(MessageDecodingError) -> ArraySlice<UInt8> {
        guard bytes.count - offset >= count else { throw .truncated }
        defer { offset += count }
        return bytes[offset..<offset + count]
    }
}
