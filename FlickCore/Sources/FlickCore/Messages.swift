import Foundation

public enum HapticKind: UInt8, Sendable {
    case hit
    case miss
    case point
    case win
}

public enum ByeReason: UInt8, Sendable {
    case left
    case backgrounded
    case versionMismatch
    case gameFull
}

public enum Side: UInt8, CaseIterable, Sendable {
    case playerA
    case playerB
}

public enum GamePhase: UInt8, Sendable {
    case lobby
    case calibrating
    case ready
    case serving
    case rally
    case pointScored
    case paused
    case gameOver
}

public struct SwingMessage: Equatable, Sendable {
    public let peakAt: Microseconds
    public let strength: Float
    public let direction: SIMD3<Float>

    public init(peakAt: Microseconds, strength: Float, direction: SIMD3<Float>) {
        self.peakAt = peakAt
        self.strength = strength
        self.direction = direction
    }
}

public struct GameStateUpdate: Equatable, Sendable {
    public let phase: GamePhase
    public let scoreA: UInt8
    public let scoreB: UInt8
    public let side: Side
    public let serving: Side

    public init(phase: GamePhase, scoreA: UInt8, scoreB: UInt8, side: Side, serving: Side) {
        self.phase = phase
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.side = side
        self.serving = serving
    }
}

public enum Message: Equatable, Sendable {
    case hello(name: String)
    case helloAck(name: String)
    case calibrated(Sensitivity)
    case pointer(position: Float)
    case swing(SwingMessage)
    case ready(Bool)
    case ping
    case pong(pingSentAt: Microseconds, receivedAt: Microseconds)
    case haptic(HapticKind)
    case gameState(GameStateUpdate)
    case bye(ByeReason)

    public var channel: Channel {
        switch self {
        case .pointer, .ping, .pong: .unreliable
        default: .reliable
        }
    }
}

public struct Packet: Equatable, Sendable {
    public let sequence: UInt32
    public let sentAt: Microseconds
    public let message: Message

    public init(sequence: UInt32, sentAt: Microseconds, message: Message) {
        self.sequence = sequence
        self.sentAt = sentAt
        self.message = message
    }
}

public enum MessageDecodingError: Error, Equatable {
    case truncated
    case otherVersion(UInt8)
    case unknownType(UInt8)
    case invalidPayload
}

public enum SequenceNumber {
    public static func isNewer(_ candidate: UInt32, than reference: UInt32) -> Bool {
        Int32(bitPattern: candidate &- reference) > 0
    }
}
