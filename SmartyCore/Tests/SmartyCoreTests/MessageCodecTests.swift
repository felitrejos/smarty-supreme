import SmartyCore
import Foundation
import Testing

struct MessageCodecTests {
    static let everyMessage: [Message] = [
        .hello(name: "Felipe's iPhone"),
        .helloAck(name: "MacBook Pro"),
        .calibrated,
        .pointer(position: 0.731),
        .swing(SwingMessage(peakAt: 9_876_543_210, strength: 0.42, direction: SIMD3(0.1, -0.5, 0.86))),
        .ready(true),
        .ready(false),
        .ping,
        .pong(pingSentAt: 1_000_000, receivedAt: 5_010_000),
        .haptic(.point),
        .gameState(GameStateUpdate(phase: .rally, scoreA: 7, scoreB: 10, side: .playerB, serving: .playerA, canResume: false, connectionIsSlow: true, winner: nil)),
        .gameState(GameStateUpdate(phase: .gameOver, scoreA: 5, scoreB: 3, side: .playerA, serving: .playerB, canResume: true, connectionIsSlow: false, winner: .playerB)),
        .bye(.gameFull),
        .viewerHello(name: "Studio Mac"),
        .pause(true),
        .pause(false),
        .snapshot(TableSnapshot(
            step: 9_000_000_001,
            ball: SIMD3(0.31, 0.72, 0.18),
            velocity: SIMD3(-0.4, 6.2, 1.1),
            spin: SIMD3(-210, 12, 3),
            paddleA: 0.18,
            paddleB: 0.44,
            phase: .rally,
            scoreA: 9,
            scoreB: 10,
            serving: .playerB,
            rally: 70_000,
            winner: .playerA
        )),
        .racket(RacketMessage(sampledAt: 77_000_123, orientation: SIMD4(0.1, -0.2, 0.3, 0.927), velocity: SIMD3(0.4, 5.5, 1.2))),
    ]

    @Test(arguments: everyMessage)
    func everyMessageRoundTrips(message: Message) throws {
        let packet = Packet(sequence: 4_000_000_001, sentAt: 123_456_789_012, message: message)
        #expect(try MessageCodec.decode(MessageCodec.encode(packet)) == packet)
    }

    @Test func pointerPacketIsEighteenBytes() {
        let packet = Packet(sequence: 1, sentAt: 2, message: .pointer(position: 0.5))
        #expect(MessageCodec.encode(packet).count == 18)
    }

    @Test func fieldsAreLittleEndianInTheDocumentedOrder() {
        let packet = Packet(sequence: 0x0403_0201, sentAt: 0x0C0B_0A09_0807_0605, message: .pointer(position: 1))
        let bytes = Array(MessageCodec.encode(packet))
        #expect(bytes == [MessageCodec.protocolVersion, 4, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 0x00, 0x00, 0x80, 0x3F])
    }

    @Test(arguments: everyMessage)
    func everyTruncatedPacketIsRejected(message: Message) {
        let bytes = MessageCodec.encode(Packet(sequence: 1, sentAt: 2, message: message))
        for length in 0..<bytes.count {
            #expect(throws: MessageDecodingError.truncated) {
                try MessageCodec.decode(bytes.prefix(length))
            }
        }
    }

    @Test func unknownTypeIsRejected() {
        var bytes = MessageCodec.encode(Packet(sequence: 1, sentAt: 2, message: .ping))
        bytes[1] = 99
        #expect(throws: MessageDecodingError.unknownType(99)) {
            try MessageCodec.decode(bytes)
        }
    }

    @Test func otherProtocolVersionIsRejected() {
        var bytes = MessageCodec.encode(Packet(sequence: 1, sentAt: 2, message: .ping))
        bytes[0] = MessageCodec.protocolVersion + 1
        #expect(throws: MessageDecodingError.otherVersion(MessageCodec.protocolVersion + 1)) {
            try MessageCodec.decode(bytes)
        }
    }

    @Test func extraBytesAfterThePayloadAreRejected() {
        var bytes = MessageCodec.encode(Packet(sequence: 1, sentAt: 2, message: .ping))
        bytes.append(0)
        #expect(throws: MessageDecodingError.invalidPayload) {
            try MessageCodec.decode(bytes)
        }
    }

    static let zeros8 = [UInt8](repeating: 0, count: 8)
    static let zeros12 = [UInt8](repeating: 0, count: 12)
    static let notANumber: [UInt8] = [0x00, 0x00, 0xC0, 0x7F]
    static let infinity: [UInt8] = [0x00, 0x00, 0x80, 0x7F]
    static let invalidPayloads: [(UInt8, [UInt8])] = [
        (6, [2]),
        (1, [1, 0x41, 9]),
        (9, [7]),
        (11, [200]),
        (1, [2, 0xFF, 0xFE, 0]),
        (4, notANumber),
        (4, [0x00, 0x00, 0xC0, 0x3F]),
        (4, [0x00, 0x00, 0x80, 0xBF]),
        (5, zeros8 + [0x00, 0x00, 0x00, 0x40] + zeros12),
        (5, zeros8 + notANumber + zeros12),
        (5, zeros8 + zeros8 + infinity + zeros8),
        (10, [4, 0, 0, 0, 0, 2, 0, 0xFF]),
        (10, [4, 0, 0, 0, 0, 0, 2, 0xFF]),
        (10, [4, 0, 0, 0, 0, 0, 0, 2]),
        (13, [2]),
        (14, zeros8 + notANumber + [UInt8](repeating: 0, count: 40) + [0, 0, 0, 0] + [0, 0, 0, 0, 0xFF]),
        (14, [UInt8](repeating: 0, count: 48) + infinity + [0, 0, 0, 0] + [0, 0, 0, 0, 0xFF]),
        (14, [UInt8](repeating: 0, count: 52) + [9, 0, 0, 0] + [0, 0, 0, 0, 0xFF]),
        (14, [UInt8](repeating: 0, count: 52) + [0, 0, 0, 0] + [0, 0, 0, 0, 3]),
        (15, zeros8 + notANumber + [UInt8](repeating: 0, count: 24)),
        (15, zeros8 + [UInt8](repeating: 0, count: 16) + infinity + zeros8),
    ]

    @Test(arguments: invalidPayloads)
    func payloadsOutsideTheirAllowedValuesAreRejected(type: UInt8, payload: [UInt8]) {
        let header: [UInt8] = [MessageCodec.protocolVersion, type, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0]
        #expect(throws: MessageDecodingError.invalidPayload) {
            try MessageCodec.decode(Data(header + payload))
        }
    }

    @Test(arguments: [
        (UInt32(1), UInt32.max, true),
        (UInt32.max, UInt32(1), false),
        (UInt32(5), UInt32(5), false),
        (UInt32(6), UInt32(5), true),
        (UInt32(0x8000_0000), UInt32(1), true),
    ])
    func sequenceComparisonHandlesWrapAround(candidate: UInt32, reference: UInt32, newer: Bool) {
        #expect(SequenceNumber.isNewer(candidate, than: reference) == newer)
    }
}
